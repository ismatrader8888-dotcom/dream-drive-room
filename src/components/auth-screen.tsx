import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import bydLogo from "@/assets/byd-logo.png";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { lovable } from "@/integrations/lovable/index";

type Mode = "login" | "register";

export function AuthScreen() {
  const [mode, setMode] = useState<Mode>("login");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [invite, setInvite] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");

  useEffect(() => {
    const code = new URLSearchParams(window.location.search).get("ind")?.trim().toUpperCase();
    if (code) { setInvite(code); setMode("register"); }
  }, []);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError("");
    setInfo("");
    setLoading(true);
    try {
      if (mode === "register") {
        const normalizedInvite = invite.trim().toUpperCase();
        if (normalizedInvite) {
          const { data: valid, error: validationError } = await supabase.rpc("validate_invite_code", { _code: normalizedInvite });
          if (validationError || !valid) throw new Error("INVALID_INVITE_CODE");
        }
        const { error: signUpError } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: window.location.origin,
            data: { phone, referred_by: normalizedInvite || null },
          },
        });
        if (signUpError) throw signUpError;
        setInfo("Conta criada! Entrando...");
      } else {
        const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
        if (signInError) throw signInError;
      }
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : "Não foi possível continuar.";
      setError(
        message.includes("Invalid login credentials")
          ? "E-mail ou senha incorretos."
          : message.includes("INVALID_INVITE_CODE")
            ? "Código de convite inválido. Corrija ou apague o código para continuar."
          : message.includes("already registered")
            ? "Este e-mail já possui conta. Faça login."
            : message,
      );
    } finally {
      setLoading(false);
    }
  };

  const google = async () => {
    setError("");
    const result = await lovable.auth.signInWithOAuth("google", { redirect_uri: window.location.origin });
    if (result.error) setError("Não foi possível entrar com o Google.");
  };

  return (
    <main className="min-h-screen bg-shell font-sans text-foreground">
      <div className="relative mx-auto flex min-h-screen w-full max-w-[430px] flex-col justify-center overflow-hidden bg-background px-6 shadow-phone">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,hsl(var(--primary)/0.22),transparent_55%)]" />
        <header className="relative text-center">
          <img src={bydLogo} alt="BYD Driving" width={816} height={816} className="mx-auto h-24 w-24 object-contain" />
          <h1 className="mt-4 text-3xl font-extrabold tracking-tight">BYD Driving</h1>
          <p className="mt-1 text-sm tracking-[0.25em] text-primary">BUILD YOUR DREAMS</p>
        </header>

        <div className="relative mt-8 grid grid-cols-2 rounded-full bg-card p-1 shadow-card">
          {(["login", "register"] as const).map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => { setMode(item); setError(""); setInfo(""); }}
              className={`h-10 rounded-full text-sm font-semibold transition ${mode === item ? "bg-primary text-primary-foreground" : "text-muted-foreground"}`}
            >
              {item === "login" ? "Entrar" : "Registrar"}
            </button>
          ))}
        </div>

        <form onSubmit={submit} className="relative mt-6 space-y-3 rounded-2xl bg-card p-5 shadow-card">
          <Field id="email" label="E-mail" type="email" value={email} onChange={setEmail} placeholder="voce@email.com" />
          {mode === "register" && (
            <Field id="phone" label="Telefone" type="tel" value={phone} onChange={setPhone} placeholder="11 98765-4321" required={false} />
          )}
          <Field id="password" label="Senha" type="password" value={password} onChange={setPassword} placeholder="Mínimo de 6 caracteres" />
          {mode === "register" && (
            <Field id="invite" label="Código de convite (opcional)" type="text" value={invite} onChange={(value) => setInvite(value.toUpperCase())} placeholder="Ex.: ESBXQ9XI" required={false} />
          )}
          {error && <p className="text-sm text-destructive">{error}</p>}
          {info && <p className="text-sm text-success">{info}</p>}
          <Button type="submit" disabled={loading} className="h-12 w-full rounded-full text-base">
            {loading ? <Loader2 className="animate-spin" /> : mode === "login" ? "Entrar" : "Criar conta"}
          </Button>
          <Button type="button" variant="outline" onClick={google} className="h-12 w-full rounded-full bg-transparent text-base shadow-none">
            Continuar com Google
          </Button>
        </form>

        <p className="relative mt-6 pb-8 text-center text-xs text-muted-foreground">
          Ao continuar você aceita os termos da BYD Driving.
        </p>
      </div>
    </main>
  );
}

function Field({ id, label, type, value, onChange, placeholder, required = true }: {
  id: string; label: string; type: string; value: string; onChange: (value: string) => void; placeholder: string; required?: boolean;
}) {
  return (
    <div>
      <label htmlFor={id} className="text-xs text-muted-foreground">{label}</label>
      <input
        id={id}
        type={type}
        value={value}
        required={required}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        className="mt-1 h-12 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-primary"
      />
    </div>
  );
}
