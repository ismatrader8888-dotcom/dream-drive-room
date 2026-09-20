import { useCallback, useEffect, useState } from "react";
import { BarChart3, CarFront, LogOut, RefreshCw, Users, WalletCards } from "lucide-react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

type Profile = { id: string; email: string | null; phone: string | null; balance: number; rewardBalance: number; inviteCode: string; referredBy: string | null; referrals: number; effectiveReferrals: number; referralBonus: number };
type RequestRow = { id: string; userId: string; email: string | null; amount: number; status: string; createdAt: string; pixKey?: string };
type PixCharge = RequestRow & { payerName: string; magicId: string | null; creditedAt: string | null; refereeBonus: number; referrerBonus: number };
type Purchase = { id: string; email: string | null; name: string; price: number | null; region: string; createdAt: string };
type Popular = { name: string; purchases: number; volume: number };
type Referral = { id: string; referrerEmail: string | null; referredEmail: string | null; inviteCode: string; status: "effective" | "invalid"; firstDeposit: number | null; deposits: number; totalDeposited: number; refereeBonus: number; referrerBonus: number };
type Dashboard = { users: number; gameCredits: number; rewardBalance: number; purchases: number; pendingWithdrawals: number; pendingPix: number; totalReferrals: number; effectiveReferrals: number; referredDepositVolume: number; referralCreditsDistributed: number; profiles: Profile[]; withdrawals: RequestRow[]; pixCharges: PixCharge[]; purchasesList: Purchase[]; popularVehicles: Popular[]; referrals: Referral[] };
type Tab = "users" | "purchases" | "recharges" | "withdrawals" | "referrals";

const money = (value: number) => value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

export function AdminPanel({ onSignOut }: { onSignOut: () => void }) {
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
  useEffect(() => {
    const channel = supabase.channel("admin-pix-charges").on("postgres_changes", { event: "*", schema: "public", table: "pix_charges" }, () => void load()).subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load]);

  const adjust = async (profile: Profile) => {
    const wallet = window.prompt("Qual carteira deseja alterar? Digite créditos ou prêmios:")?.trim().toLowerCase();
    if (wallet !== "créditos" && wallet !== "creditos" && wallet !== "prêmios" && wallet !== "premios") return;
    const raw = window.prompt(`Ajuste para ${profile.email ?? profile.phone ?? "usuário"}. Use valor negativo para debitar:`);
    if (!raw) return;
    const amount = Number(raw.replace(",", "."));
    const reason = window.prompt("Motivo do ajuste:")?.trim();
    if (!Number.isFinite(amount) || amount === 0 || !reason) return;
    setBusy(profile.id);
    const { error: requestError } = await supabase.rpc("admin_adjust_balance", { _user_id: profile.id, _wallet: wallet.startsWith("cr") ? "credits" : "rewards", _amount: amount, _reason: reason });
    setBusy(null);
    if (requestError) setError("O ajuste não pôde ser concluído. Confira o valor e tente novamente.");
    else await load();
  };

  const review = async (id: string, approve: boolean) => {
    setBusy(id);
    const { error: requestError } = await supabase.rpc("admin_review_withdrawal", { _request_id: id, _approve: approve });
    setBusy(null);
    if (requestError) setError("Não foi possível revisar esta solicitação.");
    else await load();
  };

  return (
    <div className="min-h-screen bg-background pb-10">
      <header className="flex h-20 items-center border-b border-border px-6 lg:px-10">
        <div><h1 className="text-xl font-bold">BYD Driving Admin</h1><p className="text-sm text-muted-foreground">Gestão do jogo e pagamentos</p></div>
        <div className="ml-auto flex gap-2"><Button variant="outline" size="icon" onClick={() => void load()} aria-label="Atualizar"><RefreshCw /></Button><Button variant="outline" onClick={onSignOut}><LogOut /> Sair</Button></div>
      </header>
      {error && <p className="m-4 rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {!data ? <p className="p-8 text-center text-muted-foreground">Carregando dados...</p> : <>
        <main className="mx-auto max-w-[1440px] p-6 lg:p-10">
        <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <Metric icon={Users} label="Usuários" value={String(data.users)} />
          <Metric icon={WalletCards} label="Créditos do jogo" value={money(data.gameCredits)} />
          <Metric icon={CarFront} label="Compras" value={String(data.purchases)} />
          <Metric icon={BarChart3} label="Pendências" value={String(data.pendingWithdrawals + data.pendingPix)} />
          <Metric icon={Users} label="Indicações eficazes" value={`${data.effectiveReferrals} / ${data.totalReferrals}`} />
          <Metric icon={WalletCards} label="Volume indicado" value={money(data.referredDepositVolume)} />
          <Metric icon={BarChart3} label="Bônus distribuídos" value={money(data.referralCreditsDistributed)} />
        </section>
        <nav className="mt-8 grid max-w-4xl grid-cols-5 rounded-lg bg-muted p-1 text-sm">
          {([['users','Usuários'],['purchases','Compras'],['recharges','Recargas'],['referrals','Indicações'],['withdrawals','Saques']] as const).map(([key, label]) => <button key={key} onClick={() => setTab(key)} className={`min-h-10 rounded-md px-1 ${tab === key ? "bg-primary font-semibold text-primary-foreground" : "text-muted-foreground"}`}>{label}</button>)}
        </nav>
        <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {tab === "users" && data.profiles.map((profile) => <article key={profile.id} className="rounded-lg bg-card p-5 shadow-card"><b className="block truncate">{profile.email ?? profile.phone ?? "Sem identificação"}</b><div className="mt-3 grid grid-cols-2 gap-2 text-sm text-muted-foreground"><span>Créditos: <strong className="block text-foreground">{money(profile.balance)}</strong></span><span>Prêmios: <strong className="block text-foreground">{money(profile.rewardBalance)}</strong></span><span>Indicados: <strong className="block text-foreground">{profile.effectiveReferrals} eficazes / {profile.referrals}</strong></span><span>Bônus: <strong className="block text-foreground">{money(profile.referralBonus)}</strong></span></div><p className="mt-3 text-xs text-muted-foreground">Código: {profile.inviteCode}{profile.referredBy ? ` · Convidado por ${profile.referredBy}` : ""}</p><Button className="mt-4 w-full" disabled={busy === profile.id} onClick={() => void adjust(profile)}>Alterar carteira</Button></article>)}
          {tab === "purchases" && <><h2 className="font-bold">Mais comprados</h2>{data.popularVehicles.map((item) => <article key={item.name} className="flex justify-between rounded-lg bg-card p-4"><span>{item.name}</span><b>{item.purchases} compras</b></article>)}<h2 className="pt-3 font-bold">Histórico</h2>{data.purchasesList.map((item) => <article key={item.id} className="rounded-lg bg-card p-4 text-sm"><b>{item.name}</b><p className="text-muted-foreground">{item.email ?? "Usuário"} · {item.region}</p><p className="mt-1">{money(item.price ?? 0)}</p></article>)}</>}
          {tab === "recharges" && <PixCharges rows={data.pixCharges} />}
          {tab === "referrals" && <Referrals rows={data.referrals} />}
          {tab === "withdrawals" && <Requests rows={data.withdrawals} busy={busy} onReview={review} />}
        </div></main>
      </>}
    </div>
  );
}

