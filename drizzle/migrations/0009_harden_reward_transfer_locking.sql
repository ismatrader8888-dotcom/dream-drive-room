CREATE OR REPLACE FUNCTION public.transfer_my_vehicle_rewards()
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE transfer_amount numeric(12,2); next_balance numeric(12,2); locked_profile uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  PERFORM public.process_vehicle_rewards_for(auth.uid());
  SELECT id INTO locked_profile FROM public.profiles WHERE id = auth.uid() FOR UPDATE;
  IF locked_profile IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  SELECT coalesce(sum(amount), 0) INTO transfer_amount FROM public.vehicle_reward_events WHERE user_id = auth.uid() AND status = 'pending';
  IF transfer_amount <= 0 THEN RETURN 0; END IF;
  UPDATE public.vehicle_reward_events SET status = 'transferred', transferred_at = now() WHERE user_id = auth.uid() AND status = 'pending';
  UPDATE public.user_vehicles SET pending_reward = 0, transferred_reward = transferred_reward + pending_reward WHERE user_id = auth.uid() AND pending_reward > 0;
  UPDATE public.profiles SET reward_balance = reward_balance + transfer_amount WHERE id = auth.uid() RETURNING reward_balance INTO next_balance;
  INSERT INTO public.balance_transactions(user_id, type, amount, balance_after, description)
  VALUES(auth.uid(), 'reward_transfer', transfer_amount, next_balance, 'Transferência de recompensas dos veículos');
  RETURN transfer_amount;
END;
$$;
REVOKE ALL ON FUNCTION public.transfer_my_vehicle_rewards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_my_vehicle_rewards() TO authenticated;