CREATE OR REPLACE FUNCTION public.guard_profile_self_service_updates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated') AND (
    NEW.id IS DISTINCT FROM OLD.id OR
    NEW.email IS DISTINCT FROM OLD.email OR
    NEW.invite_code IS DISTINCT FROM OLD.invite_code OR
    NEW.referred_by IS DISTINCT FROM OLD.referred_by OR
    NEW.level IS DISTINCT FROM OLD.level OR
    NEW.balance IS DISTINCT FROM OLD.balance OR
    NEW.demo_balance IS DISTINCT FROM OLD.demo_balance OR
    NEW.reward_balance IS DISTINCT FROM OLD.reward_balance OR
    NEW.created_at IS DISTINCT FROM OLD.created_at OR
    NEW.signup_bonus_granted_at IS DISTINCT FROM OLD.signup_bonus_granted_at OR
    NEW.welcome_bonus_seen_at IS DISTINCT FROM OLD.welcome_bonus_seen_at OR
    NEW.invite_task_rewarded_at IS DISTINCT FROM OLD.invite_task_rewarded_at
  ) THEN
    RAISE EXCEPTION 'PROTECTED_PROFILE_FIELD';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_profile_self_service_updates() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_profile_self_service_updates() TO service_role;

CREATE TRIGGER guard_profile_self_service_updates_before_update
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.guard_profile_self_service_updates();