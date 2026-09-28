-- RPCs execute as their vetted owner and do not rely on user-facing INSERT/UPDATE policies.
DROP POLICY IF EXISTS "Users request own withdrawals" ON public.withdrawal_requests;
DROP POLICY IF EXISTS "Admins update withdrawal requests" ON public.withdrawal_requests;
DROP POLICY IF EXISTS "Users request own recharges" ON public.recharge_requests;
DROP POLICY IF EXISTS "Admins update recharge requests" ON public.recharge_requests;
-- A future accidental table grant must not silently restore direct request creation or review.
CREATE POLICY "Withdrawal requests only via vetted functions" ON public.withdrawal_requests AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "Withdrawal reviews only via vetted functions" ON public.withdrawal_requests AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY "Recharge requests only via vetted functions" ON public.recharge_requests AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "Recharge reviews only via vetted functions" ON public.recharge_requests AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);