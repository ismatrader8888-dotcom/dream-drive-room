CREATE OR REPLACE FUNCTION public.guard_profile_self_service_updates()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $function$
BEGIN
  IF current_user IN ('anon', 'authenticated') AND (
    NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email OR
    NEW.invite_code IS DISTINCT FROM OLD.invite_code OR NEW.referred_by IS DISTINCT FROM OLD.referred_by OR
    NEW.level IS DISTINCT FROM OLD.level OR NEW.balance IS DISTINCT FROM OLD.balance OR
    NEW.demo_balance IS DISTINCT FROM OLD.demo_balance OR NEW.reward_balance IS DISTINCT FROM OLD.reward_balance OR
    NEW.created_at IS DISTINCT FROM OLD.created_at OR
    NEW.signup_bonus_granted_at IS DISTINCT FROM OLD.signup_bonus_granted_at OR
    NEW.welcome_bonus_seen_at IS DISTINCT FROM OLD.welcome_bonus_seen_at OR
    NEW.invite_task_rewarded_at IS DISTINCT FROM OLD.invite_task_rewarded_at OR
    NEW.blocked_at IS DISTINCT FROM OLD.blocked_at OR NEW.blocked_reason IS DISTINCT FROM OLD.blocked_reason OR
    NEW.referral_program_disabled_at IS DISTINCT FROM OLD.referral_program_disabled_at
  ) THEN RAISE EXCEPTION 'PROTECTED_PROFILE_FIELD'; END IF;
  RETURN NEW;
END;
$function$;
REVOKE UPDATE (referral_program_disabled_at) ON public.profiles FROM authenticated, anon;

ALTER POLICY "Users read own referral relationships" ON public.referrals
  USING ((auth.uid() = referred_user_id OR (auth.uid() = referrer_id AND NOT EXISTS
    (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.referral_program_disabled_at IS NOT NULL))));
ALTER POLICY "Users read own referral rewards" ON public.referral_rewards
  USING (auth.uid() = beneficiary_id AND NOT EXISTS
    (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.referral_program_disabled_at IS NOT NULL));

CREATE OR REPLACE FUNCTION public.confirm_pix_charge(_external_ref text, _magic_id text, _amount numeric, _provider_updated_at timestamptz DEFAULT now())
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  SELECT NOT EXISTS (SELECT 1 FROM public.pix_charges WHERE user_id = charge.user_id AND credited_at IS NOT NULL AND id <> charge.id) INTO is_first_deposit;
  SELECT * INTO direct_referral FROM public.referrals WHERE referred_user_id = charge.user_id FOR UPDATE;
  IF direct_referral.id IS NOT NULL THEN
    SELECT * INTO parent_referral FROM public.referrals WHERE referred_user_id = direct_referral.referrer_id FOR UPDATE;
  END IF;
  referee_bonus := CASE WHEN direct_referral.id IS NOT NULL AND is_first_deposit THEN round(charge.amount * 0.05, 2) ELSE 0 END;
  direct_bonus := CASE WHEN direct_referral.id IS NOT NULL AND is_first_deposit AND NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = direct_referral.referrer_id AND referral_program_disabled_at IS NOT NULL
  ) THEN round(charge.amount * 0.08, 2) ELSE 0 END;
  second_level_bonus := CASE WHEN parent_referral.id IS NOT NULL AND is_first_deposit AND NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = parent_referral.referrer_id AND referral_program_disabled_at IS NOT NULL
  ) THEN round(charge.amount * 0.03, 2) ELSE 0 END;
  UPDATE public.profiles SET demo_balance = demo_balance + charge.amount + referee_bonus WHERE id = charge.user_id RETURNING demo_balance INTO next_balance;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  UPDATE public.pix_charges SET status = 'CONFIRMED', credited_at = now(), provider_updated_at = _provider_updated_at, updated_at = now() WHERE id = charge.id;
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
  VALUES(charge.user_id, 'recharge', charge.amount, next_balance - referee_bonus, 'Créditos do jogo via PIX', charge.id);
  IF referee_bonus > 0 THEN
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, charge.user_id, 'referee_first_deposit', charge.amount, 5, referee_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(charge.user_id, 'referral_bonus', referee_bonus, next_balance, 'Bônus de 5% no primeiro depósito indicado', charge.id);
  END IF;
  IF direct_bonus > 0 THEN
    UPDATE public.profiles SET demo_balance = demo_balance + direct_bonus WHERE id = direct_referral.referrer_id RETURNING demo_balance INTO direct_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, direct_referral.referrer_id, 'referrer_commission', charge.amount, 8, direct_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(direct_referral.referrer_id, 'referral_bonus', direct_bonus, direct_balance, 'Bônus de 8% no primeiro depósito do indicado direto', charge.id);
  END IF;
  IF second_level_bonus > 0 THEN
    UPDATE public.profiles SET demo_balance = demo_balance + second_level_bonus WHERE id = parent_referral.referrer_id RETURNING demo_balance INTO second_level_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, parent_referral.referrer_id, 'second_level_commission', charge.amount, 3, second_level_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(parent_referral.referrer_id, 'referral_bonus', second_level_bonus, second_level_balance, 'Bônus de 3% no primeiro depósito do indicado de nível 2', charge.id);
  END IF;
  IF direct_referral.id IS NOT NULL THEN
    UPDATE public.referrals SET effective_at = coalesce(effective_at, now()), first_deposit_amount = coalesce(first_deposit_amount, charge.amount),
      total_confirmed_deposits = total_confirmed_deposits + 1, total_deposited = total_deposited + charge.amount,
      referee_bonus_total = referee_bonus_total + referee_bonus, referrer_bonus_total = referrer_bonus_total + direct_bonus
    WHERE id = direct_referral.id;
  END IF;
  RETURN true;
END;
$function$;