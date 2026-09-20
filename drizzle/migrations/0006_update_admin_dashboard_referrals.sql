-- Update get_admin_dashboard to include effective referrals count
CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT jsonb_build_object(
    'users', (SELECT count(*) FROM public.profiles),
    'gameCredits', (SELECT coalesce(sum(demo_balance), 0) FROM public.profiles),
    'rewardBalance', (SELECT coalesce(sum(reward_balance), 0) FROM public.profiles),
    'purchases', (SELECT count(*) FROM public.user_vehicles),
    'pendingWithdrawals', (SELECT count(*) FROM public.withdrawal_requests WHERE status = 'pending'),
    'pendingPix', (SELECT count(*) FROM public.pix_charges WHERE status IN ('CREATING','PENDING')),
    'profiles', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 
      'email', p.email, 
      'phone', p.phone, 
      'balance', p.demo_balance, 
      'rewardBalance', p.reward_balance, 
      'inviteCode', p.invite_code, 
      'referrals', (SELECT count(*) FROM public.profiles r WHERE upper(r.referred_by) = upper(p.invite_code)),
      'effectiveReferrals', (
        SELECT count(*) FROM public.profiles r 
        WHERE upper(r.referred_by) = upper(p.invite_code) 
        AND EXISTS (SELECT 1 FROM public.pix_charges pc WHERE pc.user_id = r.id AND pc.status = 'CONFIRMED')
      )
    ) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'pixCharges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'userId', c.user_id, 'email', p.email, 'payerName', c.payer_name, 'amount', c.amount, 'status', c.status, 'magicId', c.provider_magic_id, 'createdAt', c.created_at, 'creditedAt', c.credited_at) ORDER BY c.created_at DESC), '[]'::jsonb) FROM public.pix_charges c JOIN public.profiles p ON p.id = c.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$$;
