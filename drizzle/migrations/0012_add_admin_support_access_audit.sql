CREATE TABLE public.admin_support_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL,
  target_user_id uuid NOT NULL,
  opened_at timestamp with time zone NOT NULL DEFAULT now(),
  closed_at timestamp with time zone,
  user_agent text
);

GRANT SELECT ON public.admin_support_sessions TO authenticated;
GRANT ALL ON public.admin_support_sessions TO service_role;

ALTER TABLE public.admin_support_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins read support audit"
ON public.admin_support_sessions
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE OR REPLACE FUNCTION public.admin_open_support_view(_target_user_id uuid, _user_agent text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  support_session_id uuid;
  result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = _target_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  PERFORM public.process_vehicle_rewards_for(_target_user_id);

  INSERT INTO public.admin_support_sessions(admin_id, target_user_id, user_agent)
  VALUES (auth.uid(), _target_user_id, left(_user_agent, 500))
  RETURNING id INTO support_session_id;

  SELECT jsonb_build_object(
    'sessionId', support_session_id,
    'profile', jsonb_build_object(
      'id', p.id,
      'email', p.email,
      'phone', p.phone,
      'inviteCode', p.invite_code,
      'referredBy', p.referred_by,
      'level', p.level,
      'balance', p.demo_balance,
      'rewardBalance', p.reward_balance,
      'createdAt', p.created_at
    ),
    'vehicles', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', uv.id,
        'name', uv.name,
        'region', uv.region,
        'plate', uv.plate,
        'price', uv.purchase_price,
        'rewardPerCycle', uv.reward_per_cycle,
        'cyclesCompleted', uv.cycles_completed,
        'contractCycles', uv.contract_cycles,
        'nextRewardAt', uv.next_reward_at,
        'purchasedAt', uv.purchased_at,
        'completedAt', uv.completed_at
      ) ORDER BY uv.purchased_at DESC)
      FROM public.user_vehicles uv WHERE uv.user_id = p.id
    ), '[]'::jsonb),
    'pixCharges', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id,
        'amount', c.amount,
        'status', c.status,
        'payerName', c.payer_name,
        'providerId', c.provider_magic_id,
        'createdAt', c.created_at,
        'creditedAt', c.credited_at
      ) ORDER BY c.created_at DESC)
      FROM public.pix_charges c WHERE c.user_id = p.id
    ), '[]'::jsonb),
    'withdrawals', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', w.id,
        'amount', w.amount,
        'status', w.status,
        'fullName', w.full_name,
        'pixKey', w.pix_key,
        'createdAt', w.created_at,
        'reviewedAt', w.reviewed_at
      ) ORDER BY w.created_at DESC)
      FROM public.withdrawal_requests w WHERE w.user_id = p.id
    ), '[]'::jsonb),
    'transactions', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'type', t.type,
        'amount', t.amount,
        'balanceAfter', t.balance_after,
        'description', t.description,
        'createdAt', t.created_at
      ) ORDER BY t.created_at DESC)
      FROM (SELECT * FROM public.balance_transactions WHERE user_id = p.id ORDER BY created_at DESC LIMIT 100) t
    ), '[]'::jsonb),
    'referrals', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', r.id,
        'inviteCode', r.invite_code,
        'memberEmail', member.email,
        'effectiveAt', r.effective_at,
        'deposits', r.total_confirmed_deposits,
        'totalDeposited', r.total_deposited,
        'bonus', r.referrer_bonus_total,
        'createdAt', r.created_at
      ) ORDER BY r.created_at DESC)
      FROM public.referrals r
      JOIN public.profiles member ON member.id = r.referred_user_id
      WHERE r.referrer_id = p.id
    ), '[]'::jsonb)
  ) INTO result
  FROM public.profiles p
  WHERE p.id = _target_user_id;

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_close_support_view(_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  UPDATE public.admin_support_sessions
  SET closed_at = coalesce(closed_at, now())
  WHERE id = _session_id AND admin_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUPPORT_SESSION_NOT_FOUND';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_open_support_view(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_open_support_view(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_open_support_view(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_close_support_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_close_support_view(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_close_support_view(uuid) TO service_role;