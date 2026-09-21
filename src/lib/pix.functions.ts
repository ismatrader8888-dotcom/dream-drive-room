import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const chargeSchema = z.object({
  amount: z.number().min(1).max(5000),
  name: z.string().trim().min(5).max(120),
  document: z.string().transform((value) => value.replace(/\D/g, "")).refine((value) => value.length === 11, "CPF inválido"),
});

type ProviderContent = {
  id?: string;
  externalId?: string;
  amount?: number;
  pixCode?: string;
  pixQrCode?: string;
  status?: string;
  updatedAt?: string;
};

const SAGACEPAY_API_URL = "https://sagacepay.com/api";
const SAGACEPAY_WEBHOOK_URL = "https://drivingyoudreamsss.online/api/public/sagacepay-webhook";

function normalizeProviderStatus(status?: string) {
  switch (status?.toLowerCase()) {
    case "paid": return "CONFIRMED";
    case "failed": return "FAILED";
    case "expired": return "EXPIRED";
    case "refunded": return "REFUNDED";
    default: return "PENDING";
  }
}

const syncSchema = z.object({ chargeId: z.string().uuid() });

export const createPixCharge = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: { amount: number; name: string; document: string }) => chargeSchema.parse(input))
  .handler(async ({ data, context }) => {
    const apiKey = process.env["SAGACEPAY_API_KEY"];
    if (!apiKey) return { ok: false as const, error: "PIX_SETUP_REQUIRED" };

    const { data: profile } = await context.supabase
      .from("profiles")
      .select("email, phone")
      .eq("id", context.userId)
      .single();
    const externalRef = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 300_000).toISOString();
    const { data: charge, error: insertError } = await context.supabase.from("pix_charges").insert({
      user_id: context.userId,
      external_ref: externalRef,
      amount: data.amount,
      payer_name: data.name,
      document_suffix: data.document.slice(-4),
      status: "CREATING",
      expires_at: expiresAt,
    }).select("id").single();
    if (insertError || !charge) throw new Error("Não foi possível iniciar a cobrança.");

    const response = await fetch(`${SAGACEPAY_API_URL}/sales`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "idempotency-key": charge.id,
      },
      body: JSON.stringify({
        amount: data.amount,
        externalId: externalRef,
        customer: {
          name: data.name,
          email: profile?.email ?? `jogador-${context.userId.slice(0, 8)}@byddriving.app`,
          phone: (profile?.phone ?? "11999999999").replace(/\D/g, ""),
          document: data.document,
        },
        expirationInSeconds: 300,
        postbackUrl: SAGACEPAY_WEBHOOK_URL,
        description: "Créditos BYD Driving",
      }),
    });
    const content = await response.json().catch(() => ({})) as ProviderContent & { message?: string };
    if (!response.ok || !content.id || !content.pixCode) {
      await context.supabase.from("pix_charges").update({ status: "FAILED", updated_at: new Date().toISOString() }).eq("id", charge.id);
      console.error("SagacePay charge creation failed", response.status, content.message ?? "unknown");
      return { ok: false as const, error: "PROVIDER_ERROR" };
    }
    const { error: updateError } = await context.supabase.from("pix_charges").update({
      provider_magic_id: content.id,
      qr_code: content.pixCode,
      status: "PENDING",
      updated_at: new Date().toISOString(),
    }).eq("id", charge.id);
    if (updateError) throw new Error("Não foi possível salvar a cobrança.");
    return { ok: true as const, chargeId: charge.id, qrCode: content.pixCode, expiresAt };
  });

export const syncPixCharge = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: { chargeId: string }) => syncSchema.parse(input))
  .handler(async ({ data, context }) => {
    const apiKey = process.env["SAGACEPAY_API_KEY"];
    if (!apiKey) return { status: "PENDING" };
    const { data: charge } = await context.supabase
      .from("pix_charges")
      .select("external_ref, provider_magic_id, amount, status")
      .eq("id", data.chargeId)
      .eq("user_id", context.userId)
      .maybeSingle();
    if (!charge || charge.status === "CONFIRMED" || !charge.provider_magic_id) return { status: charge?.status ?? "PENDING" };
    const response = await fetch(`${SAGACEPAY_API_URL}/sales/${encodeURIComponent(charge.provider_magic_id)}`, {
      headers: { "x-api-key": apiKey },
    });
    if (!response.ok) return { status: charge.status };
    const transaction = await response.json().catch(() => ({})) as ProviderContent;
    if (!transaction?.status) return { status: charge.status };
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const updatedAt = transaction.updatedAt ?? new Date().toISOString();
    const normalizedStatus = normalizeProviderStatus(transaction.status);
    const result = normalizedStatus === "CONFIRMED"
      ? await supabaseAdmin.rpc("confirm_pix_charge", { _external_ref: charge.external_ref, _magic_id: charge.provider_magic_id, _amount: Number(charge.amount), _provider_updated_at: updatedAt })
      : await supabaseAdmin.rpc("update_pix_charge_status", { _external_ref: charge.external_ref, _magic_id: charge.provider_magic_id, _status: normalizedStatus, _provider_updated_at: updatedAt });
    if (result.error) throw new Error(result.error.message);
    return { status: normalizedStatus };
  });