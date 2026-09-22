ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'signup_bonus';
ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'daily_spin';

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS signup_bonus_granted_at timestamptz,
  ADD COLUMN IF NOT EXISTS welcome_bonus_seen_at timestamptz;

CREATE TABLE public.daily_wheel_spins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  prize numeric(12,2) NOT NULL CHECK (prize IN (1, 2, 5)),
  spun_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.daily_wheel_spins TO authenticated;
GRANT ALL ON public.daily_wheel_spins TO service_role;

ALTER TABLE public.daily_wheel_spins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own wheel spins"
ON public.daily_wheel_spins
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins read all wheel spins"
ON public.daily_wheel_spins
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE INDEX daily_wheel_spins_user_spun_at_idx
ON public.daily_wheel_spins(user_id, spun_at DESC);

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
    id, email, phone, invite_code, referred_by, demo_balance,
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
      new.id, 'signup_bonus', 15, 15, 'Bônus de cadastro'
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

CREATE OR REPLACE FUNCTION public.consume_welcome_bonus_popup()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE should_show boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;

  UPDATE public.profiles
  SET welcome_bonus_seen_at = now()
  WHERE id = auth.uid()
    AND signup_bonus_granted_at IS NOT NULL
    AND welcome_bonus_seen_at IS NULL
  RETURNING true INTO should_show;

  RETURN coalesce(should_show, false);
END;
$function$;

REVOKE ALL ON FUNCTION public.consume_welcome_bonus_popup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_welcome_bonus_popup() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_my_daily_wheel_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE last_spin timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;

  SELECT spun_at INTO last_spin
  FROM public.daily_wheel_spins
  WHERE user_id = auth.uid()
  ORDER BY spun_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'canSpin', last_spin IS NULL OR last_spin + interval '24 hours' <= now(),
    'nextSpinAt', CASE WHEN last_spin IS NULL THEN NULL ELSE last_spin + interval '24 hours' END,
    'lastPrize', (SELECT prize FROM public.daily_wheel_spins WHERE user_id = auth.uid() ORDER BY spun_at DESC LIMIT 1)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_daily_wheel_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_daily_wheel_state() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.spin_daily_wheel()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  last_spin timestamptz;
  prize_amount numeric(12,2);
  next_balance numeric(12,2);
  spin_id uuid;
  spun_time timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;

  PERFORM 1 FROM public.profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  SELECT spun_at INTO last_spin
  FROM public.daily_wheel_spins
  WHERE user_id = auth.uid()
  ORDER BY spun_at DESC
  LIMIT 1;

  IF last_spin IS NOT NULL AND last_spin + interval '24 hours' > spun_time THEN
    RAISE EXCEPTION 'WHEEL_COOLDOWN';
  END IF;

  prize_amount := (ARRAY[1, 2, 5])[1 + floor(random() * 3)::integer];

  INSERT INTO public.daily_wheel_spins(user_id, prize, spun_at)
  VALUES(auth.uid(), prize_amount, spun_time)
  RETURNING id INTO spin_id;

  UPDATE public.profiles
  SET demo_balance = demo_balance + prize_amount
  WHERE id = auth.uid()
  RETURNING demo_balance INTO next_balance;

  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
  VALUES(auth.uid(), 'daily_spin', prize_amount, next_balance, 'Prêmio da roleta diária', spin_id);

  RETURN jsonb_build_object(
    'prize', prize_amount,
    'nextSpinAt', spun_time + interval '24 hours',
    'balance', next_balance
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.spin_daily_wheel() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spin_daily_wheel() TO authenticated, service_role;

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
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 OR length(trim(_full_name)) < 5 THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL';
  END IF;

  PERFORM public.process_vehicle_rewards_for(auth.uid());

  SELECT coalesce(sum(amount), 0) INTO generated_rewards
  FROM public.vehicle_reward_events
  WHERE user_id = auth.uid();

  IF generated_rewards < 30 THEN
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