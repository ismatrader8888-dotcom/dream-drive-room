ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'redeem_code';

CREATE TABLE public.admin_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  message text NOT NULL CHECK (char_length(btrim(message)) BETWEEN 1 AND 1000),
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.admin_notifications TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.admin_notifications TO authenticated;
GRANT ALL ON public.admin_notifications TO service_role;

ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read active notifications"
ON public.admin_notifications FOR SELECT TO authenticated
USING (active OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins create notifications"
ON public.admin_notifications FOR INSERT TO authenticated
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role) AND created_by = auth.uid());

CREATE POLICY "Admins update notifications"
ON public.admin_notifications FOR UPDATE TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins delete notifications"
ON public.admin_notifications FOR DELETE TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE TABLE public.notification_receipts (
  notification_id uuid NOT NULL REFERENCES public.admin_notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (notification_id, user_id)
);

GRANT SELECT, INSERT, UPDATE ON public.notification_receipts TO authenticated;
GRANT ALL ON public.notification_receipts TO service_role;

ALTER TABLE public.notification_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own notification receipts"
ON public.notification_receipts FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users create own notification receipts"
ON public.notification_receipts FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own notification receipts"
ON public.notification_receipts FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE TABLE public.redeem_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  credit_amount numeric(12,2) NOT NULL CHECK (credit_amount > 0),
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT redeem_codes_normalized CHECK (code = upper(btrim(code)) AND char_length(code) BETWEEN 3 AND 40)
);

CREATE UNIQUE INDEX redeem_codes_code_unique ON public.redeem_codes (upper(code));

GRANT SELECT, INSERT, UPDATE ON public.redeem_codes TO authenticated;
GRANT ALL ON public.redeem_codes TO service_role;

ALTER TABLE public.redeem_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins manage redeem codes"
ON public.redeem_codes FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role) AND created_by = auth.uid());

CREATE TABLE public.redeem_code_uses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code_id uuid NOT NULL REFERENCES public.redeem_codes(id),
  user_id uuid NOT NULL,
  credit_amount numeric(12,2) NOT NULL CHECK (credit_amount > 0),
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (code_id, user_id)
);

GRANT SELECT ON public.redeem_code_uses TO authenticated;
GRANT ALL ON public.redeem_code_uses TO service_role;

ALTER TABLE public.redeem_code_uses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own code uses"
ON public.redeem_code_uses FOR SELECT TO authenticated
USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE OR REPLACE FUNCTION public.redeem_credit_code(_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_code public.redeem_codes%ROWTYPE;
  v_balance numeric;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  SELECT * INTO v_code
  FROM public.redeem_codes
  WHERE code = upper(btrim(_code)) AND active = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_CODE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.redeem_code_uses
    WHERE code_id = v_code.id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'CODE_ALREADY_USED';
  END IF;

  INSERT INTO public.redeem_code_uses (code_id, user_id, credit_amount)
  VALUES (v_code.id, v_user_id, v_code.credit_amount);

  UPDATE public.profiles
  SET demo_balance = demo_balance + v_code.credit_amount
  WHERE id = v_user_id
  RETURNING demo_balance INTO v_balance;

  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND';
  END IF;

  INSERT INTO public.balance_transactions (
    user_id, type, amount, balance_after, description, reference_id
  ) VALUES (
    v_user_id, 'redeem_code'::public.ledger_type, v_code.credit_amount,
    v_balance, 'Código resgatado: ' || v_code.code, v_code.id
  );

  RETURN jsonb_build_object(
    'amount', v_code.credit_amount,
    'balance', v_balance,
    'code', v_code.code
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'CODE_ALREADY_USED';
END;
$$;

REVOKE ALL ON FUNCTION public.redeem_credit_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_credit_code(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_credit_code(text) TO service_role;