function Metric({ icon: Icon, label, value }: { icon: typeof Users; label: string; value: string }) { return <article className="rounded-lg bg-card p-4 shadow-card"><Icon className="h-5 w-5 text-primary"/><p className="mt-3 text-xs text-muted-foreground">{label}</p><b className="mt-1 block text-lg">{value}</b></article>; }

function Requests({ rows, busy, onReview }: { rows: RequestRow[]; busy: string | null; onReview: (id: string, approve: boolean) => void }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma solicitação.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex justify-between gap-3"><div className="min-w-0"><b className="block truncate">{row.email ?? "Usuário"}</b><p className="text-sm text-muted-foreground">{money(row.amount)} · {row.status}</p>{row.pixKey && <p className="mt-1 break-all text-xs text-muted-foreground">PIX: {row.pixKey}</p>}</div>{row.status === "pending" && <div className="flex shrink-0 gap-2"><Button size="sm" disabled={busy === row.id} onClick={() => onReview(row.id, true)}>Aprovar</Button><Button size="sm" variant="outline" disabled={busy === row.id} onClick={() => onReview(row.id, false)}>Recusar</Button></div>}</div></article>)}</>;
}

function PixCharges({ rows }: { rows: PixCharge[] }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma recarga PIX.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex justify-between gap-4"><div className="min-w-0"><b className="block truncate">{row.payerName}</b><p className="truncate text-sm text-muted-foreground">{row.email ?? "Usuário"}</p><p className="mt-1 text-xs text-muted-foreground">{row.magicId ?? "Gerando cobrança"}</p>{(row.refereeBonus > 0 || row.referrerBonus > 0) && <p className="mt-2 text-xs text-primary">Bônus: convidado {money(row.refereeBonus)} · dono do código {money(row.referrerBonus)}</p>}</div><div className="text-right"><b>{money(row.amount)}</b><p className={`mt-1 text-xs font-semibold ${row.status === "CONFIRMED" ? "text-primary" : "text-muted-foreground"}`}>{row.status}</p></div></div></article>)}</>;
}

function Referrals({ rows }: { rows: Referral[] }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma indicação.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><b className="block truncate">{row.referrerEmail ?? "Usuário"} → {row.referredEmail ?? "Convidado"}</b><p className="mt-1 text-xs text-muted-foreground">Código {row.inviteCode} · {row.deposits} depósito(s)</p></div><span className={`rounded-full px-2 py-1 text-xs font-semibold ${row.status === "effective" ? "bg-success/15 text-success" : "bg-muted text-muted-foreground"}`}>{row.status === "effective" ? "Eficaz" : "Aguardando"}</span></div><div className="mt-3 grid grid-cols-3 gap-2 text-sm"><span className="text-muted-foreground">Depositado<b className="block text-foreground">{money(row.totalDeposited)}</b></span><span className="text-muted-foreground">Bônus 5%<b className="block text-foreground">{money(row.refereeBonus)}</b></span><span className="text-muted-foreground">Bônus 15%<b className="block text-foreground">{money(row.referrerBonus)}</b></span></div></article>)}</>;
}