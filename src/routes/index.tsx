import { createFileRoute } from "@tanstack/react-router";
import {
  ArrowLeft,
  BadgeDollarSign,
  Bell,
  Building2,
  CalendarDays,
  CarFront,
  CheckCircle2,
  ChevronDown,
  CircleHelp,
  ClipboardCheck,
  Copy,
  CreditCard,
  FileText,
  Filter,
  Gift,
  Headphones,
  Home,
  Link2,
  ListChecks,
  MapPin,
  Medal,
  QrCode,
  RefreshCcw,
  Settings,
  ShieldCheck,
  TicketPercent,
  Users,
  WalletCards,
} from "lucide-react";
import { useEffect, useState, type ComponentType } from "react";
import cityMap from "@/assets/city-map.jpg";
import bydEntry from "@/assets/byd-entry.png";
import bydMid from "@/assets/byd-mid.png";
import bydPremium from "@/assets/byd-premium.png";
import bydTop from "@/assets/byd-top.png";
import bydLogo from "@/assets/byd-logo.png";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { ToolPage, type ToolView } from "@/components/tool-pages";
import { AuthScreen } from "@/components/auth-screen";
import { BydSplash } from "@/components/byd-splash";
import { supabase } from "@/integrations/supabase/client";

type View = "home" | "resources" | "news" | "profile" | "invite" | "membership" | ToolView;

const toolViews: ToolView[] = ["pix", "team", "contract", "salary", "vehicleIncome", "coupon", "inviteReward", "tasks", "orders", "exchange", "privacy", "about", "support", "settings", "recharge", "withdraw", "incomeDetails", "luckyDetails", "transfer"];

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "BYD Driving — Build Your Dreams" },
      { name: "description", content: "Acompanhe seus veículos, créditos e recompensas BYD Driving." },
      { property: "og:title", content: "BYD Driving — Build Your Dreams" },
      { property: "og:description", content: "Acompanhe seus veículos, créditos e recompensas BYD Driving." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

const tools: Array<{ label: string; icon: ComponentType<{ className?: string }>; view?: View; badge?: string }> = [
  { label: "Intercâmbio", icon: RefreshCcw, view: "exchange" },
  { label: "Convidar", icon: Gift, view: "invite" },
  { label: "PIX", icon: CreditCard, view: "pix" },
  { label: "Equipe", icon: Users, view: "team" },
  { label: "Salário semanal", icon: CalendarDays, view: "contract" },
  { label: "Receber salário", icon: ClipboardCheck, view: "salary" },
  { label: "Rendimento do veículo", icon: CarFront, view: "vehicleIncome" },
  { label: "Cupom", icon: TicketPercent, view: "coupon" },
  { label: "Recompensas por convite", icon: BadgeDollarSign, view: "inviteReward" },
  { label: "Central de tarefas", icon: CheckCircle2, view: "tasks" },
  { label: "Registros de pedidos", icon: ListChecks, view: "orders" },
  { label: "Política de privacidade", icon: ShieldCheck, view: "privacy" },
  { label: "Sobre nós", icon: Building2, view: "about" },
  { label: "Atendimento ao Cliente", icon: Headphones, badge: "4", view: "support" },
  { label: "Configurações", icon: Settings, view: "settings" },
];

type Account = { phone: string | null; invite_code: string; email: string | null; demo_balance: number; reward_balance: number };

function Index() {
  const [view, setView] = useState<View>("home");
  const [owned, setOwned] = useState<OwnedVehicle[]>([]);
  const [copied, setCopied] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [booting, setBooting] = useState(false);
  const [account, setAccount] = useState<Account | null>(null);
  const [insufficient, setInsufficient] = useState<Vehicle | null>(null);
  const [renting, setRenting] = useState(false);

  const loadAccount = async (id: string) => {
    const { data: profile } = await supabase.from("profiles").select("phone, invite_code, email, demo_balance, reward_balance").eq("id", id).maybeSingle();
    if (profile) setAccount(profile as Account);
  };

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setUserId(data.session?.user.id ?? null);
      setReady(true);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, next) => {
      setUserId(next?.user.id ?? null);
      if (event === "SIGNED_IN") {
        setBooting(true);
        window.setTimeout(() => setBooting(false), 2400);
      }
      if (event === "SIGNED_OUT") {
        setOwned([]);
        setAccount(null);
        setView("home");
      }
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!userId) return;
    void loadAccount(userId);
    void supabase.from("user_vehicles").select("*").eq("user_id", userId).order("purchased_at")
      .then(({ data }) => {
        if (!data) return;
        setOwned(data.map((row) => ({
          id: row.catalog_id ?? row.id,
          name: row.name,
          region: row.region,
          daily: row.daily,
          returnValue: row.return_value,
          price: row.price,
          priceAmount: row.purchase_price ?? 0,
          cycle: row.cycle,
          imageKey: row.image_key as ImageKey,
          plate: row.plate,
          purchasedAt: new Date(row.purchased_at).getTime(),
        })));
      });
  }, [userId]);

  const copyText = async (key: string, text: string) => {
    await navigator.clipboard?.writeText(text);
    setCopied(key);
    window.setTimeout(() => setCopied(null), 1500);
  };

  const rentVehicle = async (vehicle: Vehicle) => {
    if (!userId) return;
    if ((account?.demo_balance ?? 0) < vehicle.priceAmount) { setInsufficient(vehicle); return; }
    setRenting(true);
    const { error } = await supabase.rpc("purchase_vehicle", { _catalog_id: vehicle.id });
    setRenting(false);
    if (error) {
      if (error.message.includes("INSUFFICIENT_BALANCE")) setInsufficient(vehicle);
      return;
    }
    await loadAccount(userId);
    const { data } = await supabase.from("user_vehicles").select("*").eq("user_id", userId).order("purchased_at");
    if (data) setOwned(data.map((row) => ({ name: row.name, region: row.region, daily: row.daily, returnValue: row.return_value, price: row.price, priceAmount: row.purchase_price ?? 0, cycle: row.cycle, imageKey: row.image_key as ImageKey, plate: row.plate, purchasedAt: new Date(row.purchased_at).getTime(), id: row.catalog_id ?? row.id })));
    setView("resources");
  };

  if (!ready) return <BydSplash />;
  if (!userId) return <AuthScreen />;
  if (booting) return <BydSplash />;

  const displayName = account?.phone || account?.email || "Minha conta";
  const inviteCode = account?.invite_code ?? "--------";

  const isTool = toolViews.includes(view as ToolView);

  const page = isTool ? (
    <ToolPage view={view as ToolView} onBack={() => setView("profile")} balance={account?.demo_balance ?? 0} rewardBalance={account?.reward_balance ?? 0} onBalanceChanged={() => userId && loadAccount(userId)} />
  ) : view === "invite" ? (
    <InvitePage onBack={() => setView("profile")} copyText={copyText} copied={copied} displayName={displayName} inviteCode={inviteCode} />
  ) : view === "membership" ? (
    <MembershipPage onBack={() => setView("profile")} displayName={displayName} inviteCode={inviteCode} />
  ) : view === "profile" ? (
    <ProfilePage onNavigate={setView} displayName={displayName} inviteCode={inviteCode} balance={account?.demo_balance ?? 0} rewardBalance={account?.reward_balance ?? 0} />
  ) : view === "resources" ? (
    <ResourcesPage owned={owned} onBuy={() => setView("home")} />
  ) : view === "news" ? (
    <SimplePage icon={FileText} title="Notícias" copy="As novidades da sua frota aparecerão aqui." />
  ) : (
    <MarketplacePage onRent={rentVehicle} renting={renting} />
  );

  return (
    <main className="min-h-screen bg-shell font-sans text-foreground">
      <div className="mx-auto min-h-screen w-full max-w-[430px] overflow-hidden bg-background shadow-phone">
        {page}
        {!isTool && view !== "invite" && view !== "membership" && <BottomNav view={view} onNavigate={setView} />}
        <Dialog open={Boolean(insufficient)} onOpenChange={(open) => { if (!open) setInsufficient(null); }}>
          <DialogContent className="max-w-[calc(100%-2rem)] rounded-xl">
            <DialogHeader><DialogTitle>Créditos insuficientes</DialogTitle><DialogDescription>Você precisa de {insufficient?.price} em créditos do jogo para ativar este veículo. Faça uma recarga PIX para continuar.</DialogDescription></DialogHeader>
            <DialogFooter><Button variant="outline" onClick={() => setInsufficient(null)}>Agora não</Button><Button onClick={() => { setInsufficient(null); setView("recharge"); }}>Ir para recarga PIX</Button></DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </main>
  );
}

