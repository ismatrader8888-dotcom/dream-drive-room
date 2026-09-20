ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS reward_balance numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_reward_balance_nonnegative CHECK (reward_balance >= 0);

CREATE TABLE public.pix_charges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  external_ref text NOT NULL UNIQUE,
  provider_magic_id text UNIQUE,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  payer_name text NOT NULL,
  document_suffix text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('CREATING','PENDING','CONFIRMED','FAILED','EXPIRED','REFUNDED','DISPUTE_NEEDS_RESPONSE','DISPUTE_IN_REVIEW','DISPUTE_WON','DISPUTE_LOST')),
  qr_code text,
  expires_at timestamptz NOT NULL,
  credited_at timestamptz,
  provider_updated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.pix_charges TO authenticated;
GRANT ALL ON public.pix_charges TO service_role;
ALTER TABLE public.pix_charges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own pix charges" ON public.pix_charges FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users create own pix charges" ON public.pix_charges FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'CREATING');
CREATE POLICY "Users update creating pix charges" ON public.pix_charges FOR UPDATE TO authenticated USING (auth.uid() = user_id AND status = 'CREATING') WITH CHECK (auth.uid() = user_id AND status IN ('PENDING','FAILED'));
CREATE POLICY "Admins read all pix charges" ON public.pix_charges FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE INDEX pix_charges_user_created_idx ON public.pix_charges(user_id, created_at DESC);
CREATE INDEX pix_charges_status_idx ON public.pix_charges(status, created_at DESC);

CREATE OR REPLACE FUNCTION public.confirm_pix_charge(_external_ref text, _magic_id text, _amount numeric, _provider_updated_at timestamptz DEFAULT now())
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE charge public.pix_charges%ROWTYPE; next_balance numeric(12,2);
BEGIN
  SELECT * INTO charge FROM public.pix_charges WHERE external_ref = _external_ref FOR UPDATE;
  IF NOT FOUND OR charge.provider_magic_id IS DISTINCT FROM _magic_id OR charge.amount <> _amount THEN RAISE EXCEPTION 'INVALID_PIX_CHARGE'; END IF;
  IF charge.credited_at IS NOT NULL THEN RETURN false; END IF;
  UPDATE public.profiles SET demo_balance = demo_balance + charge.amount WHERE id = charge.user_id RETURNING demo_balance INTO next_balance;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  UPDATE public.pix_charges SET status = 'CONFIRMED', credited_at = now(), provider_updated_at = _provider_updated_at, updated_at = now() WHERE id = charge.id;
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
  VALUES(charge.user_id, 'recharge', charge.amount, next_balance, 'Créditos do jogo via PIX', charge.id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_pix_charge(text, text, numeric, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pix_charge(text, text, numeric, timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.update_pix_charge_status(_external_ref text, _magic_id text, _status text, _provider_updated_at timestamptz DEFAULT now())
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF _status NOT IN ('PENDING','FAILED','EXPIRED','REFUNDED','DISPUTE_NEEDS_RESPONSE','DISPUTE_IN_REVIEW','DISPUTE_WON','DISPUTE_LOST') THEN RAISE EXCEPTION 'INVALID_PIX_STATUS'; END IF;
  UPDATE public.pix_charges SET status = _status, provider_updated_at = _provider_updated_at, updated_at = now()
  WHERE external_ref = _external_ref AND provider_magic_id = _magic_id AND credited_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.update_pix_charge_status(text, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_pix_charge_status(text, text, text, timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE request_id uuid; current_balance numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 THEN RAISE EXCEPTION 'INVALID_WITHDRAWAL'; END IF;
  SELECT reward_balance INTO current_balance FROM public.profiles WHERE id = auth.uid();
  IF current_balance < _amount THEN RAISE EXCEPTION 'INSUFFICIENT_REWARD_BALANCE'; END IF;
  IF EXISTS (SELECT 1 FROM public.withdrawal_requests WHERE user_id = auth.uid() AND status = 'pending') THEN RAISE EXCEPTION 'PENDING_WITHDRAWAL_EXISTS'; END IF;
  INSERT INTO public.withdrawal_requests(user_id, amount, pix_key) VALUES(auth.uid(), _amount, trim(_pix_key)) RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.request_withdrawal(numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_review_withdrawal(_request_id uuid, _approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req public.withdrawal_requests%ROWTYPE; current_balance numeric(12,2); next_balance numeric(12,2);
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO req FROM public.withdrawal_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND OR req.status <> 'pending' THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  IF _approve THEN
    SELECT reward_balance INTO current_balance FROM public.profiles WHERE id = req.user_id FOR UPDATE;
    IF current_balance < req.amount THEN RAISE EXCEPTION 'INSUFFICIENT_REWARD_BALANCE'; END IF;
    UPDATE public.profiles SET reward_balance = reward_balance - req.amount WHERE id = req.user_id RETURNING reward_balance INTO next_balance;
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id, created_by) VALUES(req.user_id, 'withdrawal', -req.amount, next_balance, 'Saque de prêmio aprovado', req.id, auth.uid());
  END IF;
  UPDATE public.withdrawal_requests SET status = CASE WHEN _approve THEN 'approved'::public.request_status ELSE 'rejected'::public.request_status END, reviewed_by = auth.uid(), reviewed_at = now() WHERE id = _request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_review_withdrawal(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_adjust_balance(_user_id uuid, _wallet text, _amount numeric, _reason text)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE next_balance numeric(12,2);
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF _wallet NOT IN ('credits','rewards') OR _amount = 0 OR length(trim(_reason)) < 3 THEN RAISE EXCEPTION 'INVALID_ADJUSTMENT'; END IF;
  IF _wallet = 'credits' THEN
    UPDATE public.profiles SET demo_balance = demo_balance + _amount WHERE id = _user_id AND demo_balance + _amount >= 0 RETURNING demo_balance INTO next_balance;
  ELSE
    UPDATE public.profiles SET reward_balance = reward_balance + _amount WHERE id = _user_id AND reward_balance + _amount >= 0 RETURNING reward_balance INTO next_balance;
  END IF;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'INVALID_BALANCE'; END IF;
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, created_by) VALUES(_user_id, 'admin_adjustment', _amount, next_balance, upper(_wallet) || ': ' || trim(_reason), auth.uid());
  RETURN next_balance;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_adjust_balance(uuid, text, numeric, text) TO authenticated;

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
    'profiles', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email, 'phone', p.phone, 'balance', p.demo_balance, 'rewardBalance', p.reward_balance, 'inviteCode', p.invite_code, 'referrals', (SELECT count(*) FROM public.profiles r WHERE upper(r.referred_by) = upper(p.invite_code))) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'pixCharges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'userId', c.user_id, 'email', p.email, 'payerName', c.payer_name, 'amount', c.amount, 'status', c.status, 'magicId', c.provider_magic_id, 'createdAt', c.created_at, 'creditedAt', c.credited_at) ORDER BY c.created_at DESC), '[]'::jsonb) FROM public.pix_charges c JOIN public.profiles p ON p.id = c.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated;