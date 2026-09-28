-- Account-owned financial data is read-only through the Data API. Trusted SECURITY DEFINER functions remain the only write path.
REVOKE ALL ON TABLE public.profiles, public.balance_transactions, public.withdrawal_requests, public.recharge_requests, public.user_roles, public.daily_wheel_spins, public.redeem_code_uses, public.referral_rewards, public.referrals, public.vehicle_reward_events FROM anon, authenticated;
GRANT SELECT ON TABLE public.profiles, public.balance_transactions, public.withdrawal_requests, public.recharge_requests, public.user_roles, public.daily_wheel_spins, public.redeem_code_uses, public.referral_rewards, public.referrals, public.vehicle_reward_events TO authenticated;
GRANT UPDATE (phone) ON TABLE public.profiles TO authenticated;
-- No direct withdrawal submission or review: request_withdrawal and admin_review_withdrawal own those paths.
-- Protect blocked state even if broader privileges are mistakenly restored later.
CREATE OR REPLACE FUNCTION public.guard_profile_self_service_updates()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated') AND (
    NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email OR
    NEW.invite_code IS DISTINCT FROM OLD.invite_code OR NEW.referred_by IS DISTINCT FROM OLD.referred_by OR
    NEW.level IS DISTINCT FROM OLD.level OR NEW.balance IS DISTINCT FROM OLD.balance OR
    NEW.demo_balance IS DISTINCT FROM OLD.demo_balance OR NEW.reward_balance IS DISTINCT FROM OLD.reward_balance OR
    NEW.created_at IS DISTINCT FROM OLD.created_at OR
    NEW.signup_bonus_granted_at IS DISTINCT FROM OLD.signup_bonus_granted_at OR
    NEW.welcome_bonus_seen_at IS DISTINCT FROM OLD.welcome_bonus_seen_at OR
    NEW.invite_task_rewarded_at IS DISTINCT FROM OLD.invite_task_rewarded_at OR
    NEW.blocked_at IS DISTINCT FROM OLD.blocked_at OR NEW.blocked_reason IS DISTINCT FROM OLD.blocked_reason
  ) THEN RAISE EXCEPTION 'PROTECTED_PROFILE_FIELD'; END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_profile_self_service_updates() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_profile_self_service_updates() TO service_role;
-- The old overload remains callable: hold it to the same guarded implementation.
CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'USE_FULL_NAME_WITHDRAWAL';
END;
$$;
REVOKE ALL ON FUNCTION public.request_withdrawal(numeric,text) FROM PUBLIC, anon, authenticated;
-- Deny arbitrary impersonation in role checks made from a regular user's session.
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_account_active(_user_id) AND EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role
  )
$$;