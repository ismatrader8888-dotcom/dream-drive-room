ALTER TABLE public.profiles ADD COLUMN referral_program_disabled_at timestamptz;

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
  SELECT NOT EXISTS (
    SELECT 1 FROM public.pix_charges
    WHERE user_id = charge.user_id AND credited_at IS NOT NULL AND id <> charge.id
  ) INTO is_first_deposit;

  SELECT * INTO direct_referral FROM public.referrals WHERE referred_user_id = charge.user_id FOR UPDATE;
  IF direct_referral.id IS NOT NULL THEN
    SELECT * INTO parent_referral FROM public.referrals
    WHERE referred_user_id = direct_referral.referrer_id FOR UPDATE;
  END IF;

  referee_bonus := CASE WHEN direct_referral.id IS NOT NULL AND is_first_deposit THEN round(charge.amount * 0.05, 2) ELSE 0 END;
  direct_bonus := CASE WHEN direct_referral.id IS NOT NULL AND is_first_deposit AND NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = direct_referral.referrer_id AND referral_program_disabled_at IS NOT NULL
  ) THEN round(charge.amount * 0.08, 2) ELSE 0 END;
  second_level_bonus := CASE WHEN parent_referral.id IS NOT NULL AND is_first_deposit AND NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = parent_referral.referrer_id AND referral_program_disabled_at IS NOT NULL
  ) THEN round(charge.amount * 0.03, 2) ELSE 0 END;

  UPDATE public.profiles SET demo_balance = demo_balance + charge.amount + referee_bonus
  WHERE id = charge.user_id RETURNING demo_balance INTO next_balance;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  UPDATE public.pix_charges
  SET status = 'CONFIRMED', credited_at = now(), provider_updated_at = _provider_updated_at, updated_at = now()
  WHERE id = charge.id;

  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
  VALUES(charge.user_id, 'recharge', charge.amount, next_balance - referee_bonus, 'Créditos do jogo via PIX', charge.id);

  IF referee_bonus > 0 THEN
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, charge.user_id, 'referee_first_deposit', charge.amount, 5, referee_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(charge.user_id, 'referral_bonus', referee_bonus, next_balance, 'Bônus de 5% no primeiro depósito indicado', charge.id);
  END IF;

  IF direct_bonus > 0 THEN
    UPDATE public.profiles SET demo_balance = demo_balance + direct_bonus
    WHERE id = direct_referral.referrer_id RETURNING demo_balance INTO direct_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, direct_referral.referrer_id, 'referrer_commission', charge.amount, 8, direct_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(direct_referral.referrer_id, 'referral_bonus', direct_bonus, direct_balance, 'Bônus de 8% no primeiro depósito do indicado direto', charge.id);
  END IF;

  IF second_level_bonus > 0 THEN
    UPDATE public.profiles SET demo_balance = demo_balance + second_level_bonus
    WHERE id = parent_referral.referrer_id RETURNING demo_balance INTO second_level_balance;
    INSERT INTO public.referral_rewards(referral_id, charge_id, beneficiary_id, reward_type, deposit_amount, percentage, credit_amount)
    VALUES(direct_referral.id, charge.id, parent_referral.referrer_id, 'second_level_commission', charge.amount, 3, second_level_bonus);
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(parent_referral.referrer_id, 'referral_bonus', second_level_bonus, second_level_balance, 'Bônus de 3% no primeiro depósito do indicado de nível 2', charge.id);
  END IF;

  IF direct_referral.id IS NOT NULL THEN
    UPDATE public.referrals
    SET effective_at = coalesce(effective_at, now()),
        first_deposit_amount = coalesce(first_deposit_amount, charge.amount),
        total_confirmed_deposits = total_confirmed_deposits + 1,
        total_deposited = total_deposited + charge.amount,
        referee_bonus_total = referrer_bonus_total + 0 + referee_bonus_total - referee_bonus_total + referee_bonus_total,
        referrer_bonus_total = referrer_bonus_total + direct_bonus
    WHERE id = direct_referral.id;
  END IF;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_referral_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND referral_program_disabled_at IS NOT NULL) THEN
    RETURN jsonb_build_object('totalMembers', 0, 'effectiveMembers', 0, 'totalDeposited', 0, 'teamEarned', 0, 'totalEarned', 0, 'earnedToday', 0, 'depositedToday', 0, 'members', '[]'::jsonb, 'rewards', '[]'::jsonb, 'disabled', true);
  END IF;
  SELECT jsonb_build_object(
    'totalMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid()),
    'effectiveMembers', (SELECT count(*) FROM public.referrals WHERE referrer_id = auth.uid() AND effective_at IS NOT NULL),
    'totalDeposited', (SELECT coalesce(sum(total_deposited), 0) FROM public.referrals WHERE referrer_id = auth.uid()),
    'teamEarned', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND reward_type IN ('referrer_commission', 'second_level_commission')),
    'totalEarned', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid()),
    'earnedToday', (SELECT coalesce(sum(credit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type IN ('referrer_commission', 'second_level_commission')),
    'depositedToday', (SELECT coalesce(sum(deposit_amount), 0) FROM public.referral_rewards WHERE beneficiary_id = auth.uid() AND created_at >= date_trunc('day', now()) AND reward_type IN ('referrer_commission', 'second_level_commission')),
    'members', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'displayName', coalesce(nullif(split_part(p.email, '@', 1), ''), regexp_replace(coalesce(p.phone, ''), '.(?=.{4})', '*', 'g'), 'Jogador'),
      'status', CASE WHEN r.effective_at IS NULL THEN 'invalid' ELSE 'effective' END,
      'joinedAt', r.created_at, 'effectiveAt', r.effective_at, 'firstDeposit', r.first_deposit_amount,
      'deposits', r.total_confirmed_deposits, 'totalDeposited', r.total_deposited, 'bonusEarned', r.referrer_bonus_total
    ) ORDER BY r.created_at DESC), '[]'::jsonb) FROM public.referrals r JOIN public.profiles p ON p.id = r.referred_user_id WHERE r.referrer_id = auth.uid()),
    'rewards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', rw.id, 'type', rw.reward_type, 'depositAmount', rw.deposit_amount,
      'percentage', rw.percentage, 'creditAmount', rw.credit_amount, 'createdAt', rw.created_at,
      'memberName', coalesce(nullif(split_part(p.email, '@', 1), ''), 'Jogador')
    ) ORDER BY rw.created_at DESC), '[]'::jsonb)
    FROM public.referral_rewards rw JOIN public.referrals r ON r.id = rw.referral_id
    JOIN public.profiles p ON p.id = r.referred_user_id WHERE rw.beneficiary_id = auth.uid())
  ) INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_invite_task_state()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  total_invited_count integer;
  qualified_count integer;
  already_rewarded boolean;
  next_balance numeric(12,2);
