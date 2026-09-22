CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text, _full_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  request_id uuid;
  current_balance numeric(12,2);
  generated_rewards numeric(12,2);
  minimum_exempt_user constant uuid := '6c9ea3d7-7172-4aee-a14f-4d01dc50377e'::uuid;
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 OR length(trim(_full_name)) < 5 THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL';
  END IF;

  PERFORM public.process_vehicle_rewards_for(auth.uid());

  SELECT coalesce(sum(amount), 0) INTO generated_rewards
  FROM public.vehicle_reward_events
  WHERE user_id = auth.uid();

  IF auth.uid() <> minimum_exempt_user AND generated_rewards < 30 THEN
    RAISE EXCEPTION 'MIN_TOTAL_REWARDS_REQUIRED';
  END IF;

  SELECT reward_balance INTO current_balance FROM public.profiles WHERE id = auth.uid();
  IF current_balance < _amount THEN RAISE EXCEPTION 'INSUFFICIENT_REWARD_BALANCE'; END IF;
  IF EXISTS (SELECT 1 FROM public.withdrawal_requests WHERE user_id = auth.uid() AND status = 'pending') THEN RAISE EXCEPTION 'PENDING_WITHDRAWAL_EXISTS'; END IF;

  INSERT INTO public.withdrawal_requests(user_id, amount, pix_key, full_name)
  VALUES(auth.uid(), _amount, trim(_pix_key), trim(_full_name))
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_withdrawal(numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_withdrawal(numeric, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  request_id uuid;
  current_balance numeric(12,2);
  generated_rewards numeric(12,2);
  minimum_exempt_user constant uuid := '6c9ea3d7-7172-4aee-a14f-4d01dc50377e'::uuid;
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL';
  END IF;

  PERFORM public.process_vehicle_rewards_for(auth.uid());

  SELECT coalesce(sum(amount), 0) INTO generated_rewards
  FROM public.vehicle_reward_events
  WHERE user_id = auth.uid();

  IF auth.uid() <> minimum_exempt_user AND generated_rewards < 30 THEN
    RAISE EXCEPTION 'MIN_TOTAL_REWARDS_REQUIRED';
  END IF;

  SELECT reward_balance INTO current_balance FROM public.profiles WHERE id = auth.uid();
  IF current_balance < _amount THEN RAISE EXCEPTION 'INSUFFICIENT_REWARD_BALANCE'; END IF;
  IF EXISTS (SELECT 1 FROM public.withdrawal_requests WHERE user_id = auth.uid() AND status = 'pending') THEN RAISE EXCEPTION 'PENDING_WITHDRAWAL_EXISTS'; END IF;

  INSERT INTO public.withdrawal_requests(user_id, amount, pix_key, full_name)
  VALUES(auth.uid(), _amount, trim(_pix_key), 'Titular não informado')
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_withdrawal(numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_withdrawal(numeric, text) TO authenticated, service_role;