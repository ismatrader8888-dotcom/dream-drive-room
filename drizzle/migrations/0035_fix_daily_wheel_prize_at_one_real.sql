CREATE OR REPLACE FUNCTION public.spin_daily_wheel()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  last_spin timestamptz;
  prize_amount numeric(12,2) := 1.00;
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

REVOKE ALL ON FUNCTION public.spin_daily_wheel() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.spin_daily_wheel() TO authenticated, service_role;