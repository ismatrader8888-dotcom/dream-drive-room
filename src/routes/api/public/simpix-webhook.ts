import { createFileRoute } from "@tanstack/react-router";
import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import type { Json } from "@/integrations/supabase/types";

const supportedEvents = ["TRANSACTION", "WITHDRAW", "DISPUTE"] as const;
const transactionStatuses = [
  "PENDING",
  "CONFIRMED",
  "FAILED",
  "EXPIRED",
  "REFUNDED",
  "DISPUTE_NEEDS_RESPONSE",
  "DISPUTE_IN_REVIEW",
  "DISPUTE_WON",
  "DISPUTE_LOST",
] as const;

const webhookSchema = z.object({
  event: z.string().trim().min(1).transform((value) => value.toUpperCase()).pipe(z.enum(supportedEvents)),
  data: z.record(z.unknown()),
});
const transactionSchema = z.object({
  magic_id: z.string().min(1),
  external_ref: z.string().uuid(),
  amount: z.coerce.number().positive(),
  status: z.string().transform((value) => value.toUpperCase()).pipe(z.enum(transactionStatuses)),
  updated_at: z.string().datetime({ offset: true }).optional(),
});

function signatureMatches(body: string, supplied: string, secret: string) {
  const normalized = supplied.trim().replace(/^sha256=/i, "").toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalized)) return false;
  const expected = createHmac("sha256", secret).update(body).digest("hex");
  const suppliedBuffer = Buffer.from(normalized, "hex");
  const expectedBuffer = Buffer.from(expected, "hex");
  return suppliedBuffer.length === expectedBuffer.length && timingSafeEqual(suppliedBuffer, expectedBuffer);
}

export const Route = createFileRoute("/api/public/simpix-webhook")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const secret = process.env["SIMPIX_WEBHOOK_SECRET"];
        const signature = request.headers.get("x-webhook-signature") ?? "";
        const body = await request.text();
        if (!secret || !signature) return new Response("Unauthorized", { status: 401 });
        if (!signatureMatches(body, signature, secret)) return new Response("Unauthorized", { status: 401 });
        let json: unknown;
        try { json = JSON.parse(body); } catch { return new Response("Invalid JSON", { status: 400 }); }
        const parsed = webhookSchema.safeParse(json);
        if (!parsed.success) return new Response("Invalid payload", { status: 400 });
        const eventType = parsed.data.event;
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
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
          const { error: processedError } = await supabaseAdmin.from("simpix_webhook_events").update({ processed: true, processed_at: new Date().toISOString(), error_message: null }).eq("id", eventRow.id);
          if (processedError) throw processedError;
        } catch (error) {
          const message = error instanceof Error ? error.message : "Unknown processing error";
          const { error: updateError } = await supabaseAdmin.from("simpix_webhook_events").update({ error_message: message.slice(0, 500) }).eq("id", eventRow.id);
          if (updateError) console.error("SimPix event error log failed", updateError.message);
          console.error("SimPix webhook processing failed", message);
          return new Response("Processing failed", { status: 422 });
        }
        return Response.json({ received: true, processed: true });
      },
    },
  },
});