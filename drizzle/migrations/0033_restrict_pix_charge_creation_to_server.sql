-- PIX charge identity, provider ID, amount and state must be written only by the trusted server, never the authenticated browser.
REVOKE ALL ON TABLE public.pix_charges FROM anon, authenticated;
GRANT SELECT ON TABLE public.pix_charges TO authenticated;
DROP POLICY IF EXISTS "Users create own pix charges" ON public.pix_charges;
DROP POLICY IF EXISTS "Users update creating pix charges" ON public.pix_charges;
CREATE POLICY "No browser-created charges" ON public.pix_charges AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "No browser-updated charges" ON public.pix_charges AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);