ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'referral_bonus';

CREATE TABLE public.referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referred_user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  invite_code text NOT NULL,
  effective_at timestamptz,
  first_deposit_amount numeric(12,2),
  total_confirmed_deposits integer NOT NULL DEFAULT 0,
  total_deposited numeric(12,2) NOT NULL DEFAULT 0,
  referee_bonus_total numeric(12,2) NOT NULL DEFAULT 0,
  referrer_bonus_total numeric(12,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referrals_distinct_users CHECK (referrer_id <> referred_user_id),
  CONSTRAINT referrals_nonnegative_totals CHECK (total_confirmed_deposits >= 0 AND total_deposited >= 0 AND referee_bonus_total >= 0 AND referrer_bonus_total >= 0)
);
GRANT SELECT ON public.referrals TO authenticated;
GRANT ALL ON public.referrals TO service_role;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own referral relationships" ON public.referrals FOR SELECT TO authenticated USING (auth.uid() = referrer_id OR auth.uid() = referred_user_id);
CREATE POLICY "Admins read all referrals" ON public.referrals FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE INDEX referrals_referrer_idx ON public.referrals(referrer_id, created_at DESC);
CREATE INDEX referrals_effective_idx ON public.referrals(referrer_id, effective_at) WHERE effective_at IS NOT NULL;

CREATE TABLE public.referral_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_id uuid NOT NULL REFERENCES public.referrals(id) ON DELETE CASCADE,
  charge_id uuid NOT NULL REFERENCES public.pix_charges(id) ON DELETE RESTRICT,
  beneficiary_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reward_type text NOT NULL CHECK (reward_type IN ('referee_first_deposit','referrer_commission')),
  deposit_amount numeric(12,2) NOT NULL CHECK (deposit_amount > 0),
  percentage numeric(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 100),
  credit_amount numeric(12,2) NOT NULL CHECK (credit_amount > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (charge_id, reward_type)
);
GRANT SELECT ON public.referral_rewards TO authenticated;
GRANT ALL ON public.referral_rewards TO service_role;
ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own referral rewards" ON public.referral_rewards FOR SELECT TO authenticated USING (auth.uid() = beneficiary_id);
CREATE POLICY "Admins read all referral rewards" ON public.referral_rewards FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE INDEX referral_rewards_beneficiary_idx ON public.referral_rewards(beneficiary_id, created_at DESC);
CREATE INDEX referral_rewards_referral_idx ON public.referral_rewards(referral_id, created_at DESC);

INSERT INTO public.referrals (referrer_id, referred_user_id, invite_code)
SELECT owner.id, invited.id, owner.invite_code
FROM public.profiles invited
JOIN public.profiles owner ON upper(owner.invite_code) = upper(trim(invited.referred_by))
WHERE invited.referred_by IS NOT NULL
  AND owner.id <> invited.id
ON CONFLICT (referred_user_id) DO NOTHING;

REVOKE UPDATE ON public.profiles FROM authenticated;

