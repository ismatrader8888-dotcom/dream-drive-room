import { ArrowLeft, CheckCircle2, ClipboardCopy, ClipboardList, FileX2, FileMinus2, Plus, User, Ticket, Coins } from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import QRCode from "qrcode";
import { useServerFn } from "@tanstack/react-start";
import bydLogo from "@/assets/byd-logo.png";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { createPixCharge, syncPixCharge } from "@/lib/pix.functions";

export type ToolView =
  | "pix"
  | "team"
  | "contract"
  | "salary"
  | "vehicleIncome"
  | "coupon"
  | "inviteReward"
  | "tasks"
  | "orders"
  | "exchange"
  | "privacy"
  | "about"
  | "support"
  | "settings"
  | "recharge"
  | "withdraw"
  | "incomeDetails"
  | "luckyDetails"
  | "transfer";

export type RewardEvent = { id: string; vehicleId: string; vehicleName: string; cycle: number; amount: number; status: "pending" | "transferred"; earnedAt: string; transferredAt: string | null };
export type RewardSummary = { available: number; today: number; total: number; pending: number; transferred: number; cyclesCompleted: number; cyclesTotal: number; events: RewardEvent[] };

export function ToolHeader({ title, onBack }: { title: string; onBack: () => void }) {
  return (
    <header className="relative flex h-16 items-center justify-center border-b border-border">
      <Button variant="ghost" size="icon" onClick={onBack} aria-label="Voltar" className="absolute left-1"><ArrowLeft /></Button>
      <h1 className="text-lg font-bold">{title}</h1>
    </header>
  );
}

function EmptyState({ label = "Ainda não há dados" }: { label?: string }) {
  return (
    <div className="flex min-h-[46vh] flex-col items-center justify-center gap-3 text-muted-foreground">
      <FileX2 className="h-16 w-16 opacity-50" />
      <p className="text-sm">{label}</p>
    </div>
  );
}

function Shell({ title, onBack, children }: { title: string; onBack: () => void; children: ReactNode }) {
  return (
    <div className="min-h-screen bg-background pb-28">
      <ToolHeader title={title} onBack={onBack} />
      {children}
    </div>
  );
}

function Tabs({ items, value, onChange }: { items: string[]; value: string; onChange: (v: string) => void }) {
  return (
    <div className="m-4 grid gap-2 rounded-xl bg-muted p-1" style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}>
      {items.map((item) => (
        <button
          key={item}
          type="button"
          onClick={() => onChange(item)}
          className={`rounded-lg px-2 py-2 text-sm font-medium transition ${value === item ? "bg-primary text-primary-foreground" : "text-muted-foreground"}`}
        >
          {item}
        </button>
      ))}
    </div>
  );
}

function PixPage({ onBack }: { onBack: () => void }) {
  const [keys, setKeys] = useState<Array<{ id: string; key_value: string }>>([]);
  const [draft, setDraft] = useState("");
  const [open, setOpen] = useState(false);
  const loadKeys = async () => {
    const { data } = await supabase.from("pix_keys").select("id, key_value").order("created_at");
    setKeys(data ?? []);
  };
  useEffect(() => { void loadKeys(); }, []);
  return (
    <Shell title="Gerenciamento de chaves" onBack={onBack}>
      {keys.length ? (
        <ul className="space-y-3 p-4">
          {keys.map((key) => (
            <li key={key.id} className="flex items-center justify-between rounded-xl bg-card p-4 shadow-card">
              <span className="min-w-0 break-all text-sm">{key.key_value}</span>
              <Button variant="ghost" size="sm" onClick={async () => { await supabase.from("pix_keys").delete().eq("id", key.id); await loadKeys(); }}>Remover</Button>
            </li>
          ))}
        </ul>
      ) : <EmptyState />}
      {open && (
        <div className="mx-4 rounded-xl bg-card p-4 shadow-card">
          <label className="text-sm text-muted-foreground" htmlFor="pix-key">Nova chave PIX</label>
          <input id="pix-key" value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="CPF, e-mail ou telefone" className="mt-2 h-11 w-full rounded-lg border border-border bg-background px-3 text-sm outline-none focus:border-primary" />
          <div className="mt-3 flex gap-2">
            <Button className="flex-1" onClick={async () => { const value = draft.trim(); if (!value) return; const { data: { user } } = await supabase.auth.getUser(); if (!user) return; await supabase.from("pix_keys").insert({ user_id: user.id, key_value: value }); setDraft(""); setOpen(false); await loadKeys(); }}>Salvar</Button>
            <Button variant="secondary" onClick={() => setOpen(false)}>Cancelar</Button>
          </div>
        </div>
      )}
      <div className="fixed bottom-4 left-1/2 w-full max-w-[430px] -translate-x-1/2 px-4">
        <Button className="h-14 w-full rounded-xl text-base" onClick={() => setOpen(true)}><Plus /> Chave PIX</Button>
      </div>
    </Shell>
  );
}

function TeamPage({ onBack }: { onBack: () => void }) {
  const [tab, setTab] = useState("Eficiente");
  const [data, setData] = useState<ReferralDashboard | null>(null);
  useEffect(() => { void supabase.rpc("get_my_referral_dashboard").then(({ data: result }) => setData(result as unknown as ReferralDashboard)); }, []);
  const members = (data?.members ?? []).filter((member) => member.status === (tab === "Eficiente" ? "effective" : "invalid"));
  return (
    <Shell title="Minha Equipe" onBack={onBack}>
      <section className="m-4 grid grid-cols-2 gap-4 rounded-2xl bg-card p-5 text-center shadow-card">
        <div><p className="text-sm text-muted-foreground">Créditos da equipe</p><b className="mt-2 block text-xl">{money(data?.teamEarned ?? 0)}</b></div>
        <div><p className="text-sm text-muted-foreground">Membros eficazes</p><b className="mt-2 block text-xl">{data?.effectiveMembers ?? 0} / {data?.totalMembers ?? 0}</b></div>
      </section>
      <section className="m-4 grid grid-cols-2 gap-4 rounded-2xl bg-card p-5 text-center shadow-card">
        <div><p className="text-sm text-muted-foreground">Bônus de hoje</p><b className="mt-2 block text-xl">{money(data?.earnedToday ?? 0)}</b></div>
        <div><p className="text-sm text-muted-foreground">Depósitos de hoje</p><b className="mt-2 block text-xl">{money(data?.depositedToday ?? 0)}</b></div>
      </section>
      <Tabs items={["Eficiente", "Inválido"]} value={tab} onChange={setTab} />
      {members.length ? <div className="space-y-3 px-4">{members.map((member) => <article key={member.id} className="rounded-xl bg-card p-4 shadow-card"><div className="flex items-center justify-between gap-3"><b className="truncate">{member.displayName}</b><span className={`rounded-full px-2 py-1 text-xs font-semibold ${member.status === "effective" ? "bg-success/15 text-success" : "bg-muted text-muted-foreground"}`}>{member.status === "effective" ? "Eficiente" : "Aguardando depósito"}</span></div><div className="mt-3 grid grid-cols-2 gap-2 text-sm text-muted-foreground"><span>Depósitos <b className="block text-foreground">{member.deposits}</b></span><span>Bônus recebido <b className="block text-foreground">{money(member.bonusEarned)}</b></span></div></article>)}</div> : <EmptyState label={tab === "Eficiente" ? "Nenhum membro eficaz ainda" : "Nenhum membro aguardando depósito"} />}
    </Shell>
  );
}

type ReferralMember = { id: string; displayName: string; status: "effective" | "invalid"; deposits: number; bonusEarned: number };
type ReferralReward = { id: string; type: "referee_first_deposit" | "referrer_commission"; depositAmount: number; percentage: number; creditAmount: number; createdAt: string; memberName: string };
type ReferralDashboard = { totalMembers: number; effectiveMembers: number; totalDeposited: number; totalEarned: number; teamEarned: number; earnedToday: number; depositedToday: number; members: ReferralMember[]; rewards: ReferralReward[] };
const money = (value: number) => value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

function ContractPage({ onBack }: { onBack: () => void }) {
  return (
    <Shell title="Contrato semanal" onBack={onBack}>
      <article className="m-4 space-y-4 rounded-2xl bg-card p-5 text-sm leading-relaxed shadow-card">
        <div className="flex items-center gap-3"><img src={bydLogo} alt="BYD Driving" width={816} height={816} className="h-10 w-10 object-contain" /><b>BYD DRIVING COMPANHIA DE INTELIGÊNCIA AUTOMOTIVA LTDA</b></div>
        <h2 className="text-center font-bold">CONTRATO DE TRABALHO EM REGIME DE TEMPO PARCIAL</h2>
        <p><b>EMPREGADOR:</b> BYD DRIVING<br />Endereço: a definir<br />CNPJ: a definir</p>
        <p><b>EMPREGADO:</b><br />Nome do Empregado: ______________<br />Endereço residencial: ______________<br />C.P.F.: ______________</p>
        {[
          ["1. Natureza do Contrato", "Este contrato é regido pela legislação brasileira (CLT), caracterizando vínculo de trabalho parcial, sem subordinação do empregador."],
          ["2. Atividades", "O(a) contratado(a) exercerá a função de: auxiliar a empresa na promoção do conceito de carros autônomos, cumprir as diretrizes da gestão da empresa e ajudar os membros da equipe."],
          ["3. Local de Trabalho", "Sem local fixo, podendo atuar remotamente ou em locais designados."],
          ["4. Jornada de Trabalho", "Trabalhar no mínimo 30 horas por semana. Funcionários com excelente desempenho podem solicitar um aumento salarial ao seu gerente."],
          ["5. Remuneração", "5.1 Salário semanal: R$ ______\n5.2 O pagamento semanal é recebido aos domingos, com atraso máximo de 5 dias úteis. O pagamento pode ser feito por transferência bancária ou pagamento online."],
          ["6. Direitos e Obrigações", "6.1 O empregador deverá pagar corretamente e garantir condições de trabalho.\n6.2 O empregado deverá cumprir suas funções, respeitar regras internas e manter sigilo.\n6.3 Ambas as partes devem cumprir a legislação trabalhista e fiscal brasileira."],
          ["7. Rescisão", "7.1 Este contrato pode ser encerrado por acordo entre as partes.\n7.2 Qualquer parte pode rescindir com aviso prévio de 7 dias.\n7.3 Valores pendentes devem ser quitados na rescisão."],
          ["8. Legislação e Foro", "Este contrato segue a legislação brasileira (CLT). Em caso de disputa, será competente a Justiça do Trabalho."],
        ].map(([title, body]) => (
          <div key={title}><b>{title}</b><p className="mt-1 whitespace-pre-line text-muted-foreground">{body}</p></div>
        ))}
        <p className="pt-2"><b>Assinaturas:</b><br />EMPREGADOR: ______________<br />EMPREGADO: ______________<br />Data: ______________</p>
      </article>
    </Shell>
  );
}

