import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { Loader2, LockKeyhole } from "lucide-react";
import bydLogo from "@/assets/byd-logo.png";
import { AdminPanel } from "@/components/admin-panel";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/admin")({
  head: () => ({ meta: [
    { title: "Painel Administrativo — BYD Driving" },
    { name: "description", content: "Acesso administrativo da BYD Driving." },
    { property: "og:title", content: "Painel Administrativo — BYD Driving" },
    { property: "og:description", content: "Acesso administrativo da BYD Driving." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ] }),
  component: AdminRoute,
});

function AdminRoute() {
  const [ready, setReady] = useState(false);
  const [authorized, setAuthorized] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const verify = async () => {
    const { data: userData } = await supabase.auth.getUser();
    if (!userData.user) { setAuthorized(false); setReady(true); return; }
    const { data: role } = await supabase.from("user_roles").select("role").eq("user_id", userData.user.id).eq("role", "admin").maybeSingle();
    setAuthorized(Boolean(role));
    setReady(true);
  };

  useEffect(() => { void verify(); }, []);

  const login = async (event: React.FormEvent) => {
    event.preventDefault(); setLoading(true); setError("");
    const { error: loginError } = await supabase.auth.signInWithPassword({ email, password });
    if (loginError) { setError("E-mail ou senha de administrador incorretos."); setLoading(false); return; }
    const { data: userData } = await supabase.auth.getUser();
    const { data: role } = userData.user ? await supabase.from("user_roles").select("role").eq("user_id", userData.user.id).eq("role", "admin").maybeSingle() : { data: null };
    if (!role) { await supabase.auth.signOut(); setError("Esta conta não possui permissão administrativa."); setLoading(false); return; }
    setAuthorized(true); setLoading(false); setPassword("");
  };

  const signOut = async () => { await supabase.auth.signOut(); setAuthorized(false); setEmail(""); setPassword(""); };

  if (!ready) return <div className="grid min-h-screen place-items-center bg-background"><Loader2 className="animate-spin text-primary" /></div>;
  if (authorized) return <AdminPanel onSignOut={() => void signOut()} />;

  return <main className="grid min-h-screen place-items-center bg-shell p-6 text-foreground">
    <section className="w-full max-w-md rounded-lg border border-border bg-card p-8 shadow-card">
      <img src={bydLogo} alt="BYD Driving" className="mx-auto h-20 w-20 object-contain" />
      <div className="mt-5 text-center"><h1 className="text-2xl font-extrabold">Painel Administrativo</h1><p className="mt-1 text-sm text-muted-foreground">Acesso restrito à administração BYD Driving</p></div>
      <form onSubmit={login} className="mt-8 space-y-4">
        <label className="block text-sm">E-mail<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="username" className="mt-2 h-12 w-full rounded-md border border-border bg-background px-3 outline-none focus:border-primary" /></label>
        <label className="block text-sm">Senha<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password" className="mt-2 h-12 w-full rounded-md border border-border bg-background px-3 outline-none focus:border-primary" /></label>
        {error && <p className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
        <Button type="submit" disabled={loading} className="h-12 w-full">{loading ? <Loader2 className="animate-spin" /> : <><LockKeyhole /> Entrar no painel</>}</Button>
      </form>
    </section>
  </main>;
}