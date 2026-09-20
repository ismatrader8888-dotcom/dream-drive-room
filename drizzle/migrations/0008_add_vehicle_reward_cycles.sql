ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'vehicle_reward';
ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'reward_transfer';

ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS reward_per_cycle numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS contract_cycles integer NOT NULL DEFAULT 25;
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS cycles_completed integer NOT NULL DEFAULT 0;
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS pending_reward numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS transferred_reward numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS next_reward_at timestamptz;
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS completed_at timestamptz;

UPDATE public.user_vehicles uv
SET reward_per_cycle = coalesce(vc.daily_amount, 0),
    contract_cycles = coalesce(vc.cycle_days, 25),
    next_reward_at = uv.purchased_at + interval '24 hours'
FROM public.vehicle_catalog vc
WHERE uv.catalog_id = vc.id
  AND (uv.reward_per_cycle = 0 OR uv.next_reward_at IS NULL);

ALTER TABLE public.user_vehicles ADD CONSTRAINT user_vehicles_reward_per_cycle_nonnegative CHECK (reward_per_cycle >= 0);
ALTER TABLE public.user_vehicles ADD CONSTRAINT user_vehicles_contract_cycles_positive CHECK (contract_cycles > 0);
ALTER TABLE public.user_vehicles ADD CONSTRAINT user_vehicles_cycles_completed_valid CHECK (cycles_completed >= 0 AND cycles_completed <= contract_cycles);
ALTER TABLE public.user_vehicles ADD CONSTRAINT user_vehicles_pending_reward_nonnegative CHECK (pending_reward >= 0);
ALTER TABLE public.user_vehicles ADD CONSTRAINT user_vehicles_transferred_reward_nonnegative CHECK (transferred_reward >= 0);

CREATE TABLE public.vehicle_reward_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.user_vehicles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cycle_number integer NOT NULL CHECK (cycle_number > 0),
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'transferred')),
  earned_at timestamptz NOT NULL,
  transferred_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(vehicle_id, cycle_number)
);
GRANT SELECT ON public.vehicle_reward_events TO authenticated;
GRANT ALL ON public.vehicle_reward_events TO service_role;
ALTER TABLE public.vehicle_reward_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own vehicle rewards" ON public.vehicle_reward_events FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins read all vehicle rewards" ON public.vehicle_reward_events FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE INDEX vehicle_reward_events_user_created_idx ON public.vehicle_reward_events(user_id, created_at DESC);
CREATE INDEX vehicle_reward_events_pending_idx ON public.vehicle_reward_events(user_id, status) WHERE status = 'pending';

CREATE OR REPLACE FUNCTION public.process_vehicle_rewards_for(_user_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  vehicle_record record;
  due_cycles integer;
  inserted_cycles integer;
  processed_total integer := 0;
  earned_amount numeric(12,2);
BEGIN
  FOR vehicle_record IN
    SELECT id, purchased_at, reward_per_cycle, contract_cycles, cycles_completed
    FROM public.user_vehicles
    WHERE user_id = _user_id AND cycles_completed < contract_cycles
    FOR UPDATE
  LOOP
    due_cycles := LEAST(
      vehicle_record.contract_cycles - vehicle_record.cycles_completed,
      GREATEST(0, floor(extract(epoch FROM (now() - vehicle_record.purchased_at)) / 86400)::integer - vehicle_record.cycles_completed)
    );
    IF due_cycles > 0 THEN
      INSERT INTO public.vehicle_reward_events(vehicle_id, user_id, cycle_number, amount, earned_at)
      SELECT vehicle_record.id, _user_id, cycle_no, vehicle_record.reward_per_cycle,
             vehicle_record.purchased_at + (cycle_no * interval '24 hours')
      FROM generate_series(vehicle_record.cycles_completed + 1, vehicle_record.cycles_completed + due_cycles) AS cycle_no
      ON CONFLICT (vehicle_id, cycle_number) DO NOTHING;
      GET DIAGNOSTICS inserted_cycles = ROW_COUNT;
      earned_amount := inserted_cycles * vehicle_record.reward_per_cycle;
      UPDATE public.user_vehicles
      SET cycles_completed = cycles_completed + inserted_cycles,
          pending_reward = pending_reward + earned_amount,
          next_reward_at = CASE WHEN cycles_completed + inserted_cycles >= contract_cycles THEN NULL ELSE purchased_at + ((cycles_completed + inserted_cycles + 1) * interval '24 hours') END,
          completed_at = CASE WHEN cycles_completed + inserted_cycles >= contract_cycles THEN now() ELSE completed_at END
      WHERE id = vehicle_record.id;
      processed_total := processed_total + inserted_cycles;
    END IF;
  END LOOP;
  RETURN processed_total;
END;
$$;
REVOKE ALL ON FUNCTION public.process_vehicle_rewards_for(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_vehicle_rewards_for(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.process_my_vehicle_rewards()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  RETURN public.process_vehicle_rewards_for(auth.uid());
END;
$$;
REVOKE ALL ON FUNCTION public.process_my_vehicle_rewards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_my_vehicle_rewards() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_reward_summary()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  PERFORM public.process_vehicle_rewards_for(auth.uid());
  SELECT jsonb_build_object(
    'available', p.reward_balance,
    'today', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events WHERE user_id = p.id AND (earned_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date), 0),
    'total', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events WHERE user_id = p.id), 0),
    'pending', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events WHERE user_id = p.id AND status = 'pending'), 0),
    'transferred', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events WHERE user_id = p.id AND status = 'transferred'), 0),
    'cyclesCompleted', coalesce((SELECT sum(cycles_completed) FROM public.user_vehicles WHERE user_id = p.id), 0),
    'cyclesTotal', coalesce((SELECT sum(contract_cycles) FROM public.user_vehicles WHERE user_id = p.id), 0),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'vehicleId', e.vehicle_id, 'vehicleName', uv.name, 'cycle', e.cycle_number, 'amount', e.amount, 'status', e.status, 'earnedAt', e.earned_at, 'transferredAt', e.transferred_at) ORDER BY e.earned_at DESC) FROM public.vehicle_reward_events e JOIN public.user_vehicles uv ON uv.id = e.vehicle_id WHERE e.user_id = p.id), '[]'::jsonb)
  ) INTO result FROM public.profiles p WHERE p.id = auth.uid();
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_reward_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_reward_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.transfer_my_vehicle_rewards()
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE transfer_amount numeric(12,2); next_balance numeric(12,2);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  PERFORM public.process_vehicle_rewards_for(auth.uid());
  SELECT coalesce(sum(amount), 0) INTO transfer_amount FROM public.vehicle_reward_events WHERE user_id = auth.uid() AND status = 'pending' FOR UPDATE;
  IF transfer_amount <= 0 THEN RETURN 0; END IF;
  UPDATE public.vehicle_reward_events SET status = 'transferred', transferred_at = now() WHERE user_id = auth.uid() AND status = 'pending';
  UPDATE public.user_vehicles SET pending_reward = 0, transferred_reward = transferred_reward + transfer_amount WHERE user_id = auth.uid() AND pending_reward > 0;
  UPDATE public.profiles SET reward_balance = reward_balance + transfer_amount WHERE id = auth.uid() RETURNING reward_balance INTO next_balance;
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description)
  VALUES(auth.uid(), 'reward_transfer', transfer_amount, next_balance, 'Transferência de recompensas dos veículos');
  RETURN transfer_amount;
