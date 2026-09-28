import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const recoveryRequest = z.object({
  targetUserId: z.string().uuid(),
  email: z.string().trim().email().max(254),
  phone: z.string().trim().min(8).max(30),
});

export const generatePasswordRecoveryLink = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => recoveryRequest.parse(input))
  .handler(async ({ data, context }) => {
    const { data: isAdmin, error: roleError } = await context.supabase.rpc("has_role", {
      _user_id: context.userId,
      _role: "admin",
    });
    if (roleError || !isAdmin) throw new Error("FORBIDDEN");

    const { data: profile, error: profileError } = await context.supabase
      .from("profiles")
      .select("id, email, phone, blocked_at")
      .eq("id", data.targetUserId)
      .maybeSingle();
    if (profileError || !profile || profile.blocked_at || !profile.email || !profile.phone ||
        profile.email.trim().toLowerCase() !== data.email.toLowerCase() ||
        profile.phone.replace(/\D/g, "") !== data.phone.replace(/\D/g, "")) {
      throw new Error("DETAILS_MISMATCH");
    }

    // Never return a recovery token until an authenticated admin has passed every check.
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: recent, error: recentError } = await supabaseAdmin
      .from("admin_password_recovery_links")
      .select("id")
      .eq("target_user_id", profile.id)
      .gte("created_at", new Date(Date.now() - 5 * 60_000).toISOString())
      .limit(1);
    if (recentError) throw new Error("RECOVERY_UNAVAILABLE");
    if (recent?.length) throw new Error("TOO_SOON");

    const { data: generated, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
      type: "recovery",
      email: profile.email,
      options: { redirectTo: "https://drivingyoudreamsss.online/reset-password" },
    });
    if (linkError || !generated.properties?.action_link || generated.user?.id !== profile.id) {
      throw new Error("RECOVERY_UNAVAILABLE");
    }

    const { error: auditError } = await supabaseAdmin.from("admin_password_recovery_links").insert({
      admin_id: context.userId,
      target_user_id: profile.id,
    });
    if (auditError) throw new Error("RECOVERY_UNAVAILABLE");

    return { link: generated.properties.action_link };
  });