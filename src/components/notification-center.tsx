import { useEffect, useState } from "react";
import { Bell, X, Info, AlertTriangle, CheckCircle, AlertCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type Notification = {
  id: string;
  title: string;
  content: string;
  type: "info" | "warning" | "success" | "error";
  created_at: string;
};

type UserState = {
  notification_id: string;
  dismissed_at: string | null;
};

export function NotificationCenter({ userId }: { userId: string }) {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [userStates, setUserStates] = useState<Record<string, UserState>>({});
  const [activeNotification, setActiveNotification] = useState<Notification | null>(null);

  const load = async () => {
    const { data: notifs } = await supabase
      .from("global_notifications" as any)
      .select("*")
      .eq("active", true)
      .order("created_at", { ascending: false });

    const { data: states } = await supabase
      .from("user_notification_states" as any)
      .select("notification_id, dismissed_at")
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

  const undismissed = notifications.filter(n => !userStates[n.id]?.dismissed_at);

  useEffect(() => {
    if (undismissed.length > 0 && !activeNotification) {
      setActiveNotification(undismissed[0]);
    }
  }, [undismissed, activeNotification]);

  const dismiss = async (id: string) => {
    const { error } = await supabase
      .from("user_notification_states" as any)
      .upsert({
        user_id: userId,
        notification_id: id,
        dismissed_at: new Date().toISOString()
      }, { onConflict: "user_id,notification_id" });

    if (!error) {
      setUserStates(prev => ({
        ...prev,
        [id]: { notification_id: id, dismissed_at: new Date().toISOString() }
      }));
      setActiveNotification(null);
    }
  };

  const getIcon = (type: string) => {
    switch (type) {
      case "warning": return <AlertTriangle className="h-6 w-6 text-warning" />;
      case "success": return <CheckCircle className="h-6 w-6 text-success" />;
      case "error": return <AlertCircle className="h-6 w-6 text-destructive" />;
      default: return <Info className="h-6 w-6 text-primary" />;
    }
  };

  if (!activeNotification) return null;

  return (
    <Dialog open={!!activeNotification} onOpenChange={(open) => { if (!open) setActiveNotification(null); }}>
      <DialogContent className="max-w-[calc(100%-2rem)] rounded-2xl">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-muted">
            {getIcon(activeNotification.type)}
          </div>
          <DialogHeader className="text-left">
            <DialogTitle className="text-xl">{activeNotification.title}</DialogTitle>
          </DialogHeader>
        </div>
        <div className="mt-2 text-muted-foreground whitespace-pre-wrap">
          {activeNotification.content}
        </div>
        <div className="mt-4 flex flex-col gap-2">
          <Button className="h-12 w-full rounded-full" onClick={() => void dismiss(activeNotification.id)}>
            Entendi
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
