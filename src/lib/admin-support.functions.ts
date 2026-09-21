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