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
      'id', p.id, 'email', p.email, 'phone', p.phone, 'createdAt', p.created_at, 'balance', p.demo_balance, 'rewardBalance', p.reward_balance,
      'vehicleRewardsToday', coalesce((SELECT sum(amount) FROM public.vehicle_reward_events e WHERE e.user_id = p.id AND e.earned_at >= date_trunc('day', now())), 0),
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
REVOKE ALL ON FUNCTION public.get_admin_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated, service_role;