import { createFileRoute } from "@tanstack/react-router";
import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import type { Json } from "@/integrations/supabase/types";

const webhookSchema = z.object({ event: z.string().min(1), data: z.record(z.unknown()) });
const transactionSchema = z.object({
  magic_id: z.string().min(1),
  external_ref: z.string().uuid(),
  amount: z.coerce.number().positive(),
  status: z.string(),
  updated_at: z.string().optional(),
});

export const Route = createFileRoute("/api/public/simpix-webhook")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const secret = process.env["SIMPIX_WEBHOOK_SECRET"];
        const signature = request.headers.get("x-webhook-signature") ?? "";
        const body = await request.text();
        if (!secret || !signature) return new Response("Unauthorized", { status: 401 });
        const expected = createHmac("sha256", secret).update(body).digest("hex");
        const suppliedBuffer = Buffer.from(signature, "utf8");
        const expectedBuffer = Buffer.from(expected, "utf8");
        if (suppliedBuffer.length !== expectedBuffer.length || !timingSafeEqual(suppliedBuffer, expectedBuffer)) return new Response("Unauthorized", { status: 401 });
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        let json: unknown;
        try { json = JSON.parse(body); } catch { return new Response("Invalid JSON", { status: 400 }); }
        const parsed = webhookSchema.safeParse(json);
        if (!parsed.success) return new Response("Invalid payload", { status: 400 });
        const eventType = parsed.data.event.toUpperCase();
        if (!["TRANSACTION", "WITHDRAW", "DISPUTE"].includes(eventType)) return new Response("Unsupported event", { status: 400 });
        const { data: eventRow, error: logError } = await supabaseAdmin.from("simpix_webhook_events").insert({ event_type: eventType.toLowerCase(), payload: json as Json }).select("id").single();
        if (logError || !eventRow) { console.error("SimPix event log failed", logError?.message); return new Response("Event log failed", { status: 500 }); }
        try {
          if (eventType === "TRANSACTION") {
            const transaction = transactionSchema.parse(parsed.data.data);
            const updatedAt = transaction.updated_at ?? new Date().toISOString();
            const result = transaction.status === "CONFIRMED"
              ? await supabaseAdmin.rpc("confirm_pix_charge", { _external_ref: transaction.external_ref, _magic_id: transaction.magic_id, _amount: transaction.amount, _provider_updated_at: updatedAt })
              : await supabaseAdmin.rpc("update_pix_charge_status", { _external_ref: transaction.external_ref, _magic_id: transaction.magic_id, _status: transaction.status, _provider_updated_at: updatedAt });
            if (result.error) throw result.error;
          }
          await supabaseAdmin.from("simpix_webhook_events").update({ processed: true, processed_at: new Date().toISOString() }).eq("id", eventRow.id);
        } catch (error) {
          const message = error instanceof Error ? error.message : "Unknown processing error";
          await supabaseAdmin.from("simpix_webhook_events").update({ error_message: message.slice(0, 500) }).eq("id", eventRow.id);
          console.error("SimPix webhook processing failed", message);
          return new Response("Processing failed", { status: 422 });
        }
        return Response.json({ received: true });
      },
    },
  },
});