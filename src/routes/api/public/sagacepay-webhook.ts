import { createFileRoute } from "@tanstack/react-router";
import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import type { Json } from "@/integrations/supabase/types";

const eventSchema = z.object({
  event: z.enum([
    "sale.pending",
    "sale.paid",
    "sale.failed",
    "sale.expired",
    "sale.refunded",
    "sale.status_changed",
    "sale.med_created",
    "sale.med_accepted",
    "sale.med_rejected",
    "sale.med_cancelled",
    "withdrawal.completed",
    "withdrawal.failed",
    "withdrawal.rejected",
  ]),
  data: z.record(z.unknown()),
});

const saleSchema = z.object({
  id: z.string().min(1),
  externalId: z.string().uuid(),
  amount: z.coerce.number().positive(),
  status: z.enum(["pending", "paid", "failed", "expired", "refunded"]),
  updatedAt: z.string().datetime({ offset: true }).optional(),
  paidAt: z.string().datetime({ offset: true }).optional(),
});

function signatureMatches(body: string, timestamp: string, supplied: string, secret: string) {
  if (!/^\d{10,13}$/.test(timestamp)) return false;
  const timestampSeconds = timestamp.length === 13 ? Number(timestamp) / 1000 : Number(timestamp);
  if (!Number.isFinite(timestampSeconds) || Math.abs(Date.now() / 1000 - timestampSeconds) > 300) return false;
  const normalized = supplied.trim().replace(/^sha256=/i, "").toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalized)) return false;
  const expected = createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");
  return timingSafeEqual(Buffer.from(normalized, "hex"), Buffer.from(expected, "hex"));
}

function normalizeStatus(status: string) {
  switch (status) {
    case "paid": return "CONFIRMED";
    case "failed": return "FAILED";
    case "expired": return "EXPIRED";
    case "refunded": return "REFUNDED";
    default: return "PENDING";
  }
}

export const Route = createFileRoute("/api/public/sagacepay-webhook")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const secret = process.env["SAGACEPAY_WEBHOOK_SECRET"];
        const timestamp = request.headers.get("x-sagacepay-timestamp") ?? "";
        const signature = request.headers.get("x-sagacepay-signature") ?? "";
        const body = await request.text();
        if (!secret || !signature || !timestamp || !signatureMatches(body, timestamp, signature, secret)) {
          return new Response("Unauthorized", { status: 401 });
        }

        let json: unknown;
        try { json = JSON.parse(body); } catch { return new Response("Invalid JSON", { status: 400 }); }
        const parsed = eventSchema.safeParse(json);
        if (!parsed.success) return new Response("Invalid payload", { status: 400 });

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data: eventRow, error: logError } = await supabaseAdmin
          .from("simpix_webhook_events")
          .insert({ event_type: parsed.data.event, payload: json as Json })
          .select("id")
          .single();
        if (logError || !eventRow) {
          console.error("SagacePay event log failed", logError?.message);
          return new Response("Event log failed", { status: 500 });
        }

        try {
          if (parsed.data.event.startsWith("sale.")) {
            const sale = saleSchema.parse(parsed.data.data);
            const status = normalizeStatus(sale.status);
            const updatedAt = sale.paidAt ?? sale.updatedAt ?? new Date().toISOString();
            const result = status === "CONFIRMED"
              ? await supabaseAdmin.rpc("confirm_pix_charge", { _external_ref: sale.externalId, _magic_id: sale.id, _amount: sale.amount, _provider_updated_at: updatedAt })
              : await supabaseAdmin.rpc("update_pix_charge_status", { _external_ref: sale.externalId, _magic_id: sale.id, _status: status, _provider_updated_at: updatedAt });
            if (result.error) throw result.error;
          }
          const { error: processedError } = await supabaseAdmin
            .from("simpix_webhook_events")
            .update({ processed: true, processed_at: new Date().toISOString(), error_message: null })
            .eq("id", eventRow.id);
          if (processedError) throw processedError;
        } catch (error) {
          const message = error instanceof Error ? error.message : "Unknown processing error";
          await supabaseAdmin.from("simpix_webhook_events").update({ error_message: message.slice(0, 500) }).eq("id", eventRow.id);
          console.error("SagacePay webhook processing failed", message);
          return new Response("Processing failed", { status: 422 });
        }

        return Response.json({ received: true, processed: true });
      },
    },
  },
});