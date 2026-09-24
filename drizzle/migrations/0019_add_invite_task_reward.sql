ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS invite_task_rewarded_at timestamptz;

CREATE OR REPLACE FUNCTION public.get_my_invite_task_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  invited_count integer;
  already_rewarded boolean;
  next_balance numeric(12,2);
BEGIN
  IF current_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;

  PERFORM 1 FROM public.profiles WHERE id = current_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  SELECT count(*)::integer INTO invited_count
  FROM public.referrals
  WHERE referrer_id = current_user_id;

  SELECT invite_task_rewarded_at IS NOT NULL INTO already_rewarded
  FROM public.profiles
  WHERE id = current_user_id;

  IF invited_count >= 3 AND NOT already_rewarded THEN
    UPDATE public.profiles
    SET reward_balance = reward_balance + 20,
        invite_task_rewarded_at = now()
    WHERE id = current_user_id
      AND invite_task_rewarded_at IS NULL
    RETURNING reward_balance INTO next_balance;

    IF next_balance IS NOT NULL THEN
      INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description)
      VALUES(current_user_id, 'referral_bonus', 20, next_balance, 'Prêmio da tarefa: convide 3 amigos');
      already_rewarded := true;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'completed', LEAST(invited_count, 3),
    'totalInvited', invited_count,
    'goal', 3,
    'reward', 20,
    'rewarded', already_rewarded
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_invite_task_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_invite_task_state() TO authenticated, service_role;