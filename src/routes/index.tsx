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
import evCompact from "@/assets/ev-compact.png";
import evExecutive from "@/assets/ev-executive.png";
import evSuv from "@/assets/ev-suv.png";
import { Button } from "@/components/ui/button";

type View = "home" | "resources" | "news" | "profile" | "invite" | "membership";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Voltiva — Mobilidade que gera valor" },
      { name: "description", content: "Acompanhe seus veículos, rendimentos e benefícios Voltiva." },
      { property: "og:title", content: "Voltiva — Mobilidade que gera valor" },
      { property: "og:description", content: "Acompanhe seus veículos, rendimentos e benefícios Voltiva." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

const tools: Array<{ label: string; icon: ComponentType<{ className?: string }>; view?: View; badge?: string }> = [
  { label: "Intercâmbio", icon: RefreshCcw },
  { label: "Convidar", icon: Gift, view: "invite" },
  { label: "PIX", icon: CreditCard },
  { label: "Equipe", icon: Users },
  { label: "Salário semanal", icon: CalendarDays },
  { label: "Receber salário", icon: ClipboardCheck },
  { label: "Rendimento do veículo", icon: CarFront },
  { label: "Cupom", icon: TicketPercent },
  { label: "Recompensas por convite", icon: BadgeDollarSign },
  { label: "Central de tarefas", icon: CheckCircle2 },
  { label: "Registros de pedidos", icon: ListChecks },
  { label: "Política de privacidade", icon: ShieldCheck },
  { label: "Sobre nós", icon: Building2 },
  { label: "Atendimento ao Cliente", icon: Headphones, badge: "4" },
  { label: "Configurações", icon: Settings },
];

function Index() {
  const [view, setView] = useState<View>("home");
  const [owned, setOwned] = useState<OwnedVehicle[]>([]);
  const [copied, setCopied] = useState<string | null>(null);

  const copyText = async (key: string, text: string) => {
    await navigator.clipboard?.writeText(text);
    setCopied(key);
    window.setTimeout(() => setCopied(null), 1500);
  };

  const rentVehicle = (vehicle: Vehicle) => {
    setOwned((list) => [...list, { ...vehicle, plate: `VX${12178 + list.length}`, purchasedAt: Date.now() }]);
    setView("resources");
  };

  const page = view === "invite" ? (
    <InvitePage onBack={() => setView("profile")} copyText={copyText} copied={copied} />
  ) : view === "membership" ? (
    <MembershipPage onBack={() => setView("profile")} />
  ) : view === "profile" ? (
    <ProfilePage onNavigate={setView} />
  ) : view === "resources" ? (
    <ResourcesPage owned={owned} onBuy={() => setView("home")} />
  ) : view === "news" ? (
    <SimplePage icon={FileText} title="Notícias" copy="As novidades da sua frota aparecerão aqui." />
  ) : (
    <MarketplacePage onRent={rentVehicle} />
  );

  return (
    <main className="min-h-screen bg-shell font-sans text-foreground">
      <div className="mx-auto min-h-screen w-full max-w-[430px] overflow-hidden bg-background shadow-phone">
        {page}
        {view !== "invite" && view !== "membership" && <BottomNav view={view} onNavigate={setView} />}
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

type Vehicle = {
  name: string;
  region: string;
  daily: string;
  returnValue: string;
  price: string;
  cycle: string;
  image: string;
};

const vehicles: Vehicle[] = [
  { name: "EV Compacto", region: "New York", daily: "R$ 5,00/dia", returnValue: "R$ 125,00", price: "R$ 62,50", cycle: "25 dias úteis", image: evCompact },
  { name: "EV Executivo", region: "New York", daily: "R$ 50,00/dia", returnValue: "R$ 1.250,00", price: "R$ 625,00", cycle: "25 dias úteis", image: evExecutive },
  { name: "EV Urbano", region: "Israel", daily: "R$ 8,00/dia", returnValue: "R$ 200,00", price: "R$ 100,00", cycle: "25 dias úteis", image: evCompact },
  { name: "EV Premium", region: "Alemanha", daily: "R$ 18,00/dia", returnValue: "R$ 450,00", price: "R$ 225,00", cycle: "25 dias úteis", image: evExecutive },
  { name: "EV SUV", region: "Dubai", daily: "R$ 25,00/dia", returnValue: "R$ 625,00", price: "R$ 312,50", cycle: "25 dias úteis", image: evSuv },
  { name: "EV Neo", region: "Tokyo", daily: "R$ 12,00/dia", returnValue: "R$ 300,00", price: "R$ 150,00", cycle: "25 dias úteis", image: evExecutive },
  { name: "EV Citadino", region: "Paris", daily: "R$ 10,00/dia", returnValue: "R$ 250,00", price: "R$ 125,00", cycle: "25 dias úteis", image: evCompact },
  { name: "EV Costa", region: "Los Angeles", daily: "R$ 20,00/dia", returnValue: "R$ 500,00", price: "R$ 250,00", cycle: "25 dias úteis", image: evSuv },
  { name: "EV Connect", region: "Jerusalém", daily: "R$ 9,00/dia", returnValue: "R$ 225,00", price: "R$ 112,50", cycle: "25 dias úteis", image: evCompact },
  { name: "EV Class", region: "Berlim", daily: "R$ 16,00/dia", returnValue: "R$ 400,00", price: "R$ 200,00", cycle: "25 dias úteis", image: evExecutive },
];

const regions = ["Todos", "Israel", "Alemanha", "New York", "London", "Dubai", "Tokyo", "Paris", "Los Angeles", "Jerusalém", "Berlim"];

function MarketplacePage({ onRent }: { onRent: (vehicle: Vehicle) => void }) {
  const [region, setRegion] = useState("Todos");
  const [period, setPeriod] = useState<"Diário" | "Ciclo">("Diário");
  const [rented, setRented] = useState<string | null>(null);
  const visible = region === "Todos" ? vehicles.filter((vehicle) => vehicle.region === "New York") : vehicles.filter((vehicle) => vehicle.region === region);

  return (
    <div className="min-h-screen bg-highlight pb-28 pt-3">
      <div className="mx-3 grid grid-cols-2 rounded-full bg-card/70 p-1 shadow-card">
        {(["Diário", "Ciclo"] as const).map((item) => (
          <Button key={item} onClick={() => setPeriod(item)} variant={period === item ? "default" : "ghost"} className="h-10 rounded-full text-sm shadow-none">{item}</Button>
        ))}
      </div>
      <div className="mt-3 flex items-center justify-between px-3 text-xs">
        <span>Padrão</span><button type="button">Preço⌄</button><button type="button">Taxa de juros⌄</button><button type="button">Renda⌄</button><button type="button" className="flex items-center gap-1">Filtrar <Filter className="h-4 w-4" /></button>
      </div>
      <div className="mt-3 flex flex-wrap gap-2 px-3">
        {regions.map((item) => <Button key={item} onClick={() => setRegion(item)} variant={region === item ? "default" : "secondary"} size="sm" className="rounded-full px-4 shadow-none">{item}</Button>)}
      </div>
      <div className="mt-3 space-y-3 px-2">
        {visible.length ? visible.map((vehicle) => <MarketVehicleCard key={`${vehicle.region}-${vehicle.name}`} vehicle={vehicle} period={period} rented={rented === vehicle.name} onRent={() => { setRented(vehicle.name); onRent(vehicle); }} />) : <div className="rounded-2xl bg-card p-8 text-center text-sm text-muted-foreground">Novos veículos para {region} chegam em breve.</div>}
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
          <p className="mt-2 text-xs text-muted-foreground">Lucro <b className="text-foreground">{period === "Diário" ? vehicle.daily : vehicle.returnValue}</b></p>
          <p className="mt-1 text-xs text-muted-foreground">Retorno <b className="text-accent-foreground">{vehicle.returnValue}</b></p>
          <div className="mt-2 flex flex-wrap gap-2 text-[11px] text-muted-foreground"><span className="rounded bg-muted px-2 py-1">{vehicle.region}</span><span className="rounded bg-muted px-2 py-1">Rende seg–sex</span><span className="rounded bg-muted px-2 py-1">{vehicle.cycle}</span></div>
        </div>
        <img src={vehicle.image} alt={`${vehicle.name} disponível em ${vehicle.region}`} loading="lazy" width={992} height={672} className="h-28 w-full self-center object-contain" />
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
          <Button variant="secondary" className="font-normal text-muted-foreground shadow-none">Ponto de carregamento</Button>
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
        <div className="flex items-center justify-center"><img src={vehicle.image} alt={vehicle.name} width={992} height={672} className="h-16 w-full object-contain" /></div>
        <div className="grid grid-cols-2 gap-2"><div className="rounded-lg bg-muted p-2"><b>1</b><p className="text-xs text-muted-foreground">Pedidos</p></div><div className="rounded-lg bg-muted p-2"><b>{vehicle.daily.replace("/dia", "")}</b><p className="text-xs text-muted-foreground">Lucro</p></div></div>
      </div>
      <div className="mt-4 rounded-xl bg-highlight p-3 text-sm"><div className="flex justify-between"><span>◷ 1º rendimento em</span><b className="tabular-nums text-primary">{countdown}</b></div><p className="mt-2 text-xs text-muted-foreground">Rende {vehicle.daily} a cada 24h da compra, em dias úteis.</p></div>
    </article>
  );
}

function ProfilePage({ onNavigate }: { onNavigate: (view: View) => void }) {
  return (
    <div className="min-h-screen bg-highlight pb-24 pt-4">
      <header className="flex items-center gap-4 px-5">
        <div className="grid h-16 w-16 place-items-center rounded-full bg-card text-[10px] font-bold shadow-card">voltiva</div>
        <div className="min-w-0 flex-1"><h1 className="text-2xl font-bold">71982172158</h1><p className="mt-1 text-sm text-muted-foreground"><span className="rounded-full bg-primary px-2 py-0.5 text-xs font-bold text-primary-foreground">LV1</span> &nbsp;ESBXQ9XI</p></div>
        <Button variant="outline" size="icon" aria-label="Notificações" className="relative h-12 w-12 rounded-full bg-card shadow-card"><Bell /><span className="absolute -right-1 -top-1 rounded-full bg-foreground px-1 text-[10px] text-background">9+</span></Button>
      </header>
      <section className="mx-4 mt-5 overflow-hidden rounded-2xl bg-card shadow-card">
        <button type="button" onClick={() => onNavigate("membership")} className="flex w-full items-center justify-between bg-primary px-4 py-3 text-left text-primary-foreground"><b>◉ Vip1</b><span>Direitos de membro &gt;</span></button>
        <div className="grid grid-cols-2 divide-x divide-border p-4 text-center"><div><p>▣ Saldo de Recarga</p><b className="mt-3 block text-xl">0,00</b><Button className="mt-2 rounded-full">Recarregar</Button></div><div><p>◎ Registro da Sorte</p><b className="mt-3 block text-xl">0,00</b><p className="mt-4 text-sm text-muted-foreground">Detalhes &gt;</p></div></div>
      </section>
      <section className="mx-4 mt-4 rounded-2xl bg-card p-4 shadow-card"><div className="flex justify-between"><h2 className="text-lg font-bold">Renda da conta</h2><span className="text-sm text-muted-foreground">Detalhes &gt;</span></div><Row label="Saldo Ganhos" value="1,00"/><Row label="Ganhos de hoje" value="1,00"/><Row label="Ganhos totais" value="1,00"/><Button variant="outline" className="mt-3 h-12 w-full rounded-full border-primary text-base shadow-none">Sacar dinheiro</Button></section>
      <section className="mx-4 mt-4 rounded-2xl bg-card p-4 shadow-card"><div className="flex justify-between"><h2 className="text-lg font-bold">Renda de contrato</h2><span className="text-sm text-muted-foreground"><CircleHelp className="mr-1 inline h-4 w-4"/>Dica</span></div><div className="mt-5 grid grid-cols-4 items-center text-center text-xs"><div><b className="text-lg">0,00</b><p>Valor da renda</p></div><div><b className="text-lg">0,00</b><p className="text-muted-foreground">A transferir</p></div><div><b className="text-lg">0,00</b><p className="text-muted-foreground">Transferido</p></div><Button variant="outline" className="rounded-full border-primary px-2 text-muted-foreground shadow-none">Transferir</Button></div></section>
      <section className="mx-4 mt-4 grid grid-cols-4 gap-x-3 gap-y-5 rounded-2xl bg-card p-4 shadow-card">{tools.map(({ label, icon: Icon, view, badge }) => <button type="button" key={label} onClick={() => view && onNavigate(view)} className="relative flex min-w-0 flex-col items-center gap-2 text-center text-xs text-muted-foreground"><span className="grid h-11 w-11 place-items-center rounded-full bg-primary text-primary-foreground"><Icon className="h-5 w-5" /></span>{badge && <span className="absolute right-1 top-0 rounded-full bg-destructive px-1.5 text-[10px] text-destructive-foreground">{badge}</span>}<span>{label}</span></button>)}</section>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) { return <div className="mt-3 flex justify-between text-sm"><span className="text-muted-foreground">{label}</span><b>{value}</b></div>; }

function InvitePage({ onBack, copyText, copied }: { onBack: () => void; copyText: (key: string, text: string) => void; copied: string | null }) {
  const link = "https://voltiva.app/registro?ind=ESBXQ9XI";
  return <div className="min-h-screen bg-highlight px-4 pb-8"><PageHeader title="Convidar amigos" onBack={onBack}/><section className="rounded-2xl bg-card p-6 text-center"><b>voltiva</b><h2 className="mt-3 text-xl font-bold">71982172158</h2><p className="mt-2">Compartilhar código QR ou link com amigos</p><div className="mx-auto mt-5 grid h-48 w-48 place-items-center rounded-xl bg-muted"><QrCode className="h-44 w-44" /></div><p className="mt-5 text-sm text-muted-foreground">Faça uma captura de tela ou salve o código QR</p></section><section className="mt-4 rounded-2xl bg-card p-5"><p className="text-sm text-muted-foreground">Código de convite</p><CopyRow value="ESBXQ9XI" onCopy={() => copyText("code", "ESBXQ9XI")} copied={copied === "code"}/><div className="my-4 h-px bg-border"/><p className="text-sm text-muted-foreground">Convidar para conectar</p><CopyRow value={link} onCopy={() => copyText("link", link)} copied={copied === "link"}/></section></div>;
}

function CopyRow({ value, onCopy, copied }: { value: string; onCopy: () => void; copied: boolean }) { return <div className="mt-2 flex items-center gap-3"><span className="min-w-0 flex-1 break-all text-left text-lg font-medium">{value}</span><Button variant="secondary" onClick={onCopy} className="shrink-0">{copied ? "Copiado" : <><Copy/>Copiar</>}</Button></div>; }

function MembershipPage({ onBack }: { onBack: () => void }) { return <div className="min-h-screen bg-background px-4"><PageHeader title="Direitos de membro" onBack={onBack}/><section className="rounded-2xl bg-primary p-5 text-primary-foreground"><div className="flex items-center gap-4"><div className="grid h-12 w-12 place-items-center rounded-full bg-card text-[9px] font-bold text-foreground">voltiva</div><div><b>71982172158</b><p className="text-sm">ESBXQ9XI</p></div><Medal className="ml-auto h-12 w-12"/></div><p className="mt-7">Programa de níveis de associação chegando em breve.</p><p className="mt-2">Em breve você poderá subir de nível e aumentar seus ganhos.</p><b className="block text-right text-3xl">LV1</b></section><h2 className="my-6 text-2xl font-bold">Direitos de membro</h2><section className="grid grid-cols-3 gap-3 rounded-2xl bg-card p-5 text-center text-xs shadow-card"><Benefit icon={Home} text="Obtenha mais bônus"/><Benefit icon={BadgeDollarSign} text="Consiga um emprego bem remunerado"/><Benefit icon={Link2} text="Acesso prioritário a veículos"/></section><h2 className="my-6 text-2xl font-bold">Descrições dos níveis de associação</h2><section className="rounded-2xl bg-card p-10 text-center shadow-card"><span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-muted text-muted-foreground">◷</span><b className="mt-4 block">Disponível em breve</b><p className="mt-2 text-sm text-muted-foreground">Os níveis de associação e suas recompensas estão sendo preparados. Volte em breve!</p></section></div>; }

function Benefit({ icon: Icon, text }: { icon: ComponentType<{ className?: string }>; text: string }) { return <div className="flex flex-col items-center gap-3"><span className="grid h-10 w-10 place-items-center rounded-lg border border-border"><Icon className="h-5 w-5"/></span><span>{text}</span></div>; }
function PageHeader({ title, onBack }: { title: string; onBack: () => void }) { return <header className="relative flex h-16 items-center justify-center"><Button variant="ghost" size="icon" onClick={onBack} aria-label="Voltar" className="absolute left-0"><ArrowLeft/></Button><h1 className="text-lg font-bold">{title}</h1></header>; }
function SimplePage({ icon: Icon, title, copy }: { icon: ComponentType<{ className?: string }>; title: string; copy: string }) { return <div className="flex min-h-[80vh] flex-col items-center justify-center px-8 text-center"><span className="grid h-20 w-20 place-items-center rounded-full bg-primary text-primary-foreground"><Icon className="h-9 w-9"/></span><h1 className="mt-5 text-2xl font-bold">{title}</h1><p className="mt-2 text-muted-foreground">{copy}</p></div>; }

function BottomNav({ view, onNavigate }: { view: View; onNavigate: (view: View) => void }) {
  const items: Array<{ view: View; label: string; icon: ComponentType<{ className?: string }> }> = [{ view: "home", label: "Lar", icon: Home }, { view: "resources", label: "Recursos", icon: CarFront }, { view: "news", label: "Notícias", icon: FileText }, { view: "profile", label: "Minha", icon: Users }];
  return <nav className="fixed bottom-0 left-1/2 z-20 grid h-20 w-full max-w-[430px] -translate-x-1/2 grid-cols-4 border-t border-border bg-card">{items.map(({ view: itemView, label, icon: Icon }) => <button type="button" key={itemView} onClick={() => onNavigate(itemView)} className={`relative flex flex-col items-center justify-center gap-1 text-xs ${view === itemView ? "text-foreground" : "text-muted-foreground"}`}><Icon className="h-6 w-6"/><span>{label}</span>{itemView === "profile" && <span className="absolute right-[28%] top-1 rounded-full bg-foreground px-1 text-[10px] text-background">13</span>}</button>)}</nav>;
}