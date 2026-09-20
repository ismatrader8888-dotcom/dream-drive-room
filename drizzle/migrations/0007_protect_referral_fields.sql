CREATE OR REPLACE FUNCTION public.protect_profile_referral_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.invite_code IS DISTINCT FROM OLD.invite_code OR NEW.referred_by IS DISTINCT FROM OLD.referred_by THEN
    RAISE EXCEPTION 'REFERRAL_FIELDS_IMMUTABLE';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER protect_profile_referral_fields_before_update
BEFORE UPDATE ON public.profiles
FOR EACH ROW
WHEN (OLD.invite_code IS DISTINCT FROM NEW.invite_code OR OLD.referred_by IS DISTINCT FROM NEW.referred_by)
EXECUTE FUNCTION public.protect_profile_referral_fields();

GRANT UPDATE ON public.profiles TO authenticated;