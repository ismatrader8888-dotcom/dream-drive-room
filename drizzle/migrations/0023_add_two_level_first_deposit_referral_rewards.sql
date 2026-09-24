ALTER TABLE public.referral_rewards
  DROP CONSTRAINT referral_rewards_reward_type_check;

ALTER TABLE public.referral_rewards
  ADD CONSTRAINT referral_rewards_reward_type_check
  CHECK (reward_type IN ('referee_first_deposit', 'referrer_commission', 'second_level_commission'));

CREATE OR REPLACE FUNCTION public.confirm_pix_charge(_external_ref text, _magic_id text, _amount numeric, _provider_updated_at timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  charge public.pix_charges%ROWTYPE;
  direct_referral public.referrals%ROWTYPE;
  parent_referral public.referrals%ROWTYPE;
  next_balance numeric(12,2);
  direct_balance numeric(12,2);
  second_level_balance numeric(12,2);
  referee_bonus numeric(12,2);
  direct_bonus numeric(12,2);
  second_level_bonus numeric(12,2);
  is_first_deposit boolean;
BEGIN
  SELECT * INTO charge FROM public.pix_charges WHERE external_ref = _external_ref FOR UPDATE;
  IF NOT FOUND OR charge.provider_magic_id IS DISTINCT FROM _magic_id OR charge.amount <> _amount THEN RAISE EXCEPTION 'INVALID_PIX_CHARGE'; END IF;
  IF charge.credited_at IS NOT NULL THEN RETURN false; END IF;

  PERFORM 1 FROM public.profiles WHERE id = charge.user_id FOR UPDATE;
  SELECT NOT EXISTS (
    SELECT 1 FROM public.pix_charges
    WHERE user_id = charge.user_id AND credited_at IS NOT NULL AND id <> charge.id
  ) INTO is_first_deposit;

  SELECT * INTO direct_referral FROM public.referrals WHERE referred_user_id = charge.user_id FOR UPDATE;
  IF direct_referral.id IS NOT NULL THEN
    SELECT * INTO parent_referral
    FROM public.referrals
    WHERE referred_user_id = direct_referral.referrer_id
    FOR UPDATE;
  END IF;

  referee_bonus := CASE WHEN direct_referral.id IS NOT NULL AND is_first_deposit THEN round(charge.amount * 0.05, 2) ELSE 0 END;
  direct_bonus := CASE WHEN direct_referral.id IS NOT NULL AND is_first_deposit THEN round(charge.amount * 0.08, 2) ELSE 0 END;
  second_level_bonus := CASE WHEN parent_referral.id IS NOT NULL AND is_first_deposit THEN round(charge.amount * 0.03, 2) ELSE 0 END;

  UPDATE public.profiles
  SET demo_balance = demo_balance + charge.amount + referee_bonus
  WHERE id = charge.user_id
  RETURNING demo_balance INTO next_balance;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  UPDATE public.pix_charges
  SET status = 'CONFIRMED', credited_at = now(), provider_updated_at = _provider_updated_at, updated_at = now()
  WHERE id = charge.id;

  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
  VALUES(charge.user_id, 'recharge', charge.amount, next_balance - referee_bonus, 'Créditos do jogo via PIX', charge.id);

  IF referee_bonus > 0 THEN
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, charge.user_id, 'referee_first_deposit', charge.amount, 5, referee_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(charge.user_id, 'referral_bonus', referee_bonus, next_balance, 'Bônus de 5% no primeiro depósito indicado', charge.id);
  END IF;

  IF direct_bonus > 0 THEN
    UPDATE public.profiles
    SET demo_balance = demo_balance + direct_bonus
    WHERE id = direct_referral.referrer_id
    RETURNING demo_balance INTO direct_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, direct_referral.referrer_id, 'referrer_commission', charge.amount, 8, direct_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(direct_referral.referrer_id, 'referral_bonus', direct_bonus, direct_balance, 'Bônus de 8% no primeiro depósito do indicado direto', charge.id);
  END IF;

  IF second_level_bonus > 0 THEN
    UPDATE public.profiles
    SET demo_balance = demo_balance + second_level_bonus
    WHERE id = parent_referral.referrer_id
    RETURNING demo_balance INTO second_level_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, parent_referral.referrer_id, 'second_level_commission', charge.amount, 3, second_level_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(parent_referral.referrer_id, 'referral_bonus', second_level_bonus, second_level_balance, 'Bônus de 3% no primeiro depósito do indicado de nível 2', charge.id);
  END IF;

  IF direct_referral.id IS NOT NULL THEN
    UPDATE public.referrals
    SET effective_at = coalesce(effective_at, now()),
        first_deposit_amount = coalesce(first_deposit_amount, charge.amount),
        total_confirmed_deposits = total_confirmed_deposits + 1,
        total_deposited = total_deposited + charge.amount,
        referee_bonus_total = referee_bonus_total + referee_bonus,
        referrer_bonus_total = referrer_bonus_total + direct_bonus
    WHERE id = direct_referral.id;
  END IF;

  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.confirm_pix_charge(text, text, numeric, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pix_charge(text, text, numeric, timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.get_my_referral_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  SELECT jsonb_build_object(
    'totalMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid()),
    'effectiveMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid() AND effective_at IS NOT NULL),
    'totalDeposited', (SELECT coalesce(sum(total_deposited), 0) FROM public.referrals WHERE referrer_id = auth.uid()),
    'teamEarned', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND reward_type IN ('referrer_commission', 'second_level_commission')),
    'totalEarned', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid()),
    'earnedToday', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type IN ('referrer_commission', 'second_level_commission')),
    'depositedToday', (SELECT coalesce(sum(deposit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type IN ('referrer_commission', 'second_level_commission')),
    'members', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id,
      'displayName', coalesce(nullif(split_part(p.email, '@', 1), ''), regexp_replace(coalesce(p.phone, ''), '.(?=.{4})', '*', 'g'), 'Jogador'),
      'status', CASE WHEN r.effective_at IS NULL THEN 'invalid' ELSE 'effective' END,
      'joinedAt', r.created_at,
      'effectiveAt', r.effective_at,
      'firstDeposit', r.first_deposit_amount,
      'deposits', r.total_confirmed_deposits,
      'totalDeposited', r.total_deposited,
      'bonusEarned', r.referrer_bonus_total
    ) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.referrals r JOIN public.profiles p ON p.id = r.referred_user_id WHERE r.referrer_id = auth.uid()),
    'rewards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', rw.id,
      'type', rw.reward_type,
      'depositAmount', rw.deposit_amount,
      'percentage', rw.percentage,
      'creditAmount', rw.credit_amount,
      'createdAt', rw.created_at,
      'memberName', coalesce(nullif(split_part(p.email, '@', 1), ''), 'Jogador')
    ) ORDER BY rw.created_at DESC), '[]'::jsonb)
    FROM public.referral_rewards rw
    JOIN public.referrals r ON r.id = rw.referral_id
    JOIN public.profiles p ON p.id = r.referred_user_id
    WHERE rw.beneficiary_id = auth.uid())
  ) INTO result;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_referral_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_referral_dashboard() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
      'id', p.id, 'email', p.email, 'phone', p.phone, 'createdAt', p.created_at, 'balance', p.demo_balance, 'rewardBalance', p.reward_balance,
      'vehicleRewardsToday', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id AND e.earned_at >= date_trunc('day', now())), 0),
      'vehicleRewardsGenerated', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id), 0),
      'vehicleRewardsPending', 0,
      'vehicleRewardsTransferred', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id), 0),
      'inviteCode', p.invite_code, 'referredBy', p.referred_by,
      'referrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id),
      'effectiveReferrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id AND r.effective_at IS NOT NULL),
      'referralBonus', (SELECT coalesce(sum(rw.credit_amount), 0) FROM public.referral_rewards rw WHERE rw.beneficiary_id = p.id AND rw.reward_type IN ('referrer_commission', 'second_level_commission'))
    ) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'referrals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'referrerEmail', owner.email, 'referredEmail', invited.email, 'inviteCode', r.invite_code, 'status', CASE WHEN r.effective_at IS NULL THEN 'invalid' ELSE 'effective' END, 'joinedAt', r.created_at, 'effectiveAt', r.effective_at, 'firstDeposit', r.first_deposit_amount, 'deposits', r.total_confirmed_deposits, 'totalDeposited', r.total_deposited, 'refereeBonus', r.referee_bonus_total, 'referrerBonus', r.referrer_bonus_total) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.referrals r JOIN public.profiles owner ON owner.id = r.referrer_id JOIN public.profiles invited ON invited.id = r.referred_user_id),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'fullName', w.full_name, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'pixCharges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'userId', c.user_id, 'email', p.email, 'payerName', c.payer_name, 'amount', c.amount, 'status', c.status, 'magicId', c.provider_magic_id, 'createdAt', c.created_at, 'creditedAt', c.credited_at, 'refereeBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referee_first_deposit'), 0), 'referrerBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referrer_commission'), 0), 'secondLevelBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'second_level_commission'), 0)) ORDER BY c.created_at DESC), '[]'::jsonb) FROM public.pix_charges c JOIN public.profiles p ON p.id = c.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_admin_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated;