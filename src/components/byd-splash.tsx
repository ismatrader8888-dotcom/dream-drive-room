import bydLogo from "@/assets/byd-logo.png";

export function BydSplash() {
  return (
    <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-background">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_35%,hsl(var(--primary)/0.25),transparent_60%)]" />
      <img src={bydLogo} alt="BYD Driving" width={816} height={816} className="relative h-28 w-28 animate-pulse object-contain" />
      <h1 className="relative mt-6 text-2xl font-extrabold tracking-[0.2em] text-primary">BUILD YOUR DREAMS</h1>
      <p className="relative mt-2 text-sm text-muted-foreground">Preparando sua frota...</p>
      <div className="relative mt-6 h-1 w-48 overflow-hidden rounded-full bg-muted">
        <div className="h-full w-1/3 animate-[voltiva-drive_1.2s_linear_infinite] rounded-full bg-primary" />
      </div>
    </div>
  );
}
