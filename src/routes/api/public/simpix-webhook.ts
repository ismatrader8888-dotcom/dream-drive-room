import { createFileRoute } from "@tanstack/react-router";
import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";

const webhookSchema = z.object({
  event: z.string(),
  data: z.object({
    magic_id: z.string().min(1),
    external_ref: z.string().uuid(),
    amount: z.coerce.number().positive(),
    status: z.string(),
    updated_at: z.string().optional(),
  }),
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
        const parsed = webhookSchema.safeParse(JSON.parse(body));
        if (!parsed.success || parsed.data.event.toUpperCase() !== "TRANSACTION") return new Response("Invalid payload", { status: 400 });
        const event = parsed.data.data;
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const updatedAt = event.updated_at ?? new Date().toISOString();
        const result = event.status === "CONFIRMED"
          ? await supabaseAdmin.rpc("confirm_pix_charge", { _external_ref: event.external_ref, _magic_id: event.magic_id, _amount: event.amount, _provider_updated_at: updatedAt })
          : await supabaseAdmin.rpc("update_pix_charge_status", { _external_ref: event.external_ref, _magic_id: event.magic_id, _status: event.status, _provider_updated_at: updatedAt });
        if (result.error) { console.error("SimPix webhook processing failed", result.error.message); return new Response("Processing failed", { status: 422 }); }
        return Response.json({ received: true });
      },
    },
  },
});