import { useCallback, useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { ArrowLeft, BarChart3, CarFront, Eye, LogOut, RefreshCw, Users, WalletCards } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { supabase } from "@/integrations/supabase/client";
import { closeAdminSupportView, openAdminSupportView } from "@/lib/admin-support.functions";

type Profile = { id: string; email: string | null; phone: string | null; balance: number; rewardBalance: number; vehicleRewardsToday: number; vehicleRewardsGenerated: number; vehicleRewardsPending: number; vehicleRewardsTransferred: number; inviteCode: string; referredBy: string | null; referrals: number; effectiveReferrals: number; referralBonus: number };
type RequestRow = { id: string; userId: string; email: string | null; fullName?: string; amount: number; status: string; createdAt: string; pixKey?: string };
type PixCharge = RequestRow & { payerName: string; magicId: string | null; creditedAt: string | null; refereeBonus: number; referrerBonus: number };
type Purchase = { id: string; email: string | null; name: string; price: number | null; region: string; createdAt: string };
type Popular = { name: string; purchases: number; volume: number };
type Referral = { id: string; referrerEmail: string | null; referredEmail: string | null; inviteCode: string; status: "effective" | "invalid"; firstDeposit: number | null; deposits: number; totalDeposited: number; refereeBonus: number; referrerBonus: number };
type Dashboard = { users: number; gameCredits: number; rewardBalance: number; vehicleRewardsGenerated: number; vehicleRewardsPending: number; vehicleRewardsTransferred: number; purchases: number; pendingWithdrawals: number; pendingPix: number; totalReferrals: number; effectiveReferrals: number; referredDepositVolume: number; referralCreditsDistributed: number; profiles: Profile[]; withdrawals: RequestRow[]; pixCharges: PixCharge[]; purchasesList: Purchase[]; popularVehicles: Popular[]; referrals: Referral[] };
type Tab = "users" | "purchases" | "recharges" | "withdrawals" | "referrals" | "notifications" | "codes";
type SupportView = {
  sessionId: string;
  profile: { id: string; email: string | null; phone: string | null; inviteCode: string; referredBy: string | null; level: number; balance: number; rewardBalance: number; createdAt: string };
  vehicles: Array<{ id: string; name: string; region: string; plate: string; price: number | null; rewardPerCycle: number; cyclesCompleted: number; contractCycles: number; nextRewardAt: string | null; purchasedAt: string; completedAt: string | null }>;
  pixCharges: Array<{ id: string; amount: number; status: string; payerName: string; providerId: string | null; createdAt: string; creditedAt: string | null }>;
  withdrawals: Array<{ id: string; amount: number; status: string; fullName: string; pixKey: string; createdAt: string; reviewedAt: string | null }>;
  transactions: Array<{ id: string; type: string; amount: number; balanceAfter: number; description: string; createdAt: string }>;
  referrals: Array<{ id: string; inviteCode: string; memberEmail: string | null; effectiveAt: string | null; deposits: number; totalDeposited: number; bonus: number; createdAt: string }>;
};

const money = (value: number) => value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

export function AdminPanel({ onSignOut }: { onSignOut: () => void }) {
  const [data, setData] = useState<Dashboard | null>(null);
  const [tab, setTab] = useState<Tab>("users");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [adjusting, setAdjusting] = useState<Profile | null>(null);
  const [wallet, setWallet] = useState<"credits" | "rewards">("rewards");
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [supportView, setSupportView] = useState<SupportView | null>(null);
  const openSupport = useServerFn(openAdminSupportView);
  const closeSupport = useServerFn(closeAdminSupportView);

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

  const adjust = async () => {
    if (!adjusting) return;
    const value = Number(amount.replace(",", "."));
    if (!Number.isFinite(value) || value === 0 || reason.trim().length < 3) return;
    setBusy(adjusting.id);
    const { error: requestError } = await supabase.rpc("admin_adjust_balance", { _user_id: adjusting.id, _wallet: wallet, _amount: value, _reason: reason.trim() });
    setBusy(null);
    if (requestError) setError("O ajuste não pôde ser concluído. Confira o valor e tente novamente.");
    else { setAdjusting(null); setAmount(""); setReason(""); await load(); }
  };

  const review = async (id: string, approve: boolean) => {
    setBusy(id);
    const { error: requestError } = await supabase.rpc("admin_review_withdrawal", { _request_id: id, _approve: approve });
    setBusy(null);
    if (requestError) setError("Não foi possível revisar esta solicitação.");
    else await load();
  };

  const enterSupport = async (profile: Profile) => {
    setBusy(profile.id);
    setError("");
    try {
      const result = await openSupport({ data: { targetUserId: profile.id, userAgent: navigator.userAgent } });
      setSupportView(result as unknown as SupportView);
    } catch {
      setError("Não foi possível abrir a conta em modo de suporte.");
    } finally {
      setBusy(null);
    }
  };

  const leaveSupport = async () => {
    if (!supportView) return;
    const sessionId = supportView.sessionId;
    setSupportView(null);
    try { await closeSupport({ data: { sessionId } }); } catch { setError("A conta foi fechada, mas o encerramento não pôde ser registrado."); }
  };

  if (supportView) return <SupportAccount data={supportView} onClose={() => void leaveSupport()} />;

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
          <Metric icon={WalletCards} label="Prêmios disponíveis" value={money(data.rewardBalance)} />
          <Metric icon={BarChart3} label="Recompensas geradas" value={money(data.vehicleRewardsGenerated)} />
          <Metric icon={RefreshCw} label="Em processamento" value={money(data.vehicleRewardsPending)} />
          <Metric icon={WalletCards} label="Creditado no jogo" value={money(data.vehicleRewardsTransferred)} />
        </section>
        <nav className="mt-8 grid max-w-4xl grid-cols-4 lg:grid-cols-7 rounded-lg bg-muted p-1 text-sm">
          {([['users','Usuários'],['purchases','Compras'],['recharges','Recargas'],['referrals','Indicações'],['withdrawals','Saques'],['notifications','Notificações'],['codes','Códigos']] as const).map(([key, label]) => <button key={key} onClick={() => setTab(key)} className={`min-h-10 rounded-md px-1 ${tab === key ? "bg-primary font-semibold text-primary-foreground" : "text-muted-foreground"}`}>{label}</button>)}
        </nav>
        <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {tab === "users" && data.profiles.map((profile) => <article key={profile.id} className="rounded-lg bg-card p-5 shadow-card"><b className="block truncate">{profile.email ?? profile.phone ?? "Sem identificação"}</b><div className="mt-3 grid grid-cols-2 gap-2 text-sm text-muted-foreground"><span>Créditos: <strong className="block text-foreground">{money(profile.balance)}</strong></span><span>Prêmios disponíveis: <strong className="block text-foreground">{money(profile.rewardBalance)}</strong></span><span>Recompensas de hoje: <strong className="block text-foreground">{money(profile.vehicleRewardsToday)}</strong></span><span>Recompensas totais: <strong className="block text-foreground">{money(profile.vehicleRewardsGenerated)}</strong></span><span>Em processamento: <strong className="block text-foreground">{money(profile.vehicleRewardsPending)}</strong></span><span>Creditado no jogo: <strong className="block text-foreground">{money(profile.vehicleRewardsTransferred)}</strong></span><span>Indicados: <strong className="block text-foreground">{profile.effectiveReferrals} eficazes / {profile.referrals}</strong></span></div><p className="mt-3 text-xs text-muted-foreground">Código: {profile.inviteCode}{profile.referredBy ? ` · Convidado por ${profile.referredBy}` : ""}</p><div className="mt-4 grid grid-cols-2 gap-2"><Button variant="outline" disabled={busy === profile.id} onClick={() => void enterSupport(profile)}><Eye /> Entrar como usuário</Button><Button disabled={busy === profile.id} onClick={() => { setAdjusting(profile); setWallet("rewards"); }}>Alterar saldos</Button></div></article>)}
          {tab === "purchases" && <><h2 className="font-bold">Mais comprados</h2>{data.popularVehicles.map((item) => <article key={item.name} className="flex justify-between rounded-lg bg-card p-4"><span>{item.name}</span><b>{item.purchases} compras</b></article>)}<h2 className="pt-3 font-bold">Histórico</h2>{data.purchasesList.map((item) => <article key={item.id} className="rounded-lg bg-card p-4 text-sm"><b>{item.name}</b><p className="text-muted-foreground">{item.email ?? "Usuário"} · {item.region}</p><p className="mt-1">{money(item.price ?? 0)}</p></article>)}</>}
          {tab === "recharges" && <PixCharges rows={data.pixCharges} />}
          {tab === "referrals" && <Referrals rows={data.referrals} />}
          {tab === "withdrawals" && <Requests rows={data.withdrawals} busy={busy} onReview={review} />}
        </div></main>
       </>}
       <Dialog open={Boolean(adjusting)} onOpenChange={(open) => { if (!open) setAdjusting(null); }}><DialogContent><DialogHeader><DialogTitle>Alterar saldo do usuário</DialogTitle><DialogDescription>{adjusting?.email ?? adjusting?.phone ?? "Usuário"}. Use um valor negativo para debitar.</DialogDescription></DialogHeader><div className="space-y-4"><div className="grid grid-cols-2 gap-2"><Button type="button" variant={wallet === "credits" ? "default" : "outline"} onClick={() => setWallet("credits")}>Créditos do jogo</Button><Button type="button" variant={wallet === "rewards" ? "default" : "outline"} onClick={() => setWallet("rewards")}>Prêmios disponíveis</Button></div><label className="block text-sm">Valor<input value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" placeholder="Ex.: 50 ou -25" className="mt-2 h-11 w-full rounded-md border border-border bg-background px-3" /></label><label className="block text-sm">Motivo<input value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Motivo do ajuste" className="mt-2 h-11 w-full rounded-md border border-border bg-background px-3" /></label></div><DialogFooter><Button variant="outline" onClick={() => setAdjusting(null)}>Cancelar</Button><Button disabled={Boolean(busy)} onClick={() => void adjust()}>Confirmar ajuste</Button></DialogFooter></DialogContent></Dialog>
    </div>
  );
}

