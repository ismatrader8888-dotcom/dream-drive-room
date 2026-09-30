ALTER TABLE public.vehicle_catalog
ADD COLUMN min_owned_vehicles integer NOT NULL DEFAULT 0;

ALTER TABLE public.vehicle_catalog
ADD CONSTRAINT vehicle_catalog_min_owned_vehicles_nonnegative
CHECK (min_owned_vehicles >= 0);

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