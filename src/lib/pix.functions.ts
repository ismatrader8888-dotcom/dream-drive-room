import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const chargeSchema = z.object({
  amount: z.number().min(1).max(5000),
  name: z.string().trim().min(5).max(120),
  document: z.string().transform((value) => value.replace(/\D/g, "")).refine((value) => value.length === 11, "CPF inválido"),
});

type ProviderContent = {
  magic_id?: string;
  qr_code?: string;
  status?: string;
};

export const createPixCharge = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: { amount: number; name: string; document: string }) => chargeSchema.parse(input))
  .handler(async ({ data, context }) => {
    const apiKey = process.env["SIMPIX_API_KEY"];
    const token = process.env["SIMPIX_TOKEN"];
    if (!apiKey || !token) return { ok: false as const, error: "PIX_SETUP_REQUIRED" };

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

    const response = await fetch("https://api.simpixpagamentos.com/api/transactions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "x-token": token,
        "idempotency-key": charge.id,
        "x-timezone": "America/Sao_Paulo",
      },
      body: JSON.stringify({
        amount: data.amount,
        external_ref: externalRef,
        requester: {
          name: data.name,
          email: profile?.email ?? `jogador-${context.userId.slice(0, 8)}@byddriving.app`,
          phone: (profile?.phone ?? "11999999999").replace(/\D/g, ""),
          document: data.document,
        },
        payment_method: "Pix",
        expires_in: 300,
        description: "Créditos BYD Driving",
      }),
    });
    const raw = await response.json().catch(() => ({})) as { content?: ProviderContent; message?: string } & ProviderContent;
    const content = raw.content ?? raw;
    if (!response.ok || !content.magic_id || !content.qr_code) {
      await context.supabase.from("pix_charges").update({ status: "FAILED", updated_at: new Date().toISOString() }).eq("id", charge.id);
      console.error("SimPix charge creation failed", response.status, raw.message ?? "unknown");
      return { ok: false as const, error: "PROVIDER_ERROR" };
    }
    const { error: updateError } = await context.supabase.from("pix_charges").update({
      provider_magic_id: content.magic_id,
      qr_code: content.qr_code,
      status: "PENDING",
      updated_at: new Date().toISOString(),
    }).eq("id", charge.id);
    if (updateError) throw new Error("Não foi possível salvar a cobrança.");
    return { ok: true as const, chargeId: charge.id, qrCode: content.qr_code, expiresAt };
  });