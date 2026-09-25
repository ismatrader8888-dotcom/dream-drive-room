CREATE OR REPLACE FUNCTION public.next_vehicle_business_cycle(_anchor timestamptz)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ((_anchor AT TIME ZONE 'America/Sao_Paulo') +
    CASE EXTRACT(ISODOW FROM _anchor AT TIME ZONE 'America/Sao_Paulo')::integer
      WHEN 5 THEN interval '3 days'
      WHEN 6 THEN interval '2 days'
      WHEN 7 THEN interval '1 day'
      ELSE interval '1 day'
    END) AT TIME ZONE 'America/Sao_Paulo';
$$;
-- Correct the initial future deadline for contracts started on weekends.
UPDATE public.user_vehicles uv
SET next_reward_at = public.next_vehicle_business_cycle(uv.purchased_at)
WHERE uv.cycles_completed = 0
  AND uv.next_reward_at IS NOT NULL
  AND EXTRACT(ISODOW FROM uv.purchased_at AT TIME ZONE 'America/Sao_Paulo')::integer IN (6, 7);