BEGIN
  IF current_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  PERFORM 1 FROM public.profiles WHERE id = current_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = current_user_id AND referral_program_disabled_at IS NOT NULL) THEN
    RETURN jsonb_build_object('completed', 0, 'totalInvited', 0, 'qualifiedInvited', 0, 'goal', 3, 'reward', 20, 'rewarded', false, 'disabled', true);
  END IF;
  SELECT count(*)::integer INTO total_invited_count FROM public.referrals WHERE referrer_id = current_user_id;
  SELECT count(*)::integer INTO qualified_count FROM public.referrals r
  WHERE r.referrer_id = current_user_id
    AND EXISTS (SELECT 1 FROM public.pix_charges pc WHERE pc.user_id = r.referred_user_id AND pc.status = 'CONFIRMED')
    AND EXISTS (SELECT 1 FROM public.user_vehicles uv WHERE uv.user_id = r.referred_user_id);
  SELECT invite_task_rewarded_at IS NOT NULL INTO already_rewarded FROM public.profiles WHERE id = current_user_id;
  IF qualified_count >= 3 AND NOT already_rewarded THEN
    UPDATE public.profiles SET reward_balance = reward_balance + 20, invite_task_rewarded_at = now()
    WHERE id = current_user_id AND invite_task_rewarded_at IS NULL RETURNING reward_balance INTO next_balance;
    IF next_balance IS NOT NULL THEN
      INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description)
      VALUES(current_user_id, 'referral_bonus', 20, next_balance, 'Prêmio da tarefa: 3 convidados com depósito e veículo');
      already_rewarded := true;
    END IF;
  END IF;
  RETURN jsonb_build_object('completed', LEAST(qualified_count, 3), 'totalInvited', total_invited_count, 'qualifiedInvited', qualified_count, 'goal', 3, 'reward', 20, 'rewarded', already_rewarded);
END;
$function$;

CREATE POLICY "Disabled referrers cannot read own referral relationships" ON public.referrals FOR SELECT TO authenticated USING (false);