-- Add referral_reward to ledger_type enum
ALTER TYPE public.ledger_type ADD VALUE IF NOT EXISTS 'referral_reward';

-- Update confirm_pix_charge to include referral and first-deposit rewards
CREATE OR REPLACE FUNCTION public.confirm_pix_charge(_external_ref text, _magic_id text, _amount numeric, _provider_updated_at timestamptz DEFAULT now())
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE 
  charge public.pix_charges%ROWTYPE; 
  next_balance numeric(12,2);
  referrer_id uuid;
  is_first_deposit boolean;
  referee_reward numeric(12,2);
  referrer_reward numeric(12,2);
  referrer_balance numeric(12,2);
  referee_reward_balance numeric(12,2);
BEGIN
  -- Lock the charge record
  SELECT * INTO charge FROM public.pix_charges WHERE external_ref = _external_ref FOR UPDATE;
  IF NOT FOUND OR charge.provider_magic_id IS DISTINCT FROM _magic_id OR charge.amount <> _amount THEN 
    RAISE EXCEPTION 'INVALID_PIX_CHARGE'; 
  END IF;
  
  -- Prevent duplicate processing
  IF charge.credited_at IS NOT NULL THEN RETURN false; END IF;

  -- 1. Credit the deposit amount to user's game credits (demo_balance)
  UPDATE public.profiles SET demo_balance = demo_balance + charge.amount WHERE id = charge.user_id RETURNING demo_balance INTO next_balance;
  IF next_balance IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  -- Mark charge as confirmed
  UPDATE public.pix_charges SET status = 'CONFIRMED', credited_at = now(), provider_updated_at = _provider_updated_at, updated_at = now() WHERE id = charge.id;

  -- Log the main deposit transaction
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
  VALUES(charge.user_id, 'recharge', charge.amount, next_balance, 'Créditos do jogo via PIX', charge.id);

  -- 2. Check if this is the first confirmed deposit for the user
  SELECT NOT EXISTS (
    SELECT 1 FROM public.pix_charges 
    WHERE user_id = charge.user_id 
    AND status = 'CONFIRMED' 
    AND id <> charge.id
  ) INTO is_first_deposit;

  -- 3. Referee reward: 5% once on first confirmed deposit
  IF is_first_deposit THEN
    referee_reward := (charge.amount * 0.05);
    UPDATE public.profiles 
    SET reward_balance = reward_balance + referee_reward 
    WHERE id = charge.user_id 
    RETURNING reward_balance INTO referee_reward_balance;
    
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(charge.user_id, 'referral_reward', referee_reward, referee_reward_balance, 'Bônus de primeiro depósito (5%)', charge.id);
  END IF;

  -- 4. Referrer reward: 15% on every confirmed deposit
  SELECT id INTO referrer_id FROM public.profiles 
  WHERE invite_code = (SELECT referred_by FROM public.profiles WHERE id = charge.user_id);

  IF referrer_id IS NOT NULL THEN
    referrer_reward := (charge.amount * 0.15);
    UPDATE public.profiles 
    SET reward_balance = reward_balance + referrer_reward 
    WHERE id = referrer_id 
    RETURNING reward_balance INTO referrer_balance;
    
    INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
    VALUES(referrer_id, 'referral_reward', referrer_reward, referrer_balance, 'Comissão de indicação (15%)', charge.id);
  END IF;

  RETURN true;
END;
$$;

-- Function to get team stats for a user
CREATE OR REPLACE FUNCTION public.get_team_stats(_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  my_invite_code text;
  total_benefits numeric(12,2);
  effective_count int;
  total_count int;
  today_rewards numeric(12,2);
  today_recharges numeric(12,2);
  members_list jsonb;
BEGIN
  SELECT invite_code INTO my_invite_code FROM public.profiles WHERE id = _user_id;
  
  -- Total rewards earned by this user from referral_reward transactions
  SELECT coalesce(sum(amount), 0) INTO total_benefits 
  FROM public.balance_transactions 
  WHERE user_id = _user_id AND type = 'referral_reward';
  
  -- Members who have made at least one confirmed deposit
  SELECT count(*) INTO effective_count
  FROM public.profiles p
  WHERE p.referred_by = my_invite_code
  AND EXISTS (SELECT 1 FROM public.pix_charges pc WHERE pc.user_id = p.id AND pc.status = 'CONFIRMED');
  
  -- Total referrals
  SELECT count(*) INTO total_count
  FROM public.profiles
  WHERE referred_by = my_invite_code;

  -- Rewards earned today
  SELECT coalesce(sum(amount), 0) INTO today_rewards
  FROM public.balance_transactions
  WHERE user_id = _user_id 
  AND type = 'referral_reward' 
  AND created_at >= current_date;

  -- Recharges by team today
  SELECT coalesce(sum(pc.amount), 0) INTO today_recharges
  FROM public.pix_charges pc
  JOIN public.profiles p ON p.id = pc.user_id
  WHERE p.referred_by = my_invite_code
  AND pc.status = 'CONFIRMED'
  AND pc.credited_at >= current_date;

  -- List of members with their status
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'email', p.email,
    'phone', p.phone,
    'created_at', p.created_at,
    'is_effective', EXISTS (SELECT 1 FROM public.pix_charges pc WHERE pc.user_id = p.id AND pc.status = 'CONFIRMED')
  ) ORDER BY p.created_at DESC), '[]'::jsonb) INTO members_list
  FROM public.profiles p
  WHERE p.referred_by = my_invite_code;

  RETURN jsonb_build_object(
    'totalBenefits', total_benefits,
    'effectiveCount', effective_count,
    'totalCount', total_count,
    'todayRewards', today_rewards,
    'todayRecharges', today_recharges,
    'members', members_list
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_team_stats(uuid) TO authenticated;