function SupportAccount({ data, onClose }: { data: SupportView; onClose: () => void }) {
  const identity = data.profile.email ?? data.profile.phone ?? "Usuário";
  return <div className="min-h-screen bg-background pb-10">
    <header className="sticky top-0 z-10 flex min-h-20 items-center gap-4 border-b border-primary/30 bg-background px-6 lg:px-10"><Button variant="outline" size="icon" onClick={onClose} aria-label="Sair do modo de suporte"><ArrowLeft /></Button><div className="min-w-0"><h1 className="truncate text-xl font-bold">Conta de {identity}</h1><p className="text-sm text-primary">Modo de suporte · somente leitura · acesso registrado</p></div></header>
    <main className="mx-auto max-w-[1440px] space-y-8 p-6 lg:p-10">
      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4"><Metric icon={WalletCards} label="Créditos" value={money(data.profile.balance)} /><Metric icon={WalletCards} label="Prêmios disponíveis" value={money(data.profile.rewardBalance)} /><Metric icon={CarFront} label="Veículos" value={String(data.vehicles.length)} /><Metric icon={Users} label="Indicados" value={String(data.referrals.length)} /></section>
      <SupportSection title="Dados da conta"><SupportRow label="E-mail" value={data.profile.email ?? "Não informado"} /><SupportRow label="Telefone" value={data.profile.phone ?? "Não informado"} /><SupportRow label="Código de convite" value={data.profile.inviteCode} /><SupportRow label="Nível" value={String(data.profile.level)} /></SupportSection>
      <SupportSection title="Veículos">{data.vehicles.length ? data.vehicles.map((item) => <article key={item.id} className="border-b border-border py-3 last:border-0"><div className="flex justify-between gap-3"><b>{item.name}</b><span>{item.cyclesCompleted}/{item.contractCycles} ciclos</span></div><p className="text-sm text-muted-foreground">{item.region} · {item.plate} · {money(item.rewardPerCycle)} por ciclo</p></article>) : <EmptySupport />}</SupportSection>
      <div className="grid gap-8 lg:grid-cols-2"><SupportSection title="Depósitos PIX">{data.pixCharges.length ? data.pixCharges.map((item) => <SupportRow key={item.id} label={`${money(item.amount)} · ${item.payerName}`} value={item.status} />) : <EmptySupport />}</SupportSection><SupportSection title="Saques">{data.withdrawals.length ? data.withdrawals.map((item) => <SupportRow key={item.id} label={`${money(item.amount)} · ${item.fullName}`} value={item.status} />) : <EmptySupport />}</SupportSection></div>
      <div className="grid gap-8 lg:grid-cols-2"><SupportSection title="Movimentações recentes">{data.transactions.length ? data.transactions.map((item) => <SupportRow key={item.id} label={item.description} value={`${item.amount >= 0 ? "+" : ""}${money(item.amount)}`} />) : <EmptySupport />}</SupportSection><SupportSection title="Indicações">{data.referrals.length ? data.referrals.map((item) => <SupportRow key={item.id} label={item.memberEmail ?? "Usuário"} value={item.effectiveAt ? `${item.deposits} depósito(s)` : "Aguardando depósito"} />) : <EmptySupport />}</SupportSection></div>
    </main>
  </div>;
}

function SupportSection({ title, children }: { title: string; children: React.ReactNode }) { return <section><h2 className="mb-3 text-lg font-bold">{title}</h2><div className="rounded-lg bg-card p-5 shadow-card">{children}</div></section>; }
function SupportRow({ label, value }: { label: string; value: string }) { return <div className="flex items-start justify-between gap-4 border-b border-border py-3 first:pt-0 last:border-0 last:pb-0"><span className="text-sm text-muted-foreground">{label}</span><b className="max-w-[55%] break-words text-right text-sm">{value}</b></div>; }
function EmptySupport() { return <p className="text-sm text-muted-foreground">Nenhum registro.</p>; }

function Metric({ icon: Icon, label, value }: { icon: typeof Users; label: string; value: string }) { return <article className="rounded-lg bg-card p-4 shadow-card"><Icon className="h-5 w-5 text-primary"/><p className="mt-3 text-xs text-muted-foreground">{label}</p><b className="mt-1 block text-lg">{value}</b></article>; }

function Requests({ rows, busy, onReview }: { rows: RequestRow[]; busy: string | null; onReview: (id: string, approve: boolean) => void }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma solicitação.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex justify-between gap-3"><div className="min-w-0"><b className="block truncate">{row.fullName || row.email || "Usuário"}</b><p className="truncate text-xs text-muted-foreground">{row.email ?? "Sem e-mail"}</p><p className="mt-1 text-sm text-muted-foreground">{money(row.amount)} · {row.status === "pending" ? "Pendente" : row.status === "approved" ? "Pago" : "Recusado"}</p>{row.pixKey && <p className="mt-1 break-all text-xs text-muted-foreground">PIX: {row.pixKey}</p>}</div>{row.status === "pending" && <div className="flex shrink-0 gap-2"><Button size="sm" disabled={busy === row.id} onClick={() => onReview(row.id, true)}>Marcar pago</Button><Button size="sm" variant="outline" disabled={busy === row.id} onClick={() => onReview(row.id, false)}>Recusar</Button></div>}</div></article>)}</>;
}

