import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const openSupportSchema = z.object({
  targetUserId: z.string().uuid(),
  userAgent: z.string().max(500).optional(),
});

const closeSupportSchema = z.object({ sessionId: z.string().uuid() });

export const openAdminSupportView = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => openSupportSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { data: isAdmin, error: roleError } = await context.supabase.rpc("has_role", {
      _user_id: context.userId,
      _role: "admin",
    });
    if (roleError || !isAdmin) throw new Error("FORBIDDEN");

    const args = data.userAgent
      ? { _target_user_id: data.targetUserId, _user_agent: data.userAgent }
      : { _target_user_id: data.targetUserId };
    const { data: supportView, error } = await context.supabase.rpc("admin_open_support_view", args);
    if (error) throw new Error("SUPPORT_VIEW_UNAVAILABLE");
    return supportView;
  });

export const closeAdminSupportView = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => closeSupportSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { data: isAdmin, error: roleError } = await context.supabase.rpc("has_role", {
      _user_id: context.userId,
      _role: "admin",
    });
    if (roleError || !isAdmin) throw new Error("FORBIDDEN");

    const { error } = await context.supabase.rpc("admin_close_support_view", {
      _session_id: data.sessionId,
    });
    if (error) throw new Error("SUPPORT_SESSION_CLOSE_FAILED");
    return { ok: true };
  });

export const getAdminAccountReport = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ targetUserId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { data: isAdmin, error: roleError } = await context.supabase.rpc("has_role", {
      _user_id: context.userId, _role: "admin",
    });
    if (roleError || !isAdmin) throw new Error("FORBIDDEN");

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: profile, error: profileError } = await supabaseAdmin.from("profiles")
      .select("id,email,phone,invite_code,referred_by,created_at,demo_balance,reward_balance")
      .eq("id", data.targetUserId).maybeSingle();
    if (profileError || !profile) throw new Error("USER_NOT_FOUND");

    // Page each collection so the PDF does not silently omit records after the API's row limit.
    async function allRows<T>(fetchPage: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>): Promise<T[]> {
      const rows: T[] = [];
      for (let from = 0; ; from += 500) {
        const { data: page, error } = await fetchPage(from, from + 499);
        if (error) throw new Error("REPORT_UNAVAILABLE");
        rows.push(...(page ?? []));
        if (!page || page.length < 500) break;
      }
      return rows;
    }

    const [vehicles, pixCharges, withdrawals, transactions, referrals] = await Promise.all([
      allRows((from, to) => supabaseAdmin.from("user_vehicles").select("id,name,region,plate,purchase_price,reward_per_cycle,cycles_completed,contract_cycles,purchased_at,next_reward_at,completed_at").eq("user_id", profile.id).order("purchased_at", { ascending: false }).range(from, to)),
      allRows((from, to) => supabaseAdmin.from("pix_charges").select("id,amount,status,payer_name,provider_magic_id,created_at,credited_at").eq("user_id", profile.id).order("created_at", { ascending: false }).range(from, to)),
      allRows((from, to) => supabaseAdmin.from("withdrawal_requests").select("id,amount,status,full_name,pix_key,created_at,reviewed_at").eq("user_id", profile.id).order("created_at", { ascending: false }).range(from, to)),
      allRows((from, to) => supabaseAdmin.from("balance_transactions").select("id,type,amount,balance_after,description,created_at").eq("user_id", profile.id).order("created_at", { ascending: false }).range(from, to)),
      allRows((from, to) => supabaseAdmin.from("referrals").select("id,referred_user_id,invite_code,effective_at,total_confirmed_deposits,total_deposited,referrer_bonus_total,created_at").eq("referrer_id", profile.id).order("created_at", { ascending: false }).range(from, to)),
    ]);

    const invitedIds = referrals.map((r) => r.referred_user_id);
    // Keep filters short enough for URL limits when a member has hundreds of invites.
    const invitedProfiles: Array<{ id: string; email: string | null; created_at: string }> = [];
    const invitedDeposits: Array<{ id: string; user_id: string; amount: number; status: string; created_at: string; credited_at: string | null }> = [];
    for (let start = 0; start < invitedIds.length; start += 75) {
      const ids = invitedIds.slice(start, start + 75);
      const [profilesPage, depositsPage] = await Promise.all([
        allRows((from, to) => supabaseAdmin.from("profiles")
          .select("id,email,created_at").in("id", ids).order("created_at").range(from, to)),
        allRows((from, to) => supabaseAdmin.from("pix_charges")
          .select("id,user_id,amount,status,created_at,credited_at").in("user_id", ids)
          .eq("status", "CONFIRMED").order("created_at", { ascending: false }).range(from, to)),
      ]);
      invitedProfiles.push(...profilesPage);
      invitedDeposits.push(...depositsPage);
    }

    return { profile, vehicles, pixCharges, withdrawals, transactions, referrals, invitedProfiles, invitedDeposits, generatedAt: new Date().toISOString() };
  });