CREATE OR REPLACE FUNCTION public.validate_invite_code(_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN nullif(upper(trim(_code)), '') IS NULL THEN true
    ELSE EXISTS (SELECT 1 FROM public.profiles WHERE invite_code = upper(trim(_code)))
  END
$$;
REVOKE ALL ON FUNCTION public.validate_invite_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_invite_code(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  normalized_code text := nullif(upper(trim(new.raw_user_meta_data ->> 'referred_by')), '');
  referrer uuid;
  generated_code text;
BEGIN
  IF normalized_code IS NOT NULL THEN
    SELECT id INTO referrer FROM public.profiles WHERE invite_code = normalized_code;
    IF referrer IS NULL THEN RAISE EXCEPTION 'INVALID_INVITE_CODE'; END IF;
  END IF;

  LOOP
    generated_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE invite_code = generated_code);
  END LOOP;

  INSERT INTO public.profiles (id, email, phone, invite_code, referred_by)
  VALUES (new.id, new.email, new.raw_user_meta_data ->> 'phone', generated_code, normalized_code)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, CASE WHEN lower(new.email) = 'maloneadm@adm.com' THEN 'admin'::public.app_role ELSE 'user'::public.app_role END)
  ON CONFLICT DO NOTHING;

  IF referrer IS NOT NULL THEN
    INSERT INTO public.referrals (referrer_id, referred_user_id, invite_code)
    VALUES (referrer, new.id, normalized_code)
    ON CONFLICT (referred_user_id) DO NOTHING;
  END IF;
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_pix_charge(_external_ref text, _magic_id text, _amount numeric, _provider_updated_at timestamptz DEFAULT now())
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  charge public.pix_charges%ROWTYPE;
  referral public.referrals%ROWTYPE;
  next_balance numeric(12,2);
  referrer_balance numeric(12,2);
  referee_bonus numeric(12,2);
  referrer_bonus numeric(12,2);
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

  SELECT * INTO referral FROM public.referrals WHERE referred_user_id = charge.user_id FOR UPDATE;
  referee_bonus := CASE WHEN FOUND AND is_first_deposit THEN round(charge.amount * 0.05, 2) ELSE 0 END;
  referrer_bonus := CASE WHEN referral.id IS NOT NULL THEN round(charge.amount * 0.15, 2) ELSE 0 END;

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
    VALUES(referral.id, charge.id, charge.user_id, 'referee_first_deposit', charge.amount, 5, referee_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(charge.user_id, 'referral_bonus', referee_bonus, next_balance, 'Bônus de 5% no primeiro depósito indicado', charge.id);
  END IF;

  IF referrer_bonus > 0 THEN
    UPDATE public.profiles
    SET demo_balance = demo_balance + referrer_bonus
    WHERE id = referral.referrer_id
    RETURNING demo_balance INTO referrer_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(referral.id, charge.id, referral.referrer_id, 'referrer_commission', charge.amount, 15, referrer_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(referral.referrer_id, 'referral_bonus', referrer_bonus, referrer_balance, 'Bônus de 15% por depósito de convidado', charge.id);
    UPDATE public.referrals
    SET effective_at = coalesce(effective_at, now()),
        first_deposit_amount = coalesce(first_deposit_amount, charge.amount),
        total_confirmed_deposits = total_confirmed_deposits + 1,
        total_deposited = total_deposited + charge.amount,
        referee_bonus_total = referee_bonus_total + referee_bonus,
        referrer_bonus_total = referrer_bonus_total + referrer_bonus
    WHERE id = referral.id;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_pix_charge(text, text, numeric, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pix_charge(text, text, numeric, timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.get_my_referral_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  SELECT jsonb_build_object(
    'totalMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid()),
    'effectiveMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid() AND effective_at IS NOT NULL),
    'totalDeposited', (SELECT coalesce(sum(total_deposited), 0) FROM public.referrals WHERE referrer_id = auth.uid()),
    'totalEarned', (SELECT coalesce(sum(referrer_bonus_total), 0) FROM public.referrals WHERE referrer_id = auth.uid()),
    'earnedToday', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type = 'referrer_commission'),
    'depositedToday', (SELECT coalesce(sum(rr.deposit_amount), 0) FROM public.referral_rewards rr WHERE rr.beneficiary_id = auth.uid() AND rr.created_at >= date_trunc('day', now()) AND rr.reward_type = 'referrer_commission'),
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
    'totalReferrals', (SELECT count(*) FROM public.referrals),
    'effectiveReferrals', (SELECT count(*) FROM public.referrals WHERE effective_at IS NOT NULL),
    'referredDepositVolume', (SELECT coalesce(sum(total_deposited), 0) FROM public.referrals),
    'referralCreditsDistributed', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards),
    'profiles', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'email', p.email, 'phone', p.phone, 'balance', p.demo_balance, 'rewardBalance', p.reward_balance,
      'inviteCode', p.invite_code, 'referredBy', p.referred_by,
      'referrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id),
      'effectiveReferrals', (SELECT count(*) FROM public.referrals r WHERE r.referrer_id = p.id AND r.effective_at IS NOT NULL),
      'referralBonus', (SELECT coalesce(sum(r.referrer_bonus_total), 0) FROM public.referrals r WHERE r.referrer_id = p.id)
    ) ORDER BY p.created_at DESC), '[]'::jsonb) FROM public.profiles p),
    'referrals', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'referrerEmail', owner.email, 'referredEmail', invited.email, 'inviteCode', r.invite_code,
      'status', CASE WHEN r.effective_at IS NULL THEN 'invalid' ELSE 'effective' END,
      'joinedAt', r.created_at, 'effectiveAt', r.effective_at, 'firstDeposit', r.first_deposit_amount,
      'deposits', r.total_confirmed_deposits, 'totalDeposited', r.total_deposited,
      'refereeBonus', r.referee_bonus_total, 'referrerBonus', r.referrer_bonus_total
    ) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.referrals r JOIN public.profiles owner ON owner.id = r.referrer_id JOIN public.profiles invited ON invited.id = r.referred_user_id),
    'popularVehicles', (SELECT coalesce(jsonb_agg(row_to_json(v)), '[]'::jsonb) FROM (SELECT name, count(*)::integer AS purchases, coalesce(sum(purchase_price), 0) AS volume FROM public.user_vehicles GROUP BY name ORDER BY count(*) DESC, name LIMIT 20) v),
    'withdrawals', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'userId', w.user_id, 'email', p.email, 'amount', w.amount, 'pixKey', w.pix_key, 'status', w.status, 'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb) FROM public.withdrawal_requests w JOIN public.profiles p ON p.id = w.user_id),
    'pixCharges', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'userId', c.user_id, 'email', p.email, 'payerName', c.payer_name, 'amount', c.amount, 'status', c.status,
      'magicId', c.provider_magic_id, 'createdAt', c.created_at, 'creditedAt', c.credited_at,
      'refereeBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referee_first_deposit'), 0),
      'referrerBonus', coalesce((SELECT sum(credit_amount) FROM public.referral_rewards WHERE charge_id = c.id AND reward_type = 'referrer_commission'), 0)
    ) ORDER BY c.created_at DESC), '[]'::jsonb) FROM public.pix_charges c JOIN public.profiles p ON p.id = c.user_id),
    'purchasesList', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', uv.id, 'email', p.email, 'name', uv.name, 'price', uv.purchase_price, 'region', uv.region, 'createdAt', uv.purchased_at) ORDER BY uv.purchased_at DESC), '[]'::jsonb) FROM public.user_vehicles uv JOIN public.profiles p ON p.id = uv.user_id)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard() TO authenticated;