END;
$$;
REVOKE ALL ON FUNCTION public.transfer_my_vehicle_rewards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_my_vehicle_rewards() TO authenticated;

CREATE OR REPLACE FUNCTION public.purchase_vehicle(_catalog_id text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item public.vehicle_catalog%ROWTYPE; current_balance numeric(12,2); new_vehicle_id uuid; new_plate text;
BEGIN
  SELECT * INTO item FROM public.vehicle_catalog WHERE id = _catalog_id AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'VEHICLE_NOT_FOUND'; END IF;
  SELECT demo_balance INTO current_balance FROM public.profiles WHERE id = auth.uid() FOR UPDATE;
  IF current_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF current_balance < item.price THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
  new_plate := 'VX' || (12178 + (SELECT count(*) FROM public.user_vehicles WHERE user_id = auth.uid()))::text;
  UPDATE public.profiles SET demo_balance = demo_balance - item.price WHERE id = auth.uid();
  INSERT INTO public.user_vehicles (user_id, catalog_id, name, region, daily, return_value, price, purchase_price, cycle, image_key, plate, reward_per_cycle, contract_cycles, next_reward_at)
  VALUES (auth.uid(), item.id, item.name, item.region, 'R$ ' || replace(to_char(item.daily_amount, 'FM999999990D00'), '.', ',') || '/dia', 'R$ ' || replace(to_char(item.return_amount, 'FM999999990D00'), '.', ','), 'R$ ' || replace(to_char(item.price, 'FM999999990D00'), '.', ','), item.price, item.cycle_days || ' dias úteis', item.image_key, new_plate, item.daily_amount, item.cycle_days, now() + interval '24 hours')
  RETURNING id INTO new_vehicle_id;
  INSERT INTO public.balance_transactions (user_id, type, amount, balance_after, description, reference_id)
  VALUES (auth.uid(), 'vehicle_purchase', -item.price, current_balance - item.price, 'Aluguel de ' || item.name, new_vehicle_id);
  RETURN new_vehicle_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.purchase_vehicle(text) TO authenticated;

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
    'vehicleRewardsPending', (SELECT coalesce(sum(amount), 0) FROM public.vehicle_reward_events WHERE status = 'pending'),
    'vehicleRewardsTransferred', (SELECT coalesce(sum(amount), 0) FROM public.vehicle_reward_events WHERE status = 'transferred'),
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
      'vehicleRewardsPending', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id AND e.status = 'pending'), 0),
      'vehicleRewardsTransferred', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id AND e.status = 'transferred'), 0),
      'inviteCode', p.invite_code, 'referredBy', p.referred_by,
      'referrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id),
      'effectiveReferrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id AND r.effective_at IS NOT NULL),
      'referralBonus', (SELECT coalesce(sum(r.referrer_bonus_total), 0) FROM public.referrals r WHERE r.referrer_id = p.id)
    ) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'referrals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'referrerEmail', owner.email, 'referredEmail', invited.email, 'inviteCode', r.invite_code, 'status', CASE WHEN r.effective_at IS NULL THEN 'invalid' ELSE 'effective' END, 'joinedAt', r.created_at, 'effectiveAt', r.effective_at, 'firstDeposit', r.first_deposit_amount, 'deposits', r.total_confirmed_deposits, 'totalDeposited', r.total_deposited, 'refereeBonus', r.referee_bonus_total, 'referrerBonus', r.referrer_bonus_total) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.referrals r JOIN public.profiles owner ON owner.id = r.referrer_id JOIN public.profiles invited ON invited.id = r.referred_user_id),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'pixCharges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'userId', c.user_id, 'email', p.email, 'payerName', c.payer_name, 'amount', c.amount, 'status', c.status, 'magicId', c.provider_magic_id, 'createdAt', c.created_at, 'creditedAt', c.credited_at, 'refereeBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referee_first_deposit'), 0), 'referrerBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referrer_commission'), 0)) ORDER BY c.created_at DESC), '[]'::jsonb) FROM public.pix_charges c JOIN public.profiles p ON p.id = c.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated;