CREATE TABLE public.admin_password_recovery_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES auth.users(id),
  target_user_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.admin_password_recovery_links TO service_role;
ALTER TABLE public.admin_password_recovery_links ENABLE ROW LEVEL SECURITY;
CREATE INDEX admin_password_recovery_links_target_created_idx ON public.admin_password_recovery_links (target_user_id, created_at DESC);
CREATE INDEX admin_password_recovery_links_admin_created_idx ON public.admin_password_recovery_links (admin_id, created_at DESC);