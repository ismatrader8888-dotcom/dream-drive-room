REVOKE INSERT, UPDATE, DELETE ON TABLE public.profiles FROM anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.profiles FROM authenticated;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (phone) ON TABLE public.profiles TO authenticated;

REVOKE ALL ON FUNCTION public.admin_adjust_balance(uuid, text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_adjust_balance(uuid, text, numeric, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_adjust_demo_balance(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_adjust_demo_balance(uuid, numeric, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

COMMENT ON COLUMN public.profiles.demo_balance IS 'Security-critical credits balance. Updates are restricted to validated SECURITY DEFINER functions and privileged backend operations.';
COMMENT ON COLUMN public.profiles.reward_balance IS 'Security-critical rewards balance. Updates are restricted to validated SECURITY DEFINER functions and privileged backend operations.';