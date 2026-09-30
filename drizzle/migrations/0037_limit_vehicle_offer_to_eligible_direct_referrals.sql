ALTER TABLE public.vehicle_catalog ADD COLUMN eligible_referrer_id uuid;

CREATE OR REPLACE FUNCTION public.is_limited_offer_eligible(_catalog_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.vehicle_catalog c
    JOIN public.referrals r ON r.referrer_id = c.eligible_referrer_id AND r.referred_user_id = auth.uid()
    WHERE c.id = _catalog_id
      AND c.active = true
      AND c.eligible_referrer_id IS NOT NULL
      AND auth.uid() IS NOT NULL
      AND public.is_account_active(auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.user_vehicles v
        WHERE v.user_id = auth.uid() AND v.image_key <> 'charging'
      )
  );
$$;
REVOKE ALL ON FUNCTION public.is_limited_offer_eligible(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_limited_offer_eligible(text) TO authenticated;

ALTER POLICY "Anyone reads active catalog" ON public.vehicle_catalog
USING ((active AND eligible_referrer_id IS NULL) OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Eligible players read their limited offer"
ON public.vehicle_catalog FOR SELECT TO authenticated
USING (eligible_referrer_id IS NOT NULL AND public.is_limited_offer_eligible(id));

CREATE OR REPLACE FUNCTION public.purchase_vehicle(_catalog_id text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  item public.vehicle_catalog%ROWTYPE;
  current_balance numeric(12,2);
  owned_vehicle_count integer;
  new_vehicle_id uuid;
  new_plate text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  IF NOT public.is_account_active(auth.uid()) THEN RAISE EXCEPTION 'ACCOUNT_BLOCKED'; END IF;

  SELECT * INTO item
  FROM public.vehicle_catalog
  WHERE id = _catalog_id AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'VEHICLE_NOT_FOUND'; END IF;

  IF item.eligible_referrer_id IS NOT NULL AND NOT public.is_limited_offer_eligible(item.id) THEN
    RAISE EXCEPTION 'LIMITED_OFFER_NOT_ELIGIBLE';
  END IF;

  SELECT count(*) INTO owned_vehicle_count
  FROM public.user_vehicles
  WHERE user_id = auth.uid();
  IF owned_vehicle_count < item.min_owned_vehicles THEN
    RAISE EXCEPTION 'VEHICLE_OWNERSHIP_REQUIRED';
  END IF;

  SELECT demo_balance INTO current_balance
  FROM public.profiles
  WHERE id = auth.uid()
  FOR UPDATE;
  IF current_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF current_balance < item.price THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  new_plate := 'VX' || (12178 + owned_vehicle_count)::text;
  UPDATE public.profiles
  SET demo_balance = demo_balance - item.price
  WHERE id = auth.uid();

  INSERT INTO public.user_vehicles (
    user_id, catalog_id, name, region, daily, return_value, price,
    purchase_price, cycle, image_key, plate, reward_per_cycle,
    contract_cycles, next_reward_at
  )
  VALUES (
    auth.uid(), item.id, item.name, item.region,
    'R$ ' || replace(to_char(item.daily_amount, 'FM999999990D00'), '.', ',') || '/dia',
    'R$ ' || replace(to_char(item.return_amount, 'FM999999990D00'), '.', ','),
    'R$ ' || replace(to_char(item.price, 'FM999999990D00'), '.', ','),
    item.price, item.cycle_days || ' ciclos', item.image_key, new_plate,
    item.daily_amount, item.cycle_days, now() + interval '24 hours'
  )
  RETURNING id INTO new_vehicle_id;

  INSERT INTO public.balance_transactions (
    user_id, type, amount, balance_after, description, reference_id
  )
  VALUES (
    auth.uid(), 'vehicle_purchase', -item.price, current_balance - item.price,
    'Aluguel de ' || item.name, new_vehicle_id
  );

  RETURN new_vehicle_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.renew_vehicle(_vehicle_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  previous_vehicle public.user_vehicles%ROWTYPE;
  item public.vehicle_catalog%ROWTYPE;
  current_balance numeric(12,2);
  new_vehicle_id uuid;
  new_plate text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  PERFORM public.process_vehicle_rewards_for(auth.uid());
  SELECT * INTO previous_vehicle FROM public.user_vehicles
  WHERE id = _vehicle_id AND user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'VEHICLE_NOT_FOUND'; END IF;
  IF previous_vehicle.cycles_completed < previous_vehicle.contract_cycles THEN RAISE EXCEPTION 'CONTRACT_ACTIVE'; END IF;
  SELECT * INTO item FROM public.vehicle_catalog WHERE id = previous_vehicle.catalog_id AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'VEHICLE_NOT_AVAILABLE'; END IF;
  IF item.eligible_referrer_id IS NOT NULL AND NOT public.is_limited_offer_eligible(item.id) THEN
    RAISE EXCEPTION 'LIMITED_OFFER_NOT_ELIGIBLE';
  END IF;
  SELECT demo_balance INTO current_balance FROM public.profiles WHERE id = auth.uid() FOR UPDATE;
  IF current_balance < item.price THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
  new_plate := 'VX' || (12178 + (SELECT count(*) FROM public.user_vehicles WHERE user_id = auth.uid()))::text;
  UPDATE public.profiles SET demo_balance = demo_balance - item.price WHERE id = auth.uid();
  INSERT INTO public.user_vehicles (user_id, catalog_id, name, region, daily, return_value, price, purchase_price, cycle, image_key, plate, reward_per_cycle, contract_cycles, next_reward_at)
  VALUES (auth.uid(), item.id, item.name, item.region, 'R$ ' || replace(to_char(item.daily_amount, 'FM999999990D00'), '.', ',') || '/dia', 'R$ ' || replace(to_char(item.return_amount, 'FM999999990D00'), '.', ','), 'R$ ' || replace(to_char(item.price, 'FM999999990D00'), '.', ','), item.price, item.cycle_days || ' ciclos', item.image_key, new_plate, item.daily_amount, item.cycle_days, now() + interval '24 hours')
  RETURNING id INTO new_vehicle_id;
  INSERT INTO public.balance_transactions (user_id, type, amount, balance_after, description, reference_id)
  VALUES (auth.uid(), 'vehicle_purchase', -item.price, current_balance - item.price, 'Renovação de ' || item.name, new_vehicle_id);
  RETURN new_vehicle_id;
END;
$function$;