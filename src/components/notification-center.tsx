import { useEffect, useState } from "react";
import { Bell } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type Notification = {
  id: string;
  title: string;
  message: string;
  created_at: string;
};

type UserState = {
  notification_id: string;
  read_at: string;
};

export function NotificationCenter({ userId, showButton = true, autoPopup = true }: { userId: string; showButton?: boolean; autoPopup?: boolean }) {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [userStates, setUserStates] = useState<Record<string, UserState>>({});
  const [activeNotification, setActiveNotification] = useState<Notification | null>(null);
  const [showHistory, setShowHistory] = useState(false);

  const load = async () => {
    const { data: notifs } = await supabase
      .from("admin_notifications")
      .select("id, title, message, created_at")
      .eq("active", true)
      .order("created_at", { ascending: false });

    const { data: states } = await supabase
      .from("notification_receipts")
      .select("notification_id, read_at")
      .eq("user_id", userId);

    if (notifs) setNotifications(notifs);
    if (states) {
      const stateMap: Record<string, UserState> = {};
      states.forEach((s: any) => {
        stateMap[s.notification_id] = s;
      });
      setUserStates(stateMap);
    }
  };

  useEffect(() => {
    if (userId) void load();
  }, [userId]);

  const unread = notifications.filter(n => !userStates[n.id]);

  useEffect(() => {
    const first = unread[0];
    if (autoPopup && first && !activeNotification && !showHistory) {
      setActiveNotification(first);
    }
  }, [unread, activeNotification, showHistory, autoPopup]);

  const dismiss = async (id: string) => {
    const { error } = await supabase
      .from("notification_receipts")
      .upsert({
        user_id: userId,
        notification_id: id,
        read_at: new Date().toISOString()
      }, { onConflict: "user_id,notification_id" });

    if (!error) {
      setUserStates(prev => ({
        ...prev,
        [id]: { notification_id: id, read_at: new Date().toISOString() }
      }));
      setActiveNotification(null);
    }
  };

  return (
    <>
      {showButton && <Button variant="outline" size="icon" aria-label="Notificações" onClick={() => setShowHistory(true)} className="relative h-12 w-12 rounded-full bg-card shadow-card">
        <Bell />
        {unread.length > 0 && <span className="absolute -right-1 -top-1 rounded-full bg-foreground px-1 text-[10px] text-background">{unread.length > 9 ? "9+" : unread.length}</span>}
      </Button>}
      <Dialog open={Boolean(activeNotification)} onOpenChange={(open) => { if (!open && activeNotification) void dismiss(activeNotification.id); }}>
        <DialogContent className="max-w-[calc(100%-2rem)] rounded-2xl">
          <DialogHeader className="text-left"><DialogTitle className="text-xl">{activeNotification?.title}</DialogTitle></DialogHeader>
          <p className="whitespace-pre-wrap text-muted-foreground">{activeNotification?.message}</p>
          {activeNotification && <Button className="mt-4 h-12 w-full rounded-full" onClick={() => void dismiss(activeNotification.id)}>Entendi</Button>}
        </DialogContent>
      </Dialog>
      <Dialog open={showHistory} onOpenChange={setShowHistory}>
        <DialogContent className="max-h-[80vh] max-w-[calc(100%-2rem)] overflow-y-auto rounded-2xl">
          <DialogHeader><DialogTitle>Notificações</DialogTitle></DialogHeader>
          <div className="space-y-3">
            {notifications.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">Nenhuma notificação.</p>}
            {notifications.map((item) => <button type="button" key={item.id} onClick={() => { setShowHistory(false); setActiveNotification(item); }} className="w-full rounded-xl border border-border p-4 text-left"><div className="flex items-start justify-between gap-3"><b>{item.title}</b>{!userStates[item.id] && <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />}</div><p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{item.message}</p><p className="mt-2 text-xs text-muted-foreground">{new Date(item.created_at).toLocaleString("pt-BR")}</p></button>)}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
