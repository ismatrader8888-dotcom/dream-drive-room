CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, phone, invite_code, referred_by)
  VALUES (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'phone',
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    nullif(upper(trim(new.raw_user_meta_data ->> 'referred_by')), '')
  )
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, CASE WHEN lower(new.email) = 'maloneadm@adm.com' THEN 'admin'::public.app_role ELSE 'user'::public.app_role END)
  ON CONFLICT DO NOTHING;
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT jsonb_build_object(
    'users', (SELECT count(*) FROM public.profiles),
    'demoBalance', (SELECT coalesce(sum(demo_balance), 0) FROM public.profiles),
    'purchases', (SELECT count(*) FROM public.user_vehicles),
    'pendingWithdrawals', (SELECT count(*) FROM public.withdrawal_requests WHERE status = 'pending'),
    'pendingRecharges', (SELECT count(*) FROM public.recharge_requests WHERE status = 'pending'),
    'profiles', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email, 'phone', p.phone, 'balance', p.demo_balance, 'inviteCode', p.invite_code, 'referrals', (SELECT count(*) FROM public.profiles r WHERE upper(r.referred_by) = upper(p.invite_code))) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'recharges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'userId', r.user_id, 'email', p.email, 'amount', r.amount, 'status', r.status, 'createdAt', r.created_at) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.recharge_requests r JOIN public.profiles p ON p.id = r.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated;