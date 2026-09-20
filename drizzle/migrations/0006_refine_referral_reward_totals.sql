CREATE OR REPLACE FUNCTION public.get_my_referral_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  SELECT jsonb_build_object(
    'totalMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid()),
    'effectiveMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid() AND effective_at IS NOT NULL),
    'totalDeposited', (SELECT coalesce(sum(total_deposited), 0) FROM public.referrals WHERE referrer_id = auth.uid()),
    'teamEarned', (SELECT coalesce(sum(referrer_bonus_total), 0) FROM public.referrals WHERE referrer_id = auth.uid()),
    'totalEarned', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid()),
    'earnedToday', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type = 'referrer_commission'),
    'depositedToday', (SELECT coalesce(sum(deposit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type = 'referrer_commission'),
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
$$;
REVOKE ALL ON FUNCTION public.get_my_referral_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_referral_dashboard() TO authenticated;