function SalaryPage({ onBack }: { onBack: () => void }) {
  return (
    <Shell title="Recompensa de salário" onBack={onBack}>
      <div className="bg-primary px-4 py-6 text-center text-primary-foreground">
        <p className="text-sm">Total recebido de salário</p>
        <b className="mt-1 block text-3xl">R$ 0,00</b>
      </div>
      <EmptyState />
    </Shell>
  );
}

function VehicleIncomePage({ onBack, rewards }: { onBack: () => void; rewards: RewardSummary }) {
  const [range, setRange] = useState("Hoje");
  return (
    <Shell title="Receita de Veículos" onBack={onBack}>
      <div className="flex justify-end p-4 pb-0">
        <Button className="rounded-lg" onClick={() => setRange((current) => (current === "Hoje" ? "Total" : "Hoje"))}>{range}</Button>
      </div>
      <section className="grid grid-cols-2 divide-x divide-border p-4 text-center">
        <div><p className="text-sm text-muted-foreground">Ciclos</p><b className="mt-1 block text-xl">{range === "Hoje" ? rewards.events.filter((event) => new Date(event.earnedAt).toLocaleDateString("pt-BR") === new Date().toLocaleDateString("pt-BR")).length : rewards.cyclesCompleted}</b></div>
        <div><p className="text-sm text-muted-foreground">Recompensas</p><b className="mt-1 block text-xl">{money(range === "Hoje" ? rewards.today : rewards.total)}</b></div>
      </section>
      <RewardHistory events={range === "Hoje" ? rewards.events.filter((event) => new Date(event.earnedAt).toLocaleDateString("pt-BR") === new Date().toLocaleDateString("pt-BR")) : rewards.events} />
    </Shell>
  );
}

function CouponPage({ onBack }: { onBack: () => void }) {
  const [tab, setTab] = useState("Recebido");
  return (
    <Shell title="Meu cupom" onBack={onBack}>
      <Tabs items={["Recebido", "Usado", "Expirado"]} value={tab} onChange={setTab} />
      <div className="flex min-h-[46vh] flex-col items-center justify-center gap-3 text-muted-foreground"><Ticket className="h-16 w-16 opacity-50" /><p className="text-sm">Ainda não há dados</p></div>
    </Shell>
  );
}

function InviteRewardPage({ onBack }: { onBack: () => void }) {
  const [data, setData] = useState<ReferralDashboard | null>(null);
  useEffect(() => { void supabase.rpc("get_my_referral_dashboard").then(({ data: result }) => setData(result as unknown as ReferralDashboard)); }, []);
  return (
    <Shell title="Recompensas por convite" onBack={onBack}>
      <section className="m-4 rounded-2xl bg-card p-5 shadow-card"><p className="text-sm text-muted-foreground">Total em créditos do jogo</p><b className="mt-1 block text-3xl">{money(data?.totalEarned ?? 0)}</b><p className="mt-2 text-xs text-muted-foreground">5% no primeiro depósito feito com convite e 15% para quem convidou em cada depósito confirmado.</p></section>
      {data?.rewards.length ? <div className="space-y-3 px-4">{data.rewards.map((reward) => <article key={reward.id} className="rounded-xl bg-card p-4 shadow-card"><div className="flex justify-between gap-3"><div><b>{reward.type === "referee_first_deposit" ? "Bônus de boas-vindas" : `Depósito de ${reward.memberName}`}</b><p className="mt-1 text-xs text-muted-foreground">{reward.percentage}% sobre {money(reward.depositAmount)} · {new Date(reward.createdAt).toLocaleDateString("pt-BR")}</p></div><b className="text-primary">+{money(reward.creditAmount)}</b></div></article>)}</div> : <div className="flex min-h-[45vh] flex-col items-center justify-center gap-3 text-muted-foreground"><FileMinus2 className="h-16 w-16 opacity-50" /><p className="text-sm">Nenhum bônus recebido ainda</p></div>}
    </Shell>
  );
}