function PixCharges({ rows }: { rows: PixCharge[] }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma recarga PIX.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex justify-between gap-4"><div className="min-w-0"><b className="block truncate">{row.payerName}</b><p className="truncate text-sm text-muted-foreground">{row.email ?? "Usuário"}</p><p className="mt-1 text-xs text-muted-foreground">{row.magicId ?? "Gerando cobrança"}</p>{(row.refereeBonus > 0 || row.referrerBonus > 0) && <p className="mt-2 text-xs text-primary">Bônus: convidado {money(row.refereeBonus)} · dono do código {money(row.referrerBonus)}</p>}</div><div className="text-right"><b>{money(row.amount)}</b><p className={`mt-1 text-xs font-semibold ${row.status === "CONFIRMED" ? "text-primary" : "text-muted-foreground"}`}>{row.status}</p></div></div></article>)}</>;
}

function Referrals({ rows }: { rows: Referral[] }) {
  if (!rows.length) return <p className="py-12 text-center text-sm text-muted-foreground">Nenhuma indicação.</p>;
  return <>{rows.map((row) => <article key={row.id} className="rounded-lg bg-card p-4 shadow-card"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><b className="block truncate">{row.referrerEmail ?? "Usuário"} → {row.referredEmail ?? "Convidado"}</b><p className="mt-1 text-xs text-muted-foreground">Código {row.inviteCode} · {row.deposits} depósito(s)</p></div><span className={`rounded-full px-2 py-1 text-xs font-semibold ${row.status === "effective" ? "bg-success/15 text-success" : "bg-muted text-muted-foreground"}`}>{row.status === "effective" ? "Eficaz" : "Aguardando"}</span></div><div className="mt-3 grid grid-cols-3 gap-2 text-sm"><span className="text-muted-foreground">Depositado<b className="block text-foreground">{money(row.totalDeposited)}</b></span><span className="text-muted-foreground">Bônus 5%<b className="block text-foreground">{money(row.refereeBonus)}</b></span><span className="text-muted-foreground">Bônus 15%<b className="block text-foreground">{money(row.referrerBonus)}</b></span></div></article>)}</>;
}
function NotificationsManager() {
  const [notifs, setNotifs] = useState<any[]>([]);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);

  const load = async () => {
    const { data } = await supabase.from("global_notifications").select("*").order("created_at", { ascending: false });
    setNotifs(data ?? []);
  };

  useEffect(() => { void load(); }, []);

  const create = async () => {
    if (!title || !content) return;
    setBusy(true);
    await supabase.from("global_notifications").insert({ title, content, type: "info" });
    setTitle(""); setContent("");
    setBusy(false);
    await load();
  };

  const toggle = async (id: string, active: boolean) => {
    await supabase.from("global_notifications").update({ active }).eq("id", id);
    await load();
  };

  return (
    <div className="space-y-6">
      <section className="rounded-lg bg-card p-5 shadow-card">
        <h3 className="font-bold">Nova Notificação</h3>
        <input value={title} onChange={e => setTitle(e.target.value)} placeholder="Título" className="mt-3 w-full rounded border p-2 bg-background" />
        <textarea value={content} onChange={e => setContent(e.target.value)} placeholder="Conteúdo" className="mt-2 w-full rounded border p-2 bg-background" rows={3} />
        <Button onClick={create} disabled={busy} className="mt-3 w-full">Publicar Notificação</Button>
      </section>
      <div className="space-y-3">
        {notifs.map(n => (
          <article key={n.id} className="rounded-lg bg-card p-4 shadow-card">
            <div className="flex justify-between items-start">
              <b>{n.title}</b>
              <Button size="sm" variant={n.active ? "default" : "outline"} onClick={() => toggle(n.id, !n.active)}>
                {n.active ? "Ativa" : "Inativa"}
              </Button>
            </div>
            <p className="text-sm text-muted-foreground mt-1">{n.content}</p>
          </article>
        ))}
      </div>
    </div>
  );
}

