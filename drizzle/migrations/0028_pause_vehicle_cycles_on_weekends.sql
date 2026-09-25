CREATE OR REPLACE FUNCTION public.next_vehicle_business_cycle(_anchor timestamptz)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ((_anchor AT TIME ZONE 'America/Sao_Paulo') +
    CASE EXTRACT(ISODOW FROM _anchor AT TIME ZONE 'America/Sao_Paulo')::integer
      WHEN 5 THEN interval '3 days'
      WHEN 6 THEN interval '3 days'
      WHEN 7 THEN interval '2 days'
      ELSE interval '1 day'
    END) AT TIME ZONE 'America/Sao_Paulo';
$$;
REVOKE ALL ON FUNCTION public.next_vehicle_business_cycle(timestamptz) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.process_vehicle_rewards_for(_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  vehicle_record record;
  scheduled_at timestamptz;
  cycle_no integer;
  inserted_cycles integer;
  credited_cycles integer;
  processed_total integer := 0;
  earned_amount numeric(12,2);
  next_balance numeric(12,2);
BEGIN
  FOR vehicle_record IN
    SELECT id, name, reward_per_cycle, contract_cycles, cycles_completed, next_reward_at, purchased_at
    FROM public.user_vehicles
    WHERE user_id = _user_id AND cycles_completed < contract_cycles
    FOR UPDATE
  LOOP
    cycle_no := vehicle_record.cycles_completed;
    scheduled_at := COALESCE(vehicle_record.next_reward_at, public.next_vehicle_business_cycle(vehicle_record.purchased_at));
    credited_cycles := 0;

    WHILE scheduled_at <= now() AND cycle_no < vehicle_record.contract_cycles LOOP
      IF EXTRACT(ISODOW FROM scheduled_at AT TIME ZONE 'America/Sao_Paulo')::integer IN (6, 7) THEN
        scheduled_at := public.next_vehicle_business_cycle(scheduled_at - interval '1 day');
        CONTINUE;
      END IF;

      cycle_no := cycle_no + 1;
      INSERT INTO public.vehicle_reward_events(vehicle_id, user_id, cycle_number, amount, status, earned_at, transferred_at)
      VALUES (vehicle_record.id, _user_id, cycle_no, vehicle_record.reward_per_cycle, 'transferred', scheduled_at, now())
      ON CONFLICT (vehicle_id, cycle_number) DO NOTHING;
      GET DIAGNOSTICS inserted_cycles = ROW_COUNT;
      credited_cycles := credited_cycles + inserted_cycles;
      scheduled_at := public.next_vehicle_business_cycle(scheduled_at);
    END LOOP;

    IF cycle_no > vehicle_record.cycles_completed OR scheduled_at IS DISTINCT FROM vehicle_record.next_reward_at THEN
      UPDATE public.user_vehicles
      SET cycles_completed = cycle_no,
          pending_reward = 0,
          transferred_reward = transferred_reward + credited_cycles * vehicle_record.reward_per_cycle,
          next_reward_at = CASE WHEN cycle_no >= vehicle_record.contract_cycles THEN NULL ELSE scheduled_at END,
          completed_at = CASE WHEN cycle_no >= vehicle_record.contract_cycles THEN now() ELSE completed_at END
      WHERE id = vehicle_record.id;

      IF credited_cycles > 0 THEN
        earned_amount := credited_cycles * vehicle_record.reward_per_cycle;
        UPDATE public.profiles
        SET reward_balance = reward_balance + earned_amount
        WHERE id = _user_id
        RETURNING reward_balance INTO next_balance;
        INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
        VALUES (_user_id, 'vehicle_reward', earned_amount, next_balance, 'Prêmios de ' || vehicle_record.name, vehicle_record.id);
        processed_total := processed_total + credited_cycles;
      END IF;
    END IF;
  END LOOP;
  RETURN processed_total;
END;
$$;

-- Rebase only outstanding cycles. Historical reward events, balances, and completed contracts stay intact.
UPDATE public.user_vehicles uv
SET next_reward_at = public.next_vehicle_business_cycle(
  COALESCE((SELECT max(e.earned_at) FROM public.vehicle_reward_events e WHERE e.vehicle_id = uv.id), uv.purchased_at)
)
WHERE uv.cycles_completed < uv.contract_cycles
  AND uv.next_reward_at IS NOT NULL;