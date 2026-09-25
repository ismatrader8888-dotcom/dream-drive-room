CREATE OR REPLACE FUNCTION public.schedule_new_vehicle_weekday()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.next_reward_at IS NOT NULL AND EXTRACT(ISODOW FROM NEW.next_reward_at AT TIME ZONE 'America/Sao_Paulo')::integer IN (6, 7) THEN
    NEW.next_reward_at := public.next_vehicle_business_cycle(NEW.purchased_at);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.schedule_new_vehicle_weekday() FROM PUBLIC;
CREATE TRIGGER schedule_new_vehicle_weekday_before_insert
BEFORE INSERT ON public.user_vehicles
FOR EACH ROW EXECUTE FUNCTION public.schedule_new_vehicle_weekday();