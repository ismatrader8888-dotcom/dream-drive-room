CREATE TABLE public.simpix_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed boolean NOT NULL DEFAULT false,
  error_message text,
  processed_at timestamptz
);
GRANT SELECT ON public.simpix_webhook_events TO authenticated;
GRANT ALL ON public.simpix_webhook_events TO service_role;
ALTER TABLE public.simpix_webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins read SimPix webhook events" ON public.simpix_webhook_events FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE INDEX simpix_webhook_events_received_idx ON public.simpix_webhook_events(received_at DESC);
CREATE INDEX simpix_webhook_events_processed_idx ON public.simpix_webhook_events(processed, received_at DESC);