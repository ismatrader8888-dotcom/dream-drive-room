ALTER TABLE public.profiles
  ADD COLUMN blocked_at timestamp with time zone,
  ADD COLUMN blocked_reason text;

UPDATE public.profiles p
SET blocked_at = now(),
    blocked_reason = 'Automated abuse incident 2026-09-25: no confirmed deposit or administrator credit'
WHERE p.created_at >= timestamptz '2026-09-25 05:40:00+00'
  AND p.created_at < timestamptz '2026-09-25 06:20:00+00'
  AND NOT EXISTS (
    SELECT 1 FROM public.pix_charges pc
    WHERE pc.user_id = p.id
      AND (pc.credited_at IS NOT NULL OR pc.status = 'CONFIRMED')
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.balance_transactions bt
    WHERE bt.user_id = p.id
      AND bt.type = 'admin_adjustment'
      AND bt.amount > 0
  );

CREATE OR REPLACE FUNCTION public.is_account_active(_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT _user_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = _user_id AND blocked_at IS NULL
    )
$$;

REVOKE ALL ON FUNCTION public.is_account_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_account_active(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_blocked_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_account_active(auth.uid()) THEN
    RAISE EXCEPTION 'ACCOUNT_BLOCKED';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION public.reject_blocked_actor() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_blocked_actor() TO service_role;

CREATE TRIGGER reject_blocked_actor_admin_notifications
BEFORE INSERT OR UPDATE OR DELETE ON public.admin_notifications
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_admin_support_sessions
BEFORE INSERT OR UPDATE OR DELETE ON public.admin_support_sessions
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_balance_transactions
BEFORE INSERT OR UPDATE OR DELETE ON public.balance_transactions
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_daily_wheel_spins
BEFORE INSERT OR UPDATE OR DELETE ON public.daily_wheel_spins
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_notification_receipts
BEFORE INSERT OR UPDATE OR DELETE ON public.notification_receipts
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_pix_charges
BEFORE INSERT OR UPDATE OR DELETE ON public.pix_charges
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_pix_keys
BEFORE INSERT OR UPDATE OR DELETE ON public.pix_keys
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_profiles
BEFORE INSERT OR UPDATE OR DELETE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_recharge_requests
BEFORE INSERT OR UPDATE OR DELETE ON public.recharge_requests
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_redeem_code_uses
BEFORE INSERT OR UPDATE OR DELETE ON public.redeem_code_uses
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_redeem_codes
BEFORE INSERT OR UPDATE OR DELETE ON public.redeem_codes
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_referral_rewards
BEFORE INSERT OR UPDATE OR DELETE ON public.referral_rewards
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_referrals
BEFORE INSERT OR UPDATE OR DELETE ON public.referrals
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_user_roles
BEFORE INSERT OR UPDATE OR DELETE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_user_vehicles
BEFORE INSERT OR UPDATE OR DELETE ON public.user_vehicles
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_vehicle_reward_events
BEFORE INSERT OR UPDATE OR DELETE ON public.vehicle_reward_events
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();
CREATE TRIGGER reject_blocked_actor_withdrawal_requests
BEFORE INSERT OR UPDATE OR DELETE ON public.withdrawal_requests
FOR EACH ROW EXECUTE FUNCTION public.reject_blocked_actor();

CREATE POLICY "Blocked accounts denied admin notifications"
ON public.admin_notifications AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied support sessions"
ON public.admin_support_sessions AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied transactions"
ON public.balance_transactions AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied wheel spins"
ON public.daily_wheel_spins AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied notification receipts"
ON public.notification_receipts AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied pix charges"
ON public.pix_charges AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied pix keys"
ON public.pix_keys AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied profiles"
ON public.profiles AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied recharge requests"
ON public.recharge_requests AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied code uses"
ON public.redeem_code_uses AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied redeem codes"
ON public.redeem_codes AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied referral rewards"
ON public.referral_rewards AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied referrals"
ON public.referrals AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied roles"
ON public.user_roles AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied vehicles"
ON public.user_vehicles AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied vehicle rewards"
ON public.vehicle_reward_events AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));
CREATE POLICY "Blocked accounts denied withdrawals"
ON public.withdrawal_requests AS RESTRICTIVE FOR ALL TO authenticated
USING (public.is_account_active(auth.uid())) WITH CHECK (public.is_account_active(auth.uid()));

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_account_active(_user_id)
    AND EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = _user_id AND role = _role
    )
$$;

REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;

COMMENT ON COLUMN public.profiles.blocked_at IS 'Security block timestamp. Non-null accounts are denied all authenticated data access and writes.';
COMMENT ON COLUMN public.profiles.blocked_reason IS 'Audit reason for the account security block.';