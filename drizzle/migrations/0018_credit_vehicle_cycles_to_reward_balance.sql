CREATE OR REPLACE FUNCTION public.process_vehicle_rewards_for(_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  vehicle_record record;
  due_cycles integer;
  inserted_cycles integer;
  processed_total integer := 0;
  earned_amount numeric(12,2);
  next_balance numeric(12,2);
BEGIN
  FOR vehicle_record IN
    SELECT id, name, purchased_at, reward_per_cycle, contract_cycles, cycles_completed
    FROM public.user_vehicles
    WHERE user_id = _user_id AND cycles_completed < contract_cycles
    FOR UPDATE
  LOOP
    due_cycles := LEAST(
      vehicle_record.contract_cycles - vehicle_record.cycles_completed,
      GREATEST(0, floor(extract(epoch FROM (now() - vehicle_record.purchased_at)) / 86400)::integer - vehicle_record.cycles_completed)
    );

    IF due_cycles > 0 THEN
      INSERT INTO public.vehicle_reward_events(vehicle_id, user_id, cycle_number, amount, status, earned_at, transferred_at)
      SELECT vehicle_record.id, _user_id, cycle_no, vehicle_record.reward_per_cycle, 'transferred',
             vehicle_record.purchased_at + (cycle_no * interval '24 hours'), now()
      FROM generate_series(vehicle_record.cycles_completed + 1, vehicle_record.cycles_completed + due_cycles) AS cycle_no
      ON CONFLICT (vehicle_id, cycle_number) DO NOTHING;

      GET DIAGNOSTICS inserted_cycles = ROW_COUNT;
      earned_amount := inserted_cycles * vehicle_record.reward_per_cycle;

      IF inserted_cycles > 0 THEN
        UPDATE public.user_vehicles
        SET cycles_completed = cycles_completed + inserted_cycles,
            pending_reward = 0,
            transferred_reward = transferred_reward + earned_amount,
            next_reward_at = CASE
              WHEN cycles_completed + inserted_cycles >= contract_cycles THEN NULL
              ELSE purchased_at + ((cycles_completed + inserted_cycles + 1) * interval '24 hours')
            END,
            completed_at = CASE
              WHEN cycles_completed + inserted_cycles >= contract_cycles THEN now()
              ELSE completed_at
            END
        WHERE id = vehicle_record.id;

        UPDATE public.profiles
        SET reward_balance = reward_balance + earned_amount
        WHERE id = _user_id
        RETURNING reward_balance INTO next_balance;

        INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description, reference_id)
        VALUES(
          _user_id,
          'vehicle_reward',
          earned_amount,
          next_balance,
          'Prêmios de ' || vehicle_record.name,
          vehicle_record.id
        );

        processed_total := processed_total + inserted_cycles;
      END IF;
    END IF;
  END LOOP;

  RETURN processed_total;
END;
$$;

REVOKE ALL ON FUNCTION public.process_vehicle_rewards_for(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_vehicle_rewards_for(uuid) TO service_role;