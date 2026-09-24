CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  normalized_code text := nullif(upper(trim(new.raw_user_meta_data ->> 'referred_by')), '');
  referrer uuid;
  generated_code text;
BEGIN
  IF normalized_code IS NOT NULL THEN
    SELECT id INTO referrer FROM public.profiles WHERE invite_code = normalized_code;
    IF referrer IS NULL THEN RAISE EXCEPTION 'INVALID_INVITE_CODE'; END IF;
  END IF;

  LOOP
    generated_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE invite_code = generated_code);
  END LOOP;

  INSERT INTO public.profiles (
    id, email, phone, invite_code, referred_by, reward_balance,
    signup_bonus_granted_at, welcome_bonus_seen_at
  )
  VALUES (
    new.id, new.email, new.raw_user_meta_data ->> 'phone', generated_code,
    normalized_code, 15, now(), null
  )
  ON CONFLICT (id) DO NOTHING;

  IF FOUND THEN
    INSERT INTO public.balance_transactions(
      user_id, type, amount, balance_after, description
    ) VALUES (
      new.id, 'signup_bonus', 15, 15, 'Bônus de cadastro em Prêmios disponíveis'
    );
  END IF;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, CASE WHEN lower(new.email) = 'maloneadm@adm.com' THEN 'admin'::public.app_role ELSE 'user'::public.app_role END)
  ON CONFLICT DO NOTHING;

  IF referrer IS NOT NULL THEN
    INSERT INTO public.referrals (referrer_id, referred_user_id, invite_code)
    VALUES (referrer, new.id, normalized_code)
    ON CONFLICT (referred_user_id) DO NOTHING;
  END IF;
  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text, _full_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  request_id uuid;
  current_balance numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 OR length(trim(_full_name)) < 5 THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL';
  END IF;

  PERFORM public.process_vehicle_rewards_for(auth.uid());

  SELECT reward_balance INTO current_balance
  FROM public.profiles
  WHERE id = auth.uid()
  FOR UPDATE;

  IF current_balance < 30 THEN RAISE EXCEPTION 'MIN_REWARD_BALANCE_REQUIRED'; END IF;
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
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL';
  END IF;

  PERFORM public.process_vehicle_rewards_for(auth.uid());

  SELECT reward_balance INTO current_balance
  FROM public.profiles
  WHERE id = auth.uid()
  FOR UPDATE;

  IF current_balance < 30 THEN RAISE EXCEPTION 'MIN_REWARD_BALANCE_REQUIRED'; END IF;
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

CREATE OR REPLACE FUNCTION public.get_my_withdrawal_eligibility()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  current_balance numeric(12,2);
BEGIN
  IF current_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT reward_balance INTO current_balance
  FROM public.profiles
  WHERE id = current_user_id;

  RETURN jsonb_build_object(
    'eligible', coalesce(current_balance, 0) >= 30,
    'exempt', false,
    'rewardBalance', coalesce(current_balance, 0),
    'minimumBalance', 30
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_withdrawal_eligibility() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_withdrawal_eligibility() TO authenticated, service_role;