type OwnedVehicle = Vehicle & { plate: string; purchasedAt: number };

const CYCLE_MS = 24 * 60 * 60 * 1000;

function useCountdown(target: number) {
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);
  if (now === null) return "--:--:--";
  const diff = Math.max(0, target - now);
  const days = Math.floor(diff / 86400000);
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${days}d ${pad(Math.floor(diff / 3600000) % 24)}:${pad(Math.floor(diff / 60000) % 60)}:${pad(Math.floor(diff / 1000) % 60)}`;
}

type ImageKey = "entry" | "mid" | "premium" | "top";

const vehicleImages: Record<ImageKey, string> = { entry: bydEntry, mid: bydMid, premium: bydPremium, top: bydTop };

type Vehicle = {
  id: string;
  name: string;
  region: string;
  daily: string;
  returnValue: string;
  price: string;
  priceAmount: number;
  cycle: string;
  imageKey: ImageKey;
};

const vehicles: Vehicle[] = [
  { id: "dolphin-mini-new-york", name: "BYD Dolphin Mini", region: "New York", daily: "R$ 5,00/dia", returnValue: "R$ 125,00", price: "R$ 62,50", priceAmount: 62.5, cycle: "25 dias úteis", imageKey: "entry" },
  { id: "yangwang-u8-new-york", name: "Yangwang U8", region: "New York", daily: "R$ 50,00/dia", returnValue: "R$ 1.250,00", price: "R$ 625,00", priceAmount: 625, cycle: "25 dias úteis", imageKey: "top" },
  { id: "dolphin-israel", name: "BYD Dolphin", region: "Israel", daily: "R$ 8,00/dia", returnValue: "R$ 200,00", price: "R$ 100,00", priceAmount: 100, cycle: "25 dias úteis", imageKey: "mid" },
  { id: "han-alemanha", name: "BYD Han", region: "Alemanha", daily: "R$ 18,00/dia", returnValue: "R$ 450,00", price: "R$ 225,00", priceAmount: 225, cycle: "25 dias úteis", imageKey: "premium" },
  { id: "han-ev-dubai", name: "BYD Han EV", region: "Dubai", daily: "R$ 25,00/dia", returnValue: "R$ 625,00", price: "R$ 312,50", priceAmount: 312.5, cycle: "25 dias úteis", imageKey: "premium" },
  { id: "seal-tokyo", name: "BYD Seal", region: "Tokyo", daily: "R$ 12,00/dia", returnValue: "R$ 300,00", price: "R$ 150,00", priceAmount: 150, cycle: "25 dias úteis", imageKey: "mid" },
  { id: "dolphin-paris", name: "BYD Dolphin", region: "Paris", daily: "R$ 10,00/dia", returnValue: "R$ 250,00", price: "R$ 125,00", priceAmount: 125, cycle: "25 dias úteis", imageKey: "mid" },
  { id: "han-los-angeles", name: "BYD Han", region: "Los Angeles", daily: "R$ 20,00/dia", returnValue: "R$ 500,00", price: "R$ 250,00", priceAmount: 250, cycle: "25 dias úteis", imageKey: "premium" },
  { id: "seal-jerusalem", name: "BYD Seal", region: "Jerusalém", daily: "R$ 9,00/dia", returnValue: "R$ 225,00", price: "R$ 112,50", priceAmount: 112.5, cycle: "25 dias úteis", imageKey: "mid" },
  { id: "han-berlim", name: "BYD Han", region: "Berlim", daily: "R$ 16,00/dia", returnValue: "R$ 400,00", price: "R$ 200,00", priceAmount: 200, cycle: "25 dias úteis", imageKey: "premium" },
];

const regions = ["Todos", "Israel", "Alemanha", "New York", "London", "Dubai", "Tokyo", "Paris", "Los Angeles", "Jerusalém", "Berlim"];

const toNumber = (value: string) => Number(value.replace(/[^\d,]/g, "").replace(",", "."));
const rateOf = (vehicle: Vehicle) => toNumber(vehicle.returnValue) / toNumber(vehicle.price);
type SortKey = "Padrão" | "Preço" | "Progresso" | "Recompensa";

function MarketplacePage({ onRent, renting }: { onRent: (vehicle: Vehicle) => void; renting: boolean }) {
  const [region, setRegion] = useState("Todos");
  const [period, setPeriod] = useState<"Diário" | "Ciclo">("Diário");
  const [rented, setRented] = useState<string | null>(null);
  const [sort, setSort] = useState<SortKey>("Padrão");
  const [desc, setDesc] = useState(true);
  const [showFilters, setShowFilters] = useState(false);
  const [maxPrice, setMaxPrice] = useState<number | null>(null);

  const toggleSort = (key: SortKey) => {
    if (key === "Padrão") { setSort("Padrão"); setDesc(true); setMaxPrice(null); setRegion("Todos"); return; }
    if (sort === key) setDesc((value) => !value);
    else { setSort(key); setDesc(true); }
  };

  let visible = region === "Todos" ? vehicles : vehicles.filter((vehicle) => vehicle.region === region);
  if (maxPrice !== null) visible = visible.filter((vehicle) => toNumber(vehicle.price) <= maxPrice);
  if (sort !== "Padrão") {
    const value = (vehicle: Vehicle) => (sort === "Preço" ? toNumber(vehicle.price) : sort === "Recompensa" ? toNumber(vehicle.daily) : rateOf(vehicle));
    visible = [...visible].sort((a, b) => (desc ? value(b) - value(a) : value(a) - value(b)));
  }

  const arrow = (key: SortKey) => (sort === key ? (desc ? "↓" : "↑") : "⌄");

  return (
    <div className="min-h-screen bg-highlight pb-28 pt-3">
      <div className="mx-3 grid grid-cols-2 rounded-full bg-card/70 p-1 shadow-card">
        {(["Diário", "Ciclo"] as const).map((item) => (
          <Button key={item} onClick={() => setPeriod(item)} variant={period === item ? "default" : "ghost"} className="h-10 rounded-full text-sm shadow-none">{item}</Button>
        ))}
      </div>
      <div className="mt-3 flex items-center justify-between px-3 text-xs">
        {(["Padrão", "Preço", "Progresso", "Recompensa"] as const).map((key) => (
          <button key={key} type="button" onClick={() => toggleSort(key)} className={sort === key ? "font-semibold text-primary" : ""}>
            {key}{key === "Padrão" ? "" : arrow(key)}
          </button>
        ))}
        <button type="button" onClick={() => setShowFilters((value) => !value)} className={`flex items-center gap-1 ${showFilters || maxPrice !== null ? "font-semibold text-primary" : ""}`}>Filtrar <Filter className="h-4 w-4" /></button>
      </div>
      {showFilters && (
        <div className="mx-3 mt-3 rounded-2xl bg-card p-4 shadow-card">
          <p className="text-xs text-muted-foreground">Preço máximo</p>
          <div className="mt-2 flex flex-wrap gap-2">
            {[100, 200, 350, 700].map((limit) => (
              <Button key={limit} size="sm" variant={maxPrice === limit ? "default" : "secondary"} className="rounded-full shadow-none" onClick={() => setMaxPrice(maxPrice === limit ? null : limit)}>até R$ {limit}</Button>
            ))}
            <Button size="sm" variant="ghost" className="rounded-full" onClick={() => { setMaxPrice(null); setRegion("Todos"); }}>Limpar</Button>
          </div>
        </div>
      )}
      <div className="mt-3 flex flex-wrap gap-2 px-3">
        {regions.map((item) => <Button key={item} onClick={() => setRegion(item)} variant={region === item ? "default" : "secondary"} size="sm" className="rounded-full px-4 shadow-none">{item}</Button>)}
      </div>
      <div className="mt-3 space-y-3 px-2">
        {visible.length ? visible.map((vehicle) => <MarketVehicleCard key={vehicle.id} vehicle={vehicle} period={period} rented={renting && rented === vehicle.id} onRent={() => { setRented(vehicle.id); onRent(vehicle); }} />) : <div className="rounded-2xl bg-card p-8 text-center text-sm text-muted-foreground">Novos veículos para {region} chegam em breve.</div>}
      </div>
    </div>
  );
}

function MarketVehicleCard({ vehicle, period, rented, onRent }: { vehicle: Vehicle; period: "Diário" | "Ciclo"; rented: boolean; onRent: () => void }) {
  return (
    <article className="overflow-hidden rounded-2xl bg-card shadow-card">
      <div className="grid grid-cols-[1fr_145px] gap-1 p-4 pb-2">
        <div>
          <div className="flex flex-wrap items-center gap-2"><h2 className="font-semibold">{vehicle.name}</h2><span className="rounded bg-primary px-2 py-1 text-[11px] font-semibold text-primary-foreground">Operação</span></div>
          <p className="mt-2 text-xs text-muted-foreground">Recompensa virtual <b className="text-foreground">{period === "Diário" ? vehicle.daily : vehicle.returnValue}</b></p>
          <p className="mt-1 text-xs text-muted-foreground">Retorno <b className="text-accent-foreground">{vehicle.returnValue}</b></p>
          <div className="mt-2 flex flex-wrap gap-2 text-[11px] text-muted-foreground"><span className="rounded bg-muted px-2 py-1">{vehicle.region}</span><span className="rounded bg-muted px-2 py-1">Rende seg–sex</span><span className="rounded bg-muted px-2 py-1">{vehicle.cycle}</span></div>
        </div>
        <img src={vehicleImages[vehicle.imageKey]} alt={`${vehicle.name} disponível em ${vehicle.region}`} loading="lazy" width={992} height={672} className="h-28 w-full self-center object-contain" />
      </div>
      <div className="flex items-center justify-between border-t border-border px-4 py-2"><b className="text-xl">{vehicle.price}</b><Button onClick={onRent} disabled={rented} className="h-10 rounded-full px-7 text-base shadow-none">{rented ? "Selecionado" : "Alugar"}</Button></div>
    </article>
  );
}

function ResourcesPage({ owned, onBuy }: { owned: OwnedVehicle[]; onBuy: () => void }) {
  return (
    <div className="min-h-screen pb-24">
      <div className="relative h-72 w-full overflow-hidden">
        <img src={cityMap} alt="Mapa da área de veículos" width={1200} height={700} className="h-72 w-full object-cover opacity-80" />
        <div className="absolute inset-0 bg-gradient-to-b from-background/10 to-background" />
        {owned.map((vehicle, index) => (
          <span key={vehicle.plate} className="drive-marker" style={{ animationDelay: `${index * -3.5}s` }}>
            <span className="relative grid h-9 w-9 place-items-center rounded-full bg-primary text-primary-foreground shadow-card">
              <CarFront className="h-5 w-5" />
              <span className="pulse-ring absolute inset-0 rounded-full border border-primary" />
            </span>
          </span>
        ))}
      </div>
      <section className="px-4 pt-4">
        <div className="flex items-center justify-between gap-3">
          <h1 className="text-xl font-bold">Meus veículos</h1>
          <Button variant="outline" className="h-10 rounded-full bg-card px-4 shadow-none">
            <span className="h-2 w-2 rounded-full bg-success" /> Gerando lucro <ChevronDown />
          </Button>
        </div>
        <div className="mt-3 flex gap-3">
          <Button variant="outline" className="border-primary bg-transparent text-foreground shadow-none">Veículo</Button>
        </div>
        {owned.length ? <div className="space-y-4">{owned.map((vehicle) => <VehicleCard key={vehicle.plate} vehicle={vehicle} />)}</div> : <EmptyGarage onBuy={onBuy} />}
      </section>
    </div>
  );
}

function EmptyGarage({ onBuy }: { onBuy: () => void }) {
  return (
    <div className="flex min-h-[380px] flex-col items-center justify-center text-center">
      <div className="relative mb-5 h-32 w-48">
        <div className="absolute bottom-1 left-1/2 h-24 w-28 -translate-x-1/2 rotate-45 border-8 border-muted bg-card" />
        <CarFront className="absolute left-5 top-9 h-14 w-14 text-primary" />
        <MapPin className="absolute right-4 top-0 h-9 w-9 text-accent-foreground" />
      </div>
      <p className="text-sm text-muted-foreground">Você ainda não comprou veículos</p>
      <Button variant="outline" onClick={onBuy} className="mt-5 h-12 rounded-full border-primary px-8 text-base shadow-none">Comprar veículos</Button>
    </div>
  );
}

function VehicleCard({ vehicle }: { vehicle: OwnedVehicle }) {
  const countdown = useCountdown(vehicle.purchasedAt + CYCLE_MS);
  return (
    <article className="mt-5 rounded-2xl bg-card p-4 shadow-card">
      <div className="flex items-center gap-3"><span className="rounded-md bg-primary px-2 py-1 text-xs font-semibold text-primary-foreground">Operação</span><b>{vehicle.name} • {vehicle.plate}</b></div>
      <div className="mt-5 grid grid-cols-2 gap-3 text-center">
        <div><p className="text-xs text-muted-foreground">Validade</p><p className="mt-1 font-medium">{vehicle.cycle}</p></div>
        <div><p className="text-xs text-muted-foreground">Quilometragem de hoje</p><p className="mt-1 font-medium">0.01KM</p></div>
        <div className="flex items-center justify-center"><img src={vehicleImages[vehicle.imageKey]} alt={vehicle.name} width={992} height={672} className="h-16 w-full object-contain" /></div>
        <div className="grid grid-cols-2 gap-2"><div className="rounded-lg bg-muted p-2"><b>1</b><p className="text-xs text-muted-foreground">Missões</p></div><div className="rounded-lg bg-muted p-2"><b>{vehicle.daily.replace("/dia", "")}</b><p className="text-xs text-muted-foreground">Recompensa</p></div></div>
      </div>
      <div className="mt-4 rounded-xl bg-highlight p-3 text-sm"><div className="flex justify-between"><span>◷ Próxima recompensa em</span><b className="tabular-nums text-primary">{countdown}</b></div><p className="mt-2 text-xs text-muted-foreground">Acumula {vehicle.daily} em recompensas virtuais a cada ciclo do jogo.</p></div>
    </article>
  );
}

function ProfilePage({ onNavigate, displayName, inviteCode, balance, rewardBalance }: { onNavigate: (view: View) => void; displayName: string; inviteCode: string; balance: number; rewardBalance: number }) {
  return (
    <div className="min-h-screen bg-highlight pb-24 pt-4">
      <header className="flex items-center gap-4 px-5">
        <img src={bydLogo} alt="BYD Driving" width={816} height={816} className="h-16 w-16 rounded-full bg-card object-contain p-1 shadow-card" />
        <div className="min-w-0 flex-1"><h1 className="truncate text-xl font-bold">{displayName}</h1><p className="mt-1 text-sm text-muted-foreground"><span className="rounded-full bg-primary px-2 py-0.5 text-xs font-bold text-primary-foreground">LV1</span> &nbsp;{inviteCode}</p></div>
        <Button variant="outline" size="icon" aria-label="Notificações" className="relative h-12 w-12 rounded-full bg-card shadow-card"><Bell /><span className="absolute -right-1 -top-1 rounded-full bg-foreground px-1 text-[10px] text-background">9+</span></Button>
      </header>
      <section className="mx-4 mt-5 overflow-hidden rounded-2xl bg-card shadow-card">
        <button type="button" onClick={() => onNavigate("membership")} className="flex w-full items-center justify-between bg-primary px-4 py-3 text-left text-primary-foreground"><b>◉ Vip1</b><span>Direitos de membro &gt;</span></button>
        <div className="grid grid-cols-2 divide-x divide-border p-4 text-center"><div><p>▣ Créditos do jogo</p><b className="mt-3 block text-xl">{balance.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</b><Button className="mt-2 rounded-full" onClick={() => onNavigate("recharge")}>Recarregar</Button></div><div><p>◎ Prêmios disponíveis</p><b className="mt-3 block text-xl">{rewardBalance.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</b><button type="button" onClick={() => onNavigate("luckyDetails")} className="mt-4 text-sm text-muted-foreground">Detalhes &gt;</button></div></div>
      </section>
      <section className="mx-4 mt-4 rounded-2xl bg-card p-4 shadow-card"><div className="flex justify-between"><h2 className="text-lg font-bold">Recompensas do jogo</h2><button type="button" onClick={() => onNavigate("incomeDetails")} className="text-sm text-muted-foreground">Detalhes &gt;</button></div><Row label="Prêmios disponíveis" value={rewardBalance.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}/><Row label="Recompensas de hoje" value="0,00"/><Row label="Recompensas totais" value="0,00"/><Button variant="outline" onClick={() => onNavigate("withdraw")} className="mt-3 h-12 w-full rounded-full border-primary text-base shadow-none">Sacar prêmios</Button></section>
      <section className="mx-4 mt-4 rounded-2xl bg-card p-4 shadow-card"><div className="flex justify-between"><h2 className="text-lg font-bold">Progresso de contrato</h2><span className="text-sm text-muted-foreground"><CircleHelp className="mr-1 inline h-4 w-4"/>Dica</span></div><div className="mt-5 grid grid-cols-4 items-center text-center text-xs"><div><b className="text-lg">0,00</b><p>Recompensas</p></div><div><b className="text-lg">0,00</b><p className="text-muted-foreground">A transferir</p></div><div><b className="text-lg">0,00</b><p className="text-muted-foreground">Transferido</p></div><Button variant="outline" onClick={() => onNavigate("transfer")} className="rounded-full border-primary px-2 text-muted-foreground shadow-none">Transferir</Button></div></section>
      <section className="mx-4 mt-4 grid grid-cols-4 gap-x-3 gap-y-5 rounded-2xl bg-card p-4 shadow-card">{tools.map(({ label, icon: Icon, view, badge }) => <button type="button" key={label} onClick={() => view && onNavigate(view)} className="relative flex min-w-0 flex-col items-center gap-2 text-center text-xs text-muted-foreground"><span className="grid h-11 w-11 place-items-center rounded-full bg-primary text-primary-foreground"><Icon className="h-5 w-5" /></span>{badge && <span className="absolute right-1 top-0 rounded-full bg-destructive px-1.5 text-[10px] text-destructive-foreground">{badge}</span>}<span>{label}</span></button>)}</section>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) { return <div className="mt-3 flex justify-between text-sm"><span className="text-muted-foreground">{label}</span><b>{value}</b></div>; }

function InvitePage({ onBack, copyText, copied, displayName, inviteCode }: { onBack: () => void; copyText: (key: string, text: string) => void; copied: string | null; displayName: string; inviteCode: string }) {
  const link = `${window.location.origin}/?ind=${inviteCode}`;
  return <div className="min-h-screen bg-highlight px-4 pb-8"><PageHeader title="Convidar amigos" onBack={onBack}/><section className="rounded-2xl bg-card p-6 text-center"><img src={bydLogo} alt="BYD Driving" width={816} height={816} className="mx-auto h-12 w-12 object-contain" /><h2 className="mt-3 truncate text-xl font-bold">{displayName}</h2><p className="mt-2">Compartilhar código QR ou link com amigos</p><div className="mx-auto mt-5 grid h-48 w-48 place-items-center rounded-xl bg-muted"><QrCode className="h-44 w-44" /></div><p className="mt-5 text-sm text-muted-foreground">Faça uma captura de tela ou salve o código QR</p></section><section className="mt-4 rounded-2xl bg-card p-5"><p className="text-sm text-muted-foreground">Código de convite</p><CopyRow value={inviteCode} onCopy={() => copyText("code", inviteCode)} copied={copied === "code"}/><div className="my-4 h-px bg-border"/><p className="text-sm text-muted-foreground">Convidar para conectar</p><CopyRow value={link} onCopy={() => copyText("link", link)} copied={copied === "link"}/></section></div>;
}

function CopyRow({ value, onCopy, copied }: { value: string; onCopy: () => void; copied: boolean }) { return <div className="mt-2 flex items-center gap-3"><span className="min-w-0 flex-1 break-all text-left text-lg font-medium">{value}</span><Button variant="secondary" onClick={onCopy} className="shrink-0">{copied ? "Copiado" : <><Copy/>Copiar</>}</Button></div>; }

function MembershipPage({ onBack, displayName, inviteCode }: { onBack: () => void; displayName: string; inviteCode: string }) { return <div className="min-h-screen bg-background px-4"><PageHeader title="Direitos de membro" onBack={onBack}/><section className="rounded-2xl bg-primary p-5 text-primary-foreground"><div className="flex items-center gap-4"><img src={bydLogo} alt="BYD Driving" width={816} height={816} className="h-12 w-12 rounded-full bg-card object-contain p-1" /><div className="min-w-0"><b className="block truncate">{displayName}</b><p className="text-sm">{inviteCode}</p></div><Medal className="ml-auto h-12 w-12"/></div><p className="mt-7">Programa de níveis de associação chegando em breve.</p><p className="mt-2">Em breve você poderá subir de nível e aumentar seus ganhos.</p><b className="block text-right text-3xl">LV1</b></section><h2 className="my-6 text-2xl font-bold">Direitos de membro</h2><section className="grid grid-cols-3 gap-3 rounded-2xl bg-card p-5 text-center text-xs shadow-card"><Benefit icon={Home} text="Obtenha mais bônus"/><Benefit icon={BadgeDollarSign} text="Consiga um emprego bem remunerado"/><Benefit icon={Link2} text="Acesso prioritário a veículos"/></section><h2 className="my-6 text-2xl font-bold">Descrições dos níveis de associação</h2><section className="rounded-2xl bg-card p-10 text-center shadow-card"><span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-muted text-muted-foreground">◷</span><b className="mt-4 block">Disponível em breve</b><p className="mt-2 text-sm text-muted-foreground">Os níveis de associação e suas recompensas estão sendo preparados. Volte em breve!</p></section></div>; }

function Benefit({ icon: Icon, text }: { icon: ComponentType<{ className?: string }>; text: string }) { return <div className="flex flex-col items-center gap-3"><span className="grid h-10 w-10 place-items-center rounded-lg border border-border"><Icon className="h-5 w-5"/></span><span>{text}</span></div>; }
function PageHeader({ title, onBack }: { title: string; onBack: () => void }) { return <header className="relative flex h-16 items-center justify-center"><Button variant="ghost" size="icon" onClick={onBack} aria-label="Voltar" className="absolute left-0"><ArrowLeft/></Button><h1 className="text-lg font-bold">{title}</h1></header>; }
function SimplePage({ icon: Icon, title, copy }: { icon: ComponentType<{ className?: string }>; title: string; copy: string }) { return <div className="flex min-h-[80vh] flex-col items-center justify-center px-8 text-center"><span className="grid h-20 w-20 place-items-center rounded-full bg-primary text-primary-foreground"><Icon className="h-9 w-9"/></span><h1 className="mt-5 text-2xl font-bold">{title}</h1><p className="mt-2 text-muted-foreground">{copy}</p></div>; }

function BottomNav({ view, onNavigate }: { view: View; onNavigate: (view: View) => void }) {
  const items: Array<{ view: View; label: string; icon: ComponentType<{ className?: string }> }> = [{ view: "home", label: "Lar", icon: Home }, { view: "resources", label: "Recursos", icon: CarFront }, { view: "news", label: "Notícias", icon: FileText }, { view: "profile", label: "Minha", icon: Users }];
  return <nav className="fixed bottom-0 left-1/2 z-20 grid h-20 w-full max-w-[430px] -translate-x-1/2 grid-cols-4 border-t border-border bg-card">{items.map(({ view: itemView, label, icon: Icon }) => <button type="button" key={itemView} onClick={() => onNavigate(itemView)} className={`relative flex flex-col items-center justify-center gap-1 text-xs ${view === itemView ? "text-foreground" : "text-muted-foreground"}`}><Icon className="h-6 w-6"/><span>{label}</span>{itemView === "profile" && <span className="absolute right-[28%] top-1 rounded-full bg-foreground px-1 text-[10px] text-background">13</span>}</button>)}</nav>;
}