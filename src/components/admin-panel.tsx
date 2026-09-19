import { useCallback, useEffect, useState } from "react";
import { ArrowLeft, BarChart3, CarFront, RefreshCw, Users, WalletCards } from "lucide-react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

type Profile = { id: string; email: string | null; phone: string | null; balance: number; inviteCode: string; referrals: number };
type RequestRow = { id: string; userId: string; email: string | null; amount: number; status: string; createdAt: string; pixKey?: string };
type Purchase = { id: string; email: string | null; name: string; price: number | null; region: string; createdAt: string };
type Popular = { name: string; purchases: number; volume: number };
type Dashboard = { users: number; demoBalance: number; purchases: number; pendingWithdrawals: number; pendingRecharges: number; profiles: Profile[]; withdrawals: RequestRow[]; recharges: RequestRow[]; purchasesList: Purchase[]; popularVehicles: Popular[] };
type Tab = "users" | "purchases" | "recharges" | "withdrawals";

const money = (value: number) => value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

export function AdminPanel({ onBack }: { onBack: () => void }) {
  const [data, setData] = useState<Dashboard | null>(null);
  const [tab, setTab] = useState<Tab>("users");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError("");
    const { data: result, error: requestError } = await supabase.rpc("get_admin_dashboard");
    if (requestError) { setError("Não foi possível carregar o painel administrativo."); return; }
    setData(result as unknown as Dashboard);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const adjust = async (profile: Profile) => {
    const raw = window.prompt(`Ajuste para ${profile.email ?? profile.phone ?? "usuário"}. Use valor negativo para debitar:`);
    if (!raw) return;
    const amount = Number(raw.replace(",", "."));
    const reason = window.prompt("Motivo do ajuste:")?.trim();
    if (!Number.isFinite(amount) || amount === 0 || !reason) return;
    setBusy(profile.id);
    const { error: requestError } = await supabase.rpc("admin_adjust_demo_balance", { _user_id: profile.id, _amount: amount, _reason: reason });
    setBusy(null);
    if (requestError) setError("O ajuste não pôde ser concluído. Confira o valor e tente novamente.");
    else await load();
  };

  const review = async (kind: "recharge" | "withdrawal", id: string, approve: boolean) => {
    setBusy(id);
    const { error: requestError } = kind === "recharge"
      ? await supabase.rpc("admin_review_recharge", { _request_id: id, _approve: approve })
      : await supabase.rpc("admin_review_withdrawal", { _request_id: id, _approve: approve });
    setBusy(null);
    if (requestError) setError("Não foi possível revisar esta solicitação.");
    else await load();
  };

  return (
    <div className="min-h-screen bg-background pb-10">
      <header className="flex h-16 items-center border-b border-border px-3">
        <Button variant="ghost" size="icon" onClick={onBack} aria-label="Voltar"><ArrowLeft /></Button>
        <div className="ml-2"><h1 className="font-bold">Painel administrativo</h1><p className="text-xs text-muted-foreground">Créditos demonstrativos</p></div>
        <Button variant="ghost" size="icon" onClick={() => void load()} className="ml-auto" aria-label="Atualizar"><RefreshCw /></Button>
      </header>
      {error && <p className="m-4 rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {!data ? <p className="p-8 text-center text-muted-foreground">Carregando dados...</p> : <>
        <section className="grid grid-cols-2 gap-3 p-4">
          <Metric icon={Users} label="Usuários" value={String(data.users)} />
          <Metric icon={WalletCards} label="Saldo em circulação" value={money(data.demoBalance)} />
          <Metric icon={CarFront} label="Compras" value={String(data.purchases)} />
          <Metric icon={BarChart3} label="Pendências" value={String(data.pendingWithdrawals + data.pendingRecharges)} />
        </section>
        <nav className="mx-4 grid grid-cols-4 rounded-lg bg-muted p-1 text-xs">
          {([['users','Usuários'],['purchases','Compras'],['recharges','Recargas'],['withdrawals','Saques']] as const).map(([key, label]) => <button key={key} onClick={() => setTab(key)} className={`min-h-10 rounded-md px-1 ${tab === key ? "bg-primary font-semibold text-primary-foreground" : "text-muted-foreground"}`}>{label}</button>)}
        </nav>
        <div className="space-y-3 p-4">
          {tab === "users" && data.profiles.map((profile) => <article key={profile.id} className="rounded-lg bg-card p-4 shadow-card"><b className="block truncate">{profile.email ?? profile.phone ?? "Sem identificação"}</b><div className="mt-2 grid grid-cols-2 text-sm text-muted-foreground"><span>Saldo: <strong className="text-foreground">{money(profile.balance)}</strong></span><span>Indicados: <strong className="text-foreground">{profile.referrals}</strong></span></div><p className="mt-2 text-xs text-muted-foreground">Código: {profile.inviteCode}</p><Button className="mt-3 w-full" disabled={busy === profile.id} onClick={() => void adjust(profile)}>Alterar saldo</Button></article>)}
          {tab === "purchases" && <><h2 className="font-bold">Mais comprados</h2>{data.popularVehicles.map((item) => <article key={item.name} className="flex justify-between rounded-lg bg-card p-4"><span>{item.name}</span><b>{item.purchases} compras</b></article>)}<h2 className="pt-3 font-bold">Histórico</h2>{data.purchasesList.map((item) => <article key={item.id} className="rounded-lg bg-card p-4 text-sm"><b>{item.name}</b><p className="text-muted-foreground">{item.email ?? "Usuário"} · {item.region}</p><p className="mt-1">{money(item.price ?? 0)}</p></article>)}</>}
          {tab === "recharges" && <Requests rows={data.recharges} busy={busy} onReview={(id, approve) => review("recharge", id, approve)} />}
          {tab === "withdrawals" && <Requests rows={data.withdrawals} busy={busy} onReview={(id, approve) => review("withdrawal", id, approve)} />}
        </div>
      </>}
    </div>
  );
}

function Metric({ icon: Icon, label, value }: { icon: typeof Users; label: string; value: string }) { return <article className="rounded-lg bg-card p-4 shadow-card"><Icon className="h-5 w-5 text-primary"/><p className="mt-3 text-xs text-muted-foreground">{label}</p><b className="mt-1 block text-lg">{value}</b></article>; }

function Requests({ rows, busy, onReview }: { rows: RequestRow[]; busy: string | null; onReview: (id: string, approve: boolean) => void }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma solicitação.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex justify-between gap-3"><div className="min-w-0"><b className="block truncate">{row.email ?? "Usuário"}</b><p className="text-sm text-muted-foreground">{money(row.amount)} · {row.status}</p>{row.pixKey && <p className="mt-1 break-all text-xs text-muted-foreground">PIX: {row.pixKey}</p>}</div>{row.status === "pending" && <div className="flex shrink-0 gap-2"><Button size="sm" disabled={busy === row.id} onClick={() => onReview(row.id, true)}>Aprovar</Button><Button size="sm" variant="outline" disabled={busy === row.id} onClick={() => onReview(row.id, false)}>Recusar</Button></div>}</div></article>)}</>;
}