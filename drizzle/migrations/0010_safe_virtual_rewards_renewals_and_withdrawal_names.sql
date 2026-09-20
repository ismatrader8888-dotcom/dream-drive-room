ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS full_name text NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION public.process_vehicle_rewards_for(_user_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  vehicle_record record;
  due_cycles integer;
  inserted_cycles integer;
  processed_total integer := 0;
  earned_amount numeric(12,2);
  next_balance numeric(12,2);
BEGIN
  FOR vehicle_record IN
    SELECT id, name, purchased_at, reward_per_cycle, contract_cycles, cycles_completed
    FROM public.user_vehicles
    WHERE user_id = _user_id AND cycles_completed < contract_cycles
    FOR UPDATE
  LOOP
    due_cycles := LEAST(
      vehicle_record.contract_cycles - vehicle_record.cycles_completed,
      GREATEST(0, floor(extract(epoch FROM (now() - vehicle_record.purchased_at)) / 86400)::integer - vehicle_record.cycles_completed)
    );
    IF due_cycles > 0 THEN
      INSERT INTO public.vehicle_reward_events(vehicle_id, user_id, cycle_number, amount, status, earned_at, transferred_at)
      SELECT vehicle_record.id, _user_id, cycle_no, vehicle_record.reward_per_cycle, 'transferred',
             vehicle_record.purchased_at + (cycle_no * interval '24 hours'), now()
      FROM generate_series(vehicle_record.cycles_completed + 1, vehicle_record.cycles_completed + due_cycles) AS cycle_no
      ON CONFLICT (vehicle_id, cycle_number) DO NOTHING;
      GET DIAGNOSTICS inserted_cycles = ROW_COUNT;
      earned_amount := inserted_cycles * vehicle_record.reward_per_cycle;
      IF inserted_cycles > 0 THEN
        UPDATE public.user_vehicles
        SET cycles_completed = cycles_completed + inserted_cycles,
            pending_reward = 0,
            transferred_reward = transferred_reward + earned_amount,
            next_reward_at = CASE WHEN cycles_completed + inserted_cycles >= contract_cycles THEN NULL ELSE purchased_at + ((cycles_completed + inserted_cycles + 1) * interval '24 hours') END,
            completed_at = CASE WHEN cycles_completed + inserted_cycles >= contract_cycles THEN now() ELSE completed_at END
        WHERE id = vehicle_record.id;
        UPDATE public.profiles
        SET demo_balance = demo_balance + earned_amount
        WHERE id = _user_id
        RETURNING demo_balance INTO next_balance;
        INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
        VALUES(_user_id, 'vehicle_reward', earned_amount, next_balance, 'Créditos virtuais de ' || vehicle_record.name, vehicle_record.id);
        processed_total := processed_total + inserted_cycles;
      END IF;
    END IF;
  END LOOP;
  RETURN processed_total;
END;
$$;
REVOKE ALL ON FUNCTION public.process_vehicle_rewards_for(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_vehicle_rewards_for(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.transfer_my_vehicle_rewards()
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  PERFORM public.process_vehicle_rewards_for(auth.uid());
  RETURN 0;
END;
$$;
REVOKE ALL ON FUNCTION public.transfer_my_vehicle_rewards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_my_vehicle_rewards() TO authenticated;

CREATE OR REPLACE FUNCTION public.renew_vehicle(_vehicle_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
$$;
REVOKE ALL ON FUNCTION public.renew_vehicle(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.renew_vehicle(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text, _full_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE request_id uuid; current_balance numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 OR length(trim(_full_name)) < 5 THEN RAISE EXCEPTION 'INVALID_WITHDRAWAL'; END IF;
  SELECT reward_balance INTO current_balance FROM public.profiles WHERE id = auth.uid();
  IF current_balance < _amount THEN RAISE EXCEPTION 'INSUFFICIENT_REWARD_BALANCE'; END IF;
  IF EXISTS (SELECT 1 FROM public.withdrawal_requests WHERE user_id = auth.uid() AND status = 'pending') THEN RAISE EXCEPTION 'PENDING_WITHDRAWAL_EXISTS'; END IF;
  INSERT INTO public.withdrawal_requests(user_id, amount, pix_key, full_name)
  VALUES(auth.uid(), _amount, trim(_pix_key), trim(_full_name)) RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.request_withdrawal(numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_withdrawal(numeric, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result jsonb; profile_record record;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  FOR profile_record IN SELECT id FROM public.profiles LOOP PERFORM public.process_vehicle_rewards_for(profile_record.id); END LOOP;
  SELECT jsonb_build_object(
    'users', (SELECT count(*) FROM public.profiles),
    'gameCredits', (SELECT coalesce(sum(demo_balance), 0) FROM public.profiles),
    'rewardBalance', (SELECT coalesce(sum(reward_balance), 0) FROM public.profiles),
    'vehicleRewardsGenerated', (SELECT coalesce(sum(amount), 0) FROM public.vehicle_reward_events),
    'vehicleRewardsPending', 0,
    'vehicleRewardsTransferred', (SELECT coalesce(sum(amount), 0) FROM public.vehicle_reward_events),
    'purchases', (SELECT count(*) FROM public.user_vehicles),
    'pendingWithdrawals', (SELECT count(*) FROM public.withdrawal_requests WHERE status = 'pending'),
    'pendingPix', (SELECT count(*) FROM public.pix_charges WHERE status IN ('CREATING','PENDING')),
    'totalReferrals', (SELECT count(*) FROM public.referrals),
    'effectiveReferrals', (SELECT count(*) FROM public.referrals WHERE effective_at IS NOT NULL),
    'referredDepositVolume', (SELECT coalesce(sum(total_deposited), 0) FROM public.referrals),
    'referralCreditsDistributed', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards),
    'profiles', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'email', p.email, 'phone', p.phone, 'balance', p.demo_balance, 'rewardBalance', p.reward_balance,
      'vehicleRewardsGenerated', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id), 0),
      'vehicleRewardsPending', 0,
      'vehicleRewardsTransferred', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id), 0),
      'inviteCode', p.invite_code, 'referredBy', p.referred_by,
      'referrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id),
      'effectiveReferrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id AND r.effective_at IS NOT NULL),
      'referralBonus', (SELECT coalesce(sum(r.referrer_bonus_total), 0) FROM public.referrals r WHERE r.referrer_id = p.id)
    ) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'referrals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'referrerEmail', owner.email, 'referredEmail', invited.email, 'inviteCode', r.invite_code, 'status', CASE WHEN r.effective_at IS NULL THEN 'invalid' ELSE 'effective' END, 'joinedAt', r.created_at, 'effectiveAt', r.effective_at, 'firstDeposit', r.first_deposit_amount, 'deposits', r.total_confirmed_deposits, 'totalDeposited', r.total_deposited, 'refereeBonus', r.referee_bonus_total, 'referrerBonus', r.referrer_bonus_total) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.referrals r JOIN public.profiles owner ON owner.id = r.referrer_id JOIN public.profiles invited ON invited.id = r.referred_user_id),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'fullName', w.full_name, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'pixCharges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'userId', c.user_id, 'email', p.email, 'payerName', c.payer_name, 'amount', c.amount, 'status', c.status, 'magicId', c.provider_magic_id, 'createdAt', c.created_at, 'creditedAt', c.credited_at, 'refereeBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referee_first_deposit'), 0), 'referrerBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referrer_commission'), 0)) ORDER BY c.created_at DESC), '[]'::jsonb) FROM public.pix_charges c JOIN public.profiles p ON p.id = c.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated;