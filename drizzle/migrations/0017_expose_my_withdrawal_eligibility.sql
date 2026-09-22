CREATE OR REPLACE FUNCTION public.get_my_withdrawal_eligibility()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  generated_rewards numeric(12,2);
  minimum_exempt_user constant uuid := '6c9ea3d7-7172-4aee-a14f-4d01dc50377e'::uuid;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT coalesce(sum(amount), 0) INTO generated_rewards
  FROM public.vehicle_reward_events
  WHERE user_id = current_user_id;

  RETURN jsonb_build_object(
    'eligible', current_user_id = minimum_exempt_user OR generated_rewards >= 30,
    'exempt', current_user_id = minimum_exempt_user,
    'generatedRewards', generated_rewards,
    'minimumRewards', 30
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_withdrawal_eligibility() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_withdrawal_eligibility() TO authenticated, service_role;