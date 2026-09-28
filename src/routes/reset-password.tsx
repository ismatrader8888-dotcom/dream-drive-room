import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { KeyRound, Loader2 } from "lucide-react";
import bydLogo from "@/assets/byd-logo.png";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/reset-password")({
  head: () => ({ meta: [
    { title: "Redefinir senha — BYD Driving" },
    { name: "description", content: "Escolha uma nova senha para sua conta BYD Driving." },
    { property: "og:title", content: "Redefinir senha — BYD Driving" },
    { property: "og:description", content: "Escolha uma nova senha para sua conta BYD Driving." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ] }),
  component: ResetPassword,
});

function ResetPassword() {
  const [status, setStatus] = useState<"checking" | "ready" | "expired" | "done">("checking");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    const hash = new URLSearchParams(window.location.hash.slice(1));
    const query = new URLSearchParams(window.location.search);
    const hasRecovery = query.get("recovery") === "1" || hash.get("type") === "recovery" || query.has("code");
    if (hash.has("error") || query.has("error")) {
      setStatus("expired");
      return;
    }
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (active && event === "PASSWORD_RECOVERY") setStatus("ready");
    });
    void (async () => {
      // The auth client exchanges the recovery link's tokens on initialization.
      const { data } = await supabase.auth.getSession();
      if (!active) return;
      setStatus(hasRecovery && data.session ? "ready" : "expired");
    })();
    return () => { active = false; subscription.unsubscribe(); };
  }, []);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError("");
    if (password.length < 8) { setError("A senha deve ter pelo menos 8 caracteres."); return; }
    if (password !== confirmation) { setError("As senhas não são iguais."); return; }
    setSaving(true);
    const { error: updateError } = await supabase.auth.updateUser({ password });
    if (updateError) setError("Não foi possível alterar a senha. Peça um novo link e tente novamente.");
    else {
      await supabase.auth.signOut();
      setStatus("done");
      window.history.replaceState(null, "", "/reset-password");
    }
    setSaving(false);
  };

  return <main className="grid min-h-screen place-items-center bg-shell px-5 py-10 text-foreground">
    <section className="w-full max-w-md rounded-lg border border-border bg-card p-7 shadow-card">
      <img src={bydLogo} alt="BYD Driving" className="mx-auto h-20 w-20 object-contain" />
      <h1 className="mt-5 text-center text-2xl font-bold">Redefinir senha</h1>
      {status === "checking" && <p className="mt-6 flex items-center justify-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Verificando link...</p>}
      {status === "expired" && <p className="mt-6 text-center text-sm text-destructive">Este link não é válido ou expirou. Solicite um novo link ao suporte.</p>}
      {status === "done" && <p className="mt-6 text-center text-sm text-foreground">Senha atualizada. Entre novamente com a sua nova senha.</p>}
      {status === "ready" && <form onSubmit={submit} className="mt-6 space-y-4">
        <label className="block text-sm">Nova senha<input type="password" autoComplete="new-password" required minLength={8} value={password} onChange={(event) => setPassword(event.target.value)} className="mt-2 h-12 w-full rounded-md border border-border bg-background px-3 outline-none focus:border-primary" /></label>
        <label className="block text-sm">Confirme a senha<input type="password" autoComplete="new-password" required minLength={8} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} className="mt-2 h-12 w-full rounded-md border border-border bg-background px-3 outline-none focus:border-primary" /></label>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <Button type="submit" disabled={saving} className="h-12 w-full">{saving ? <Loader2 className="animate-spin" /> : <><KeyRound /> Salvar nova senha</>}</Button>
      </form>}
      {(status === "done" || status === "expired") && <Button asChild variant="outline" className="mt-6 w-full"><a href="/">Ir para o login</a></Button>}
    </section>
  </main>;
}