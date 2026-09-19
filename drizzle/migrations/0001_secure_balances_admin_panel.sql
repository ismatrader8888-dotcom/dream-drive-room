CREATE TYPE public.request_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE public.ledger_type AS ENUM ('recharge', 'vehicle_purchase', 'withdrawal', 'admin_adjustment');

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS demo_balance numeric(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_demo_balance_nonnegative CHECK (demo_balance >= 0);

CREATE TABLE public.vehicle_catalog (
  id text PRIMARY KEY,
  name text NOT NULL,
  region text NOT NULL,
  daily_amount numeric(12,2) NOT NULL CHECK (daily_amount >= 0),
  return_amount numeric(12,2) NOT NULL CHECK (return_amount >= 0),
  price numeric(12,2) NOT NULL CHECK (price > 0),
  cycle_days integer NOT NULL DEFAULT 25 CHECK (cycle_days > 0),
  image_key text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.vehicle_catalog TO anon, authenticated;
GRANT ALL ON public.vehicle_catalog TO service_role;
ALTER TABLE public.vehicle_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone reads active catalog" ON public.vehicle_catalog FOR SELECT TO anon, authenticated USING (active OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage catalog" ON public.vehicle_catalog FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS catalog_id text REFERENCES public.vehicle_catalog(id);
ALTER TABLE public.user_vehicles ADD COLUMN IF NOT EXISTS purchase_price numeric(12,2);

CREATE TABLE public.balance_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type public.ledger_type NOT NULL,
  amount numeric(12,2) NOT NULL,
  balance_after numeric(12,2) NOT NULL CHECK (balance_after >= 0),
  description text NOT NULL,
  reference_id uuid,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.balance_transactions TO authenticated;
GRANT ALL ON public.balance_transactions TO service_role;
ALTER TABLE public.balance_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own transactions" ON public.balance_transactions FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins read all transactions" ON public.balance_transactions FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE TABLE public.recharge_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  status public.request_status NOT NULL DEFAULT 'pending',
  note text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.recharge_requests TO authenticated;
GRANT ALL ON public.recharge_requests TO service_role;
ALTER TABLE public.recharge_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own recharges" ON public.recharge_requests FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users request own recharges" ON public.recharge_requests FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending');
CREATE POLICY "Admins read all recharges" ON public.recharge_requests FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE TABLE public.withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  pix_key text NOT NULL,
  status public.request_status NOT NULL DEFAULT 'pending',
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.withdrawal_requests TO authenticated;
GRANT ALL ON public.withdrawal_requests TO service_role;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own withdrawals" ON public.withdrawal_requests FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users request own withdrawals" ON public.withdrawal_requests FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending');
CREATE POLICY "Admins read all withdrawals" ON public.withdrawal_requests FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE TABLE public.pix_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_value text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, key_value)
);
GRANT SELECT, INSERT, DELETE ON public.pix_keys TO authenticated;
GRANT ALL ON public.pix_keys TO service_role;
ALTER TABLE public.pix_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own pix keys" ON public.pix_keys FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins read pix keys" ON public.pix_keys FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.purchase_vehicle(_catalog_id text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  item public.vehicle_catalog%ROWTYPE;
  current_balance numeric(12,2);
  new_vehicle_id uuid;
  new_plate text;
BEGIN
  SELECT * INTO item FROM public.vehicle_catalog WHERE id = _catalog_id AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'VEHICLE_NOT_FOUND'; END IF;
  SELECT demo_balance INTO current_balance FROM public.profiles WHERE id = auth.uid() FOR UPDATE;
  IF current_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF current_balance < item.price THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
  new_plate := 'VX' || (12178 + (SELECT count(*) FROM public.user_vehicles WHERE user_id = auth.uid()))::text;
  UPDATE public.profiles SET demo_balance = demo_balance - item.price WHERE id = auth.uid();
  INSERT INTO public.user_vehicles (user_id, catalog_id, name, region, daily, return_value, price, purchase_price, cycle, image_key, plate)
  VALUES (auth.uid(), item.id, item.name, item.region, 'R$ ' || replace(to_char(item.daily_amount, 'FM999999990D00'), '.', ',') || '/dia', 'R$ ' || replace(to_char(item.return_amount, 'FM999999990D00'), '.', ','), 'R$ ' || replace(to_char(item.price, 'FM999999990D00'), '.', ','), item.price, item.cycle_days || ' dias úteis', item.image_key, new_plate)
  RETURNING id INTO new_vehicle_id;
  INSERT INTO public.balance_transactions (user_id, type, amount, balance_after, description, reference_id)
  VALUES (auth.uid(), 'vehicle_purchase', -item.price, current_balance - item.price, 'Aluguel de ' || item.name, new_vehicle_id);
  RETURN new_vehicle_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.purchase_vehicle(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_demo_recharge(_amount numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE request_id uuid;
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'INVALID_RECHARGE'; END IF;
  INSERT INTO public.recharge_requests(user_id, amount) VALUES(auth.uid(), _amount) RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.request_demo_recharge(numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _pix_key text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE request_id uuid; current_balance numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR _amount <= 0 OR length(trim(_pix_key)) < 3 THEN RAISE EXCEPTION 'INVALID_WITHDRAWAL'; END IF;
  SELECT demo_balance INTO current_balance FROM public.profiles WHERE id = auth.uid();
  IF current_balance < _amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
  IF EXISTS (SELECT 1 FROM public.withdrawal_requests WHERE user_id = auth.uid() AND status = 'pending') THEN RAISE EXCEPTION 'PENDING_WITHDRAWAL_EXISTS'; END IF;
  INSERT INTO public.withdrawal_requests(user_id, amount, pix_key) VALUES(auth.uid(), _amount, trim(_pix_key)) RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.request_withdrawal(numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_adjust_demo_balance(_user_id uuid, _amount numeric, _reason text)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE next_balance numeric(12,2);
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF _amount = 0 OR length(trim(_reason)) < 3 THEN RAISE EXCEPTION 'INVALID_ADJUSTMENT'; END IF;
  UPDATE public.profiles SET demo_balance = demo_balance + _amount WHERE id = _user_id AND demo_balance + _amount >= 0 RETURNING demo_balance INTO next_balance;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'INVALID_BALANCE'; END IF;
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, created_by) VALUES(_user_id, 'admin_adjustment', _amount, next_balance, trim(_reason), auth.uid());
  RETURN next_balance;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_adjust_demo_balance(uuid, numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_review_recharge(_request_id uuid, _approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req public.recharge_requests%ROWTYPE; next_balance numeric(12,2);
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO req FROM public.recharge_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND OR req.status <> 'pending' THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  UPDATE public.recharge_requests SET status = CASE WHEN _approve THEN 'approved'::public.request_status ELSE 'rejected'::public.request_status END, reviewed_by = auth.uid(), reviewed_at = now() WHERE id = _request_id;
  IF _approve THEN
    UPDATE public.profiles SET demo_balance = demo_balance + req.amount WHERE id = req.user_id RETURNING demo_balance INTO next_balance;
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id, created_by) VALUES(req.user_id, 'recharge', req.amount, next_balance, 'Crédito demonstrativo aprovado', req.id, auth.uid());
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_review_recharge(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_review_withdrawal(_request_id uuid, _approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req public.withdrawal_requests%ROWTYPE; current_balance numeric(12,2); next_balance numeric(12,2);
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO req FROM public.withdrawal_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND OR req.status <> 'pending' THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  IF _approve THEN
    SELECT demo_balance INTO current_balance FROM public.profiles WHERE id = req.user_id FOR UPDATE;
    IF current_balance < req.amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
    UPDATE public.profiles SET demo_balance = demo_balance - req.amount WHERE id = req.user_id RETURNING demo_balance INTO next_balance;
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id, created_by) VALUES(req.user_id, 'withdrawal', -req.amount, next_balance, 'Saque demonstrativo aprovado', req.id, auth.uid());
  END IF;
  UPDATE public.withdrawal_requests SET status = CASE WHEN _approve THEN 'approved'::public.request_status ELSE 'rejected'::public.request_status END, reviewed_by = auth.uid(), reviewed_at = now() WHERE id = _request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_review_withdrawal(uuid, boolean) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.user_vehicles FROM authenticated;
GRANT SELECT ON public.user_vehicles TO authenticated;

CREATE POLICY "Admins update recharge requests" ON public.recharge_requests FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins update withdrawal requests" ON public.withdrawal_requests FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