function CodesManager() {
  const [codes, setCodes] = useState<any[]>([]);
  const [newCode, setNewCode] = useState("");
  const [amount, setAmount] = useState("");
  const [maxUses, setMaxUses] = useState("");
  const [busy, setBusy] = useState(false);

  const load = async () => {
    const { data } = await supabase.from("credit_codes").select("*").order("created_at", { ascending: false });
    setCodes(data ?? []);
  };

  useEffect(() => { void load(); }, []);

  const create = async () => {
    const val = Number(amount);
    if (!newCode || isNaN(val) || val <= 0) return;
    setBusy(true);
    await supabase.from("credit_codes").insert({ 
      code: newCode.toUpperCase(), 
      amount: val, 
      max_uses: maxUses ? Number(maxUses) : null 
    });
    setNewCode(""); setAmount(""); setMaxUses("");
    setBusy(false);
    await load();
  };

  return (
    <div className="space-y-6">
      <section className="rounded-lg bg-card p-5 shadow-card">
        <h3 className="font-bold">Gerar Código de Crédito</h3>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <input value={newCode} onChange={e => setNewCode(e.target.value)} placeholder="CÓDIGO" className="rounded border p-2 bg-background" />
          <input value={amount} onChange={e => setAmount(e.target.value)} placeholder="Valor (R$)" className="rounded border p-2 bg-background" />
          <input value={maxUses} onChange={e => setMaxUses(e.target.value)} placeholder="Máx. usos (vazio = ilimitado)" className="rounded border p-2 bg-background" />
          <Button onClick={create} disabled={busy}>Criar</Button>
        </div>
      </section>
      <div className="space-y-3">
        {codes.map(c => (
          <article key={c.id} className="rounded-lg bg-card p-4 shadow-card flex justify-between items-center">
            <div>
              <b className="text-primary">{c.code}</b>
              <p className="text-sm text-muted-foreground">R$ {c.amount} · {c.uses_count}{c.max_uses ? `/${c.max_uses}` : ""} usos</p>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
