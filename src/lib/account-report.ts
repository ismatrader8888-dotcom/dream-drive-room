import fontUrl from "@/assets/report-dejavu.ttf?url";

type Report = Awaited<ReturnType<typeof import("@/lib/admin-support.functions").getAdminAccountReport>>;

const when = (value: string | null | undefined) => value
  ? new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", dateStyle: "short", timeStyle: "medium" }).format(new Date(value))
  : "Não registrado";
const money = (value: number | null | undefined) => Number(value ?? 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

export async function downloadAccountReport(data: Report) {
  const [{ jsPDF }, fontResponse] = await Promise.all([import("jspdf"), fetch(fontUrl)]);
  if (!fontResponse.ok) throw new Error("FONT_UNAVAILABLE");
  const bytes = new Uint8Array(await fontResponse.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  const doc = new jsPDF({ unit: "mm", format: "a4" });
  doc.addFileToVFS("DejaVuSans.ttf", btoa(binary));
  doc.addFont("DejaVuSans.ttf", "DejaVu", "normal");
  doc.setFont("DejaVu");
  const width = doc.internal.pageSize.getWidth();
  const height = doc.internal.pageSize.getHeight();
  let y = 18;
  let page = 1;
  const footer = () => {
    doc.setFontSize(8);
    doc.setTextColor(90, 100, 110);
    doc.text(`BYD Driving · Relatório confidencial · página ${page}`, 15, height - 10);
  };
  const newPage = () => { footer(); doc.addPage(); page++; y = 18; };
  const line = (text: string, size = 10, gap = 2) => {
    doc.setFontSize(size);
    const wrapped = doc.splitTextToSize(text, width - 30) as string[];
    for (const part of wrapped) {
      if (y + size * 0.48 + gap > height - 18) newPage();
      doc.text(part, 15, y);
      y += size * 0.48;
    }
    y += gap;
  };
  const section = (title: string, count: number) => {
    if (y > height - 35) newPage();
    y += 4;
    doc.setTextColor(0, 110, 140);
    line(`${title} (${count})`, 13, 3);
    doc.setTextColor(30, 40, 55);
    if (!count) line("Nenhum registro.");
  };

  doc.setTextColor(0, 110, 140);
  line("BYD Driving | Relatório individual", 17, 5);
  doc.setTextColor(30, 40, 55);
  line(`Conta: ${data.profile.email ?? data.profile.id}`);
  line(`Telefone: ${data.profile.phone ?? "Não informado"}  |  Código: ${data.profile.invite_code}`);
  line(`Cadastro: ${when(data.profile.created_at)}  |  Emissão: ${when(data.generatedAt)}`);
  line(`Créditos: ${money(data.profile.demo_balance)}  |  Prêmios disponíveis: ${money(data.profile.reward_balance)}`);
  line("Todos os horários: São Paulo (Brasil). Dados conforme registros da conta no momento da emissão.", 8);

  section("Veículos", data.vehicles.length);
  for (const v of data.vehicles) {
    line(`${v.name} · ${v.region} · ${v.plate} | Compra: ${when(v.purchased_at)}`);
    line(`Valor: ${money(v.purchase_price)} | ${v.cycles_completed}/${v.contract_cycles} ciclos | Rendimento/ciclo: ${money(v.reward_per_cycle)} | Próximo: ${when(v.next_reward_at)} | Conclusão: ${when(v.completed_at)}`, 9, 3);
  }
  section("Depósitos PIX", data.pixCharges.length);
  for (const c of data.pixCharges) {
    line(`${money(c.amount)} · ${c.status} · ${c.payer_name} | Criado: ${when(c.created_at)}`);
    line(`Confirmado: ${when(c.credited_at)} | Referência: ${c.provider_magic_id ?? c.id}`, 9, 3);
  }
  section("Saques", data.withdrawals.length);
  for (const w of data.withdrawals) {
    line(`${money(w.amount)} · ${w.status} · ${w.full_name} | Solicitado: ${when(w.created_at)}`);
    line(`Revisado: ${when(w.reviewed_at)} | Chave PIX: ${w.pix_key}`, 9, 3);
  }
  section("Movimentações", data.transactions.length);
  for (const t of data.transactions) {
    line(`${when(t.created_at)} | ${t.description} | ${money(t.amount)} | Saldo após: ${money(t.balance_after)}`, 9, 3);
  }

  const emails = new Map(data.invitedProfiles.map((p) => [p.id, p.email ?? p.id]));
  const deposits = new Map<string, typeof data.invitedDeposits>();
  for (const charge of data.invitedDeposits) {
    const list = deposits.get(charge.user_id) ?? [];
    list.push(charge);
    deposits.set(charge.user_id, list);
  }
  section("Pessoas convidadas", data.referrals.length);
  line(`Depositantes eficazes: ${data.referrals.filter((r) => r.effective_at).length} de ${data.referrals.length}`, 10, 3);
  for (const r of data.referrals) {
    line(`${emails.get(r.referred_user_id) ?? r.referred_user_id} · ${r.effective_at ? "Eficaz" : "Aguardando"} | Convite: ${when(r.created_at)}`);
    line(`Primeiro depósito eficaz: ${when(r.effective_at)} | ${r.total_confirmed_deposits} depósito(s) · ${money(r.total_deposited)} depositados · ${money(r.referrer_bonus_total)} em bônus`, 9);
    for (const charge of deposits.get(r.referred_user_id) ?? []) {
      line(`  Depósito confirmado: ${money(charge.amount)} | Criado: ${when(charge.created_at)} | Pago: ${when(charge.credited_at)} | ID: ${charge.id}`, 9);
    }
    y += 2;
  }
  const invitedDepositTotalCents = data.invitedDeposits.reduce((total, charge) => total + Math.round(Number(charge.amount) * 100), 0);
  if (y > height - 35) newPage();
  y += 4;
  doc.setTextColor(0, 110, 140);
  line(`Total de depósitos confirmados das pessoas convidadas: ${money(invitedDepositTotalCents / 100)}`, 12, 3);
  doc.setTextColor(30, 40, 55);
  footer();
  doc.save(`relatorio-usuario-${data.profile.id}.pdf`);
}