function TasksPage({ onBack }: { onBack: () => void }) {
  const [tab, setTab] = useState("Tarefa pessoal");
  return (
    <Shell title="Central de Tarefas" onBack={onBack}>
      <Tabs items={["Tarefa pessoal", "Tarefas da equipe"]} value={tab} onChange={setTab} />
      {tab === "Tarefa pessoal" ? (
        <div className="space-y-4 px-4">
          <section className="rounded-2xl border-l-4 border-primary bg-card p-4 shadow-card">
            <p className="text-sm text-muted-foreground">Prêmio da rodada</p>
            <div className="mt-3 grid grid-cols-2 divide-x divide-border text-sm">
              <div><p className="text-muted-foreground">Bola da Sorte</p><b>+3</b></div>
              <div className="pl-4"><p className="text-muted-foreground">Saldo em dinheiro</p><b>+R$ 5,00</b></div>
            </div>
          </section>
          <section className="rounded-2xl bg-card p-4 shadow-card">
            <div className="flex items-start justify-between gap-3">
              <b>1. Progresso da tarefa</b>
              <span className="rounded-full bg-muted px-3 py-1 text-xs text-muted-foreground">● Aguardando o primeiro convite</span>
            </div>
            <div className="mt-4 flex items-center gap-3"><span className="grid h-10 w-10 place-items-center rounded-full bg-muted"><User className="h-5 w-5" /></span><b className="text-lg">Convide 3 amigos</b></div>
            <p className="mt-4 text-center"><b>0</b><span className="text-muted-foreground">/ 3 Concluído</span></p>
            <div className="mt-3 flex justify-around">{[0, 1, 2].map((index) => <span key={index} className="h-6 w-6 rounded-full border border-border" />)}</div>
            <Button variant="secondary" className="mt-4 h-12 w-full rounded-xl">Convide mais 3 para resgatar</Button>
          </section>
          <section className="rounded-2xl bg-card p-4 shadow-card">
            <b>2. Descrição da recompensa</b>
            <p className="mt-3 font-semibold">Como funciona esta tarefa</p>
            <p className="mt-2 text-sm text-muted-foreground">Convide novos usuários através do seu link de convite e alcance a meta dentro do prazo para receber sua recompensa.</p>
            <ul className="mt-3 list-disc space-y-1 pl-5 text-sm text-muted-foreground">
              <li>O primeiro convite válido inicia a contagem.</li>
              <li>Cada amigo deve completar o cadastro e ativar sua conta.</li>
              <li>A recompensa é creditada automaticamente após a meta.</li>
            </ul>
          </section>
        </div>
      ) : (
        <section className="mx-4 flex min-h-[220px] flex-col items-center justify-center gap-3 rounded-2xl bg-card p-6 text-muted-foreground shadow-card">
          <span className="grid h-14 w-14 place-items-center rounded-full bg-muted"><ClipboardList className="h-6 w-6" /></span>
          <p className="text-sm">Nenhuma tarefa da equipe disponível</p>
        </section>
      )}
    </Shell>
  );
}

function OrdersPage({ onBack }: { onBack: () => void }) {
  const [tab, setTab] = useState("veículo");
  const [lucky, setLucky] = useState(false);
  return (
    <Shell title="Meu pedido" onBack={onBack}>
      <Tabs items={["veículo", "Ponto de carregamento"]} value={tab} onChange={setTab} />
      <label className="mx-4 flex items-center gap-3 rounded-xl bg-card p-4 text-sm shadow-card">
        <input type="checkbox" checked={lucky} onChange={(event) => setLucky(event.target.checked)} className="h-4 w-4 accent-[hsl(var(--primary))]" />
        Ver apenas pedidos de Valor da sorte
      </label>
      <EmptyState />
    </Shell>
  );
}

function BalancePage({ title, onBack, mode, balance, rewardBalance, onBalanceChanged }: { title: string; onBack: () => void; mode: "recharge" | "withdraw" | "transfer"; balance: number; rewardBalance: number; onBalanceChanged: () => void }) {
  const createCharge = useServerFn(createPixCharge);
  const syncCharge = useServerFn(syncPixCharge);
  const [amount, setAmount] = useState("");
  const [message, setMessage] = useState("");
  const [pixKey, setPixKey] = useState("");
  const [name, setName] = useState("");
  const [document, setDocument] = useState("");
  const [charge, setCharge] = useState<{ id: string; code: string; image: string; expiresAt: string } | null>(null);
  const [remaining, setRemaining] = useState(300);
  const [busy, setBusy] = useState(false);
  const [withdrawals, setWithdrawals] = useState<Array<{ id: string; full_name: string; pix_key: string; amount: number; status: string; created_at: string }>>([]);
  const loadWithdrawals = async () => {
    if (mode !== "withdraw") return;
    const { data } = await supabase.from("withdrawal_requests").select("id, full_name, pix_key, amount, status, created_at").order("created_at", { ascending: false });
    setWithdrawals(data ?? []);
  };
  useEffect(() => { void loadWithdrawals(); }, [mode]);
  useEffect(() => {
    if (mode !== "recharge" || charge) return;
    let active = true;
    const syncLatest = async () => {
      const { data } = await supabase.from("pix_charges").select("id").eq("status", "PENDING").order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (!active || !data) return;
      try {
        const result = await syncCharge({ data: { chargeId: data.id } });
        if (active && result.status === "CONFIRMED") {
          setMessage("Pagamento confirmado. Seus créditos já estão disponíveis.");
          void onBalanceChanged();
        }
      } catch { /* O webhook continua sendo a confirmação principal. */ }
    };
    void syncLatest();
    return () => { active = false; };
  }, [charge, mode, onBalanceChanged, syncCharge]);
  useEffect(() => {
    if (!charge) return;
    const update = () => setRemaining(Math.max(0, Math.ceil((new Date(charge.expiresAt).getTime() - Date.now()) / 1000)));
    update();
    const timer = window.setInterval(update, 1000);
    return () => window.clearInterval(timer);
  }, [charge]);
  useEffect(() => {
    if (!charge) return;
    const applyStatus = (status?: string) => {
      if (status === "CONFIRMED") { setMessage("Pagamento confirmado. Seus créditos já estão disponíveis."); void onBalanceChanged(); }
      else if (status === "EXPIRED") setMessage("Este QR Code expirou. Gere uma nova cobrança.");
      else if (status === "FAILED") setMessage("O pagamento não pôde ser processado.");
    };
    const channel = supabase.channel(`pix-${charge.id}`).on("postgres_changes", { event: "UPDATE", schema: "public", table: "pix_charges", filter: `id=eq.${charge.id}` }, (payload) => {
      applyStatus((payload.new as { status?: string }).status);
    }).subscribe();
    const poll = window.setInterval(async () => {
      try {
        const result = await syncCharge({ data: { chargeId: charge.id } });
        applyStatus(result.status);
      } catch {
        const { data } = await supabase.from("pix_charges").select("status").eq("id", charge.id).maybeSingle();
        applyStatus(data?.status);
      }
    }, 4000);
    return () => { window.clearInterval(poll); void supabase.removeChannel(channel); };
  }, [charge, onBalanceChanged, syncCharge]);
  const submit = async () => {
    const value = Number(amount.replace(",", "."));
    if (!Number.isFinite(value) || value <= 0) return;
    setBusy(true); setMessage("");
    if (mode === "recharge") {
      try {
        const result = await createCharge({ data: { amount: value, name, document } });
        if (!result.ok) setMessage(result.error === "PIX_SETUP_REQUIRED" ? "A recarga PIX está aguardando a ativação da SagacePay." : "Não foi possível gerar o PIX. Tente novamente.");
        else {
          const image = await QRCode.toDataURL(result.qrCode, { width: 320, margin: 2 });
          setCharge({ id: result.chargeId, code: result.qrCode, image, expiresAt: result.expiresAt });
        }
      } catch { setMessage("Confira o nome completo, CPF e valor informados."); }
    } else if (mode === "withdraw") {
      const { error } = await supabase.rpc("request_withdrawal", { _amount: value, _pix_key: pixKey, _full_name: name.trim() });
      setMessage(error ? "Não foi possível solicitar. Confira seus prêmios, a chave PIX e pendências." : "Solicitação de saque registrada para análise.");
      if (!error) { setAmount(""); setPixKey(""); setName(""); await loadWithdrawals(); }
    } else {
      setMessage("Transferências estarão disponíveis em breve.");
    }
    setBusy(false); onBalanceChanged();
  };
  return (
    <Shell title={title} onBack={onBack}>
      <section className="m-4 rounded-2xl bg-card p-5 shadow-card">
        <p className="text-sm text-muted-foreground">{mode === "withdraw" ? "Prêmios disponíveis" : "Créditos do jogo"}</p>
        <b className="mt-1 block text-3xl">{(mode === "withdraw" ? rewardBalance : balance).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</b>
        <p className="mt-1 text-xs text-muted-foreground">{mode === "withdraw" ? "Somente prêmios concedidos podem ser sacados." : "Use seus créditos para veículos e ações dentro do jogo."}</p>
        {(mode === "recharge" || mode === "withdraw") && !charge && <><label className="mt-5 block text-sm text-muted-foreground" htmlFor="payer-name">Nome completo</label><input id="payer-name" autoComplete="name" value={name} onChange={(event) => setName(event.target.value)} placeholder={mode === "withdraw" ? "Nome do titular" : "Nome do pagador"} className="mt-2 h-12 w-full rounded-lg border border-border bg-background px-3 outline-none focus:border-primary" />{mode === "recharge" && <><label className="mt-4 block text-sm text-muted-foreground" htmlFor="payer-document">CPF</label><input id="payer-document" inputMode="numeric" value={document} onChange={(event) => setDocument(event.target.value.replace(/\D/g, "").slice(0, 11))} placeholder="000.000.000-00" className="mt-2 h-12 w-full rounded-lg border border-border bg-background px-3 outline-none focus:border-primary" /></>}</>}
        {!charge && <>
        <label className="mt-5 block text-sm text-muted-foreground" htmlFor="amount">Valor</label>
        <input id="amount" inputMode="decimal" value={amount} onChange={(event) => { setAmount(event.target.value); setMessage(""); }} placeholder="0,00" className="mt-2 h-12 w-full rounded-lg border border-border bg-background px-3 text-lg outline-none focus:border-primary" />
        {mode === "withdraw" && <><label className="mt-4 block text-sm text-muted-foreground" htmlFor="withdraw-pix">Chave PIX</label><input id="withdraw-pix" value={pixKey} onChange={(event) => setPixKey(event.target.value)} placeholder="CPF, e-mail ou telefone" className="mt-2 h-12 w-full rounded-lg border border-border bg-background px-3 outline-none focus:border-primary" /></>}
        <div className="mt-3 flex flex-wrap gap-2">{["10", "50", "100", "500"].map((value) => <Button key={value} variant="secondary" size="sm" className="rounded-full" onClick={() => setAmount(value)}>R$ {value}</Button>)}</div>
        <Button className="mt-5 h-12 w-full rounded-full text-base" disabled={!amount || busy || (mode === "withdraw" && (!pixKey.trim() || name.trim().length < 5))} onClick={() => void submit()}>
          {mode === "recharge" ? "Recarregar agora" : mode === "withdraw" ? "Solicitar saque" : "Transferir"}
        </Button>
        </>}
        {charge && <div className="mt-5 text-center"><div className="mx-auto w-fit rounded-xl bg-white p-3"><img src={charge.image} alt="QR Code PIX" className="h-56 w-56" /></div><p className="mt-3 text-sm font-semibold">Aguardando pagamento</p><p className="mt-1 text-xs tabular-nums text-muted-foreground">Expira em {String(Math.floor(remaining / 60)).padStart(2, "0")}:{String(remaining % 60).padStart(2, "0")}</p><Button variant="outline" className="mt-3 w-full" onClick={async () => { await navigator.clipboard.writeText(charge.code); setMessage("Código PIX copiado."); }}><ClipboardCopy /> Copiar PIX</Button>{remaining === 0 && <Button className="mt-2 w-full" onClick={() => { setCharge(null); setMessage(""); }}>Gerar novo PIX</Button>}</div>}
        {message.includes("confirmado") && <CheckCircle2 className="mx-auto mt-4 h-8 w-8 text-primary" />}
        {message && <p className="mt-3 text-center text-sm text-muted-foreground">{message}</p>}
      </section>
      {mode === "withdraw" && <p className="px-6 text-center text-xs text-muted-foreground">Saques exigem uma chave PIX cadastrada.</p>}
      {mode === "withdraw" && <section className="mx-4 mt-5"><h2 className="font-bold">Histórico de saques</h2>{withdrawals.length ? <div className="mt-3 space-y-3">{withdrawals.map((item) => <article key={item.id} className="rounded-xl bg-card p-4 shadow-card"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><b className="block truncate">{item.full_name}</b><p className="mt-1 break-all text-xs text-muted-foreground">PIX: {item.pix_key}</p><p className="mt-1 text-xs text-muted-foreground">{new Date(item.created_at).toLocaleString("pt-BR")}</p></div><div className="text-right"><b>{money(item.amount)}</b><p className="mt-1 text-xs font-semibold text-muted-foreground">{item.status === "pending" ? "Pendente" : item.status === "approved" ? "Pago" : "Recusado"}</p></div></div></article>)}</div> : <EmptyState label="Nenhuma solicitação de saque" />}</section>}
    </Shell>
  );
}

function DetailsPage({ title, onBack }: { title: string; onBack: () => void }) {
  return <Shell title={title} onBack={onBack}><EmptyState /></Shell>;
}

function RewardHistory({ events }: { events: RewardEvent[] }) {
  if (!events.length) return <EmptyState label="Nenhuma recompensa concluída" />;
  return <div className="space-y-3 px-4">{events.map((event) => <article key={event.id} className="flex items-center justify-between rounded-xl bg-card p-4 shadow-card"><div className="min-w-0"><b className="block truncate">{event.vehicleName}</b><p className="text-xs text-muted-foreground">Ciclo {event.cycle} · {new Date(event.earnedAt).toLocaleString("pt-BR")}</p></div><div className="text-right"><b className="text-primary">+{money(event.amount)}</b><p className="text-xs text-muted-foreground">{event.status === "transferred" ? "Creditado no jogo" : "Processando"}</p></div></article>)}</div>;
}

function RewardDetailsPage({ title, onBack, rewards }: { title: string; onBack: () => void; rewards: RewardSummary }) {
  return <Shell title={title} onBack={onBack}><section className="m-4 grid grid-cols-3 gap-2 rounded-2xl bg-card p-4 text-center shadow-card"><div><p className="text-xs text-muted-foreground">Hoje</p><b>{money(rewards.today)}</b></div><div><p className="text-xs text-muted-foreground">Total</p><b>{money(rewards.total)}</b></div><div><p className="text-xs text-muted-foreground">Creditado</p><b>{money(rewards.transferred)}</b></div></section><RewardHistory events={rewards.events} /></Shell>;
}

function TransferRewardsPage({ onBack, rewards, onBalanceChanged }: { onBack: () => void; rewards: RewardSummary; onBalanceChanged: () => void }) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const transfer = async () => {
    setBusy(true); setMessage("");
    const { data, error } = await supabase.rpc("transfer_my_vehicle_rewards");
    setBusy(false);
    if (error) { setMessage("Não foi possível transferir agora."); return; }
    const amount = Number(data ?? 0);
    setMessage(amount > 0 ? `${money(amount)} transferidos.` : "As recompensas dos veículos entram automaticamente nos créditos do jogo.");
    onBalanceChanged();
  };
  return <Shell title="Recompensas dos veículos" onBack={onBack}><section className="m-4 rounded-2xl bg-card p-5 shadow-card"><p className="text-sm text-muted-foreground">Créditos virtuais acumulados</p><b className="mt-1 block text-3xl">{money(rewards.total)}</b><p className="mt-3 text-sm text-muted-foreground">Cada ciclo concluído entra automaticamente nos créditos</p><Button className="mt-5 h-12 w-full rounded-full" disabled={busy} onClick={() => void transfer()}>{busy ? "Atualizando..." : "Atualizar recompensas"}</Button>{message && <p className="mt-3 text-center text-sm text-muted-foreground">{message}</p>}</section></Shell>;
}

function TextPage({ title, onBack, paragraphs }: { title: string; onBack: () => void; paragraphs: string[] }) {
  return (
    <Shell title={title} onBack={onBack}>
      <article className="m-4 space-y-3 rounded-2xl bg-card p-5 text-sm leading-relaxed text-muted-foreground shadow-card">
        {paragraphs.map((text) => <p key={text}>{text}</p>)}
      </article>
    </Shell>
  );
}

function SettingsPage({ onBack }: { onBack: () => void }) {
  const [notifications, setNotifications] = useState(true);
  const [sounds, setSounds] = useState(false);
  const rows: Array<[string, boolean, (value: boolean) => void]> = [
    ["Notificações push", notifications, setNotifications],
    ["Sons do aplicativo", sounds, setSounds],
  ];
  return (
    <Shell title="Configurações" onBack={onBack}>
      <section className="m-4 divide-y divide-border rounded-2xl bg-card shadow-card">
        {rows.map(([label, value, set]) => (
          <button key={label} type="button" onClick={() => set(!value)} className="flex w-full items-center justify-between p-4 text-left text-sm">
            <span>{label}</span>
            <span className={`h-6 w-11 rounded-full p-1 transition ${value ? "bg-primary" : "bg-muted"}`}><span className={`block h-4 w-4 rounded-full bg-card transition ${value ? "translate-x-5" : ""}`} /></span>
          </button>
        ))}
        <div className="flex items-center justify-between p-4 text-sm"><span>Idioma</span><span className="text-muted-foreground">Português (BR)</span></div>
        <div className="flex items-center justify-between p-4 text-sm"><span>Versão</span><span className="text-muted-foreground">1.0.4</span></div>
      </section>
      <div className="px-4"><Button variant="outline" className="h-12 w-full rounded-full" onClick={() => { void supabase.auth.signOut(); }}>Sair da conta</Button></div>
    </Shell>
  );
}

function ExchangePage({ onBack }: { onBack: () => void }) {
  const [code, setCode] = useState("");
  const [message, setMessage] = useState("");
  return (
    <Shell title="Intercâmbio" onBack={onBack}>
      <section className="m-4 rounded-2xl bg-card p-5 shadow-card">
        <p className="text-sm text-muted-foreground">Insira o código de resgate</p>
        <input value={code} onChange={(event) => { setCode(event.target.value); setMessage(""); }} placeholder="Ex.: BYD-2026" className="mt-2 h-12 w-full rounded-lg border border-border bg-background px-3 uppercase outline-none focus:border-primary" />
        <Button className="mt-4 h-12 w-full rounded-full" disabled={!code} onClick={() => setMessage("Código inválido ou já utilizado.")}>Resgatar</Button>
        {message && <p className="mt-3 text-center text-sm text-destructive">{message}</p>}
      </section>
    </Shell>
  );
}

function SupportPage({ onBack }: { onBack: () => void }) {
  return (
    <Shell title="Atendimento ao Cliente" onBack={onBack}>
      <section className="m-4 space-y-3 rounded-2xl bg-card p-5 shadow-card text-sm">
        <p className="text-muted-foreground">Nossa equipe responde de segunda a sábado, das 8h às 20h.</p>
        <div className="flex items-center justify-between rounded-xl bg-muted p-4"><span>Suporte no WhatsApp</span><Coins className="h-5 w-5 text-primary" /></div>
        <div className="flex items-center justify-between rounded-xl bg-muted p-4"><span>suporte@byddriving.app</span></div>
        <Button className="h-12 w-full rounded-full">Iniciar conversa</Button>
      </section>
    </Shell>
  );
}

export function ToolPage({ view, onBack, balance = 0, rewardBalance = 0, rewards, onBalanceChanged = () => undefined }: { view: ToolView; onBack: () => void; balance?: number; rewardBalance?: number; rewards: RewardSummary; onBalanceChanged?: () => void }) {
  switch (view) {
    case "pix": return <PixPage onBack={onBack} />;
    case "team": return <TeamPage onBack={onBack} />;
    case "contract": return <ContractPage onBack={onBack} />;
    case "salary": return <SalaryPage onBack={onBack} />;
    case "vehicleIncome": return <VehicleIncomePage onBack={onBack} rewards={rewards} />;
    case "coupon": return <CouponPage onBack={onBack} />;
    case "inviteReward": return <InviteRewardPage onBack={onBack} />;
    case "tasks": return <TasksPage onBack={onBack} />;
    case "orders": return <OrdersPage onBack={onBack} />;
    case "exchange": return <ExchangePage onBack={onBack} />;
    case "settings": return <SettingsPage onBack={onBack} />;
    case "support": return <SupportPage onBack={onBack} />;
    case "recharge": return <BalancePage title="Recarga PIX" onBack={onBack} mode="recharge" balance={balance} rewardBalance={rewardBalance} onBalanceChanged={onBalanceChanged} />;
    case "withdraw": return <BalancePage title="Sacar prêmios" onBack={onBack} mode="withdraw" balance={balance} rewardBalance={rewardBalance} onBalanceChanged={onBalanceChanged} />;
    case "transfer": return <TransferRewardsPage onBack={onBack} rewards={rewards} onBalanceChanged={onBalanceChanged} />;
    case "incomeDetails": return <RewardDetailsPage title="Detalhes das recompensas" onBack={onBack} rewards={rewards} />;
    case "luckyDetails": return <RewardDetailsPage title="Histórico de prêmios" onBack={onBack} rewards={rewards} />;
    case "privacy": return <TextPage title="Política de privacidade" onBack={onBack} paragraphs={[
      "A BYD Driving coleta apenas os dados necessários para criar e manter sua conta: e-mail, telefone, código de convite e histórico de operações dos veículos.",
      "Para gerar uma cobrança PIX, seu nome e CPF são enviados à processadora de pagamentos. Armazenamos somente o nome e os quatro últimos dígitos do documento para conciliação.",
      "Créditos comprados por PIX são usados dentro do jogo e não podem ser convertidos em dinheiro. Somente prêmios concedidos pela empresa podem ser solicitados para saque.",
      "Não vendemos nem compartilhamos seus dados com terceiros para fins publicitários.",
      "Você pode solicitar a exclusão da sua conta e dos dados relacionados a qualquer momento pelo atendimento ao cliente.",
      "Utilizamos criptografia em trânsito para proteger as informações trocadas entre o aplicativo e nossos servidores.",
    ]} />;
    case "about": return <TextPage title="Sobre nós" onBack={onBack} paragraphs={[
      "A BYD Driving é uma plataforma de mobilidade elétrica que conecta pessoas a frotas de veículos autônomos em grandes centros urbanos.",
      "Cada veículo ativado opera em uma região e acumula recompensas virtuais durante o ciclo do jogo.",
      "Nossa missão é criar uma experiência de mobilidade elétrica acessível, moderna e transparente.",
    ]} />;
    default: return <DetailsPage title="Em breve" onBack={onBack} />;
  }
}
