-- Add redeem_code to ledger_type enum
ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'redeem_code';

-- Global Notifications
CREATE TABLE IF NOT EXISTS public.global_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    content text NOT NULL,
    type text NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'warning', 'success', 'error')),
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_notification_states (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_id uuid NOT NULL REFERENCES public.global_notifications(id) ON DELETE CASCADE,
    seen_at timestamptz,
    dismissed_at timestamptz,
    PRIMARY KEY (user_id, notification_id)
);

-- Credit Codes
CREATE TABLE IF NOT EXISTS public.credit_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    max_uses integer CHECK (max_uses > 0),
    uses_count integer NOT NULL DEFAULT 0,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.credit_code_redemptions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code_id uuid NOT NULL REFERENCES public.credit_codes(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    redeemed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(code_id, user_id)
);

-- RLS for Global Notifications
ALTER TABLE public.global_notifications ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.global_notifications TO authenticated;
GRANT ALL ON public.global_notifications TO service_role;

CREATE POLICY "Users read active notifications" ON public.global_notifications
    FOR SELECT TO authenticated
    USING (active = true OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins manage notifications" ON public.global_notifications
    FOR ALL TO authenticated
    USING (public.has_role(auth.uid(), 'admin'))
    WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- RLS for User Notification States
ALTER TABLE public.user_notification_states ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.user_notification_states TO authenticated;
GRANT ALL ON public.user_notification_states TO service_role;

CREATE POLICY "Users manage own notification states" ON public.user_notification_states
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- RLS for Credit Codes (Admins only for the table itself, users use RPC)
ALTER TABLE public.credit_codes ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.credit_codes TO authenticated; -- Allow select for RPC and UI check if needed
GRANT ALL ON public.credit_codes TO service_role;

CREATE POLICY "Admins manage credit codes" ON public.credit_codes
    FOR ALL TO authenticated
    USING (public.has_role(auth.uid(), 'admin'))
    WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- RLS for Credit Code Redemptions
ALTER TABLE public.credit_code_redemptions ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.credit_code_redemptions TO authenticated;
GRANT ALL ON public.credit_code_redemptions TO service_role;

CREATE POLICY "Users read own redemptions" ON public.credit_code_redemptions
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Admins read all redemptions" ON public.credit_code_redemptions
    FOR SELECT TO authenticated
    USING (public.has_role(auth.uid(), 'admin'));

-- RPC for Redeeming Credit Codes
CREATE OR REPLACE FUNCTION public.redeem_credit_code(_code text)
RETURNS numeric(12,2) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_code_id uuid;
    v_amount numeric(12,2);
    v_max_uses integer;
    v_uses_count integer;
    v_expires_at timestamptz;
    v_next_balance numeric(12,2);
    v_upper_code text := upper(trim(_code));
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    -- 2. Find and Lock the code record
    SELECT id, amount, max_uses, uses_count, expires_at 
    INTO v_code_id, v_amount, v_max_uses, v_uses_count, v_expires_at
    FROM public.credit_codes
    WHERE upper(code) = v_upper_code
    FOR UPDATE;

    IF v_code_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_CODE';
    END IF;

    -- 3. Validate
    IF v_expires_at IS NOT NULL AND v_expires_at < now() THEN
        RAISE EXCEPTION 'CODE_EXPIRED';
    END IF;

    IF v_max_uses IS NOT NULL AND v_uses_count >= v_max_uses THEN
        RAISE EXCEPTION 'CODE_FULLY_REDEEMED';
    END IF;

    -- 4. Check if user already redeemed
    IF EXISTS (
        SELECT 1 FROM public.credit_code_redemptions 
        WHERE code_id = v_code_id AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'ALREADY_REDEEMED';
    END IF;

    -- 5. Atomically update
    -- Increment use count
    UPDATE public.credit_codes SET uses_count = uses_count + 1 WHERE id = v_code_id;

    -- Insert redemption record
    INSERT INTO public.credit_code_redemptions (code_id, user_id)
    VALUES (v_code_id, auth.uid());

    -- Update user balance
    UPDATE public.profiles 
    SET demo_balance = demo_balance + v_amount 
    WHERE id = auth.uid()
    RETURNING demo_balance INTO v_next_balance;

    IF v_next_balance IS NULL THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND';
    END IF;

    -- Record transaction
    INSERT INTO public.balance_transactions (user_id, type, amount, balance_after, description, reference_id)
    VALUES (auth.uid(), 'redeem_code', v_amount, v_next_balance, 'Resgate de código: ' || v_upper_code, v_code_id);

    RETURN v_next_balance;
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_credit_code(text) TO authenticated;
