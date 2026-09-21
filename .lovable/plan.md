# Corrigir webhook PIX no Lovable Cloud

## Objetivo
Centralizar a confirmação do PIX no backend hospedado do Lovable Cloud, sem depender do VPS nem exigir que o proprietário forneça uma chave administrativa do banco.

## Implementação
- Manter e reforçar o endpoint público já existente para a SimPix em `/api/public/simpix-webhook`, que é o equivalente hospedado e compatível com este projeto.
- Validar `x-webhook-signature` com HMAC SHA-256 sobre o corpo original da requisição usando `SIMPIX_WEBHOOK_SECRET`, com comparação segura.
- Validar o formato dos eventos `transaction`, `withdraw` e `dispute`; somente uma transação `CONFIRMED` poderá creditar saldo.
- Registrar cada entrega válida em `simpix_webhook_events`, incluindo sucesso, horário de processamento ou erro.
- Para PIX confirmado, localizar a cobrança por `external_ref`, confirmar também `provider_magic_id` e `amount`, e executar a confirmação dentro da operação atômica existente no banco.
- Atualizar `pix_charges.status`, `pix_charges.credited_at` e datas do provedor; creditar `profiles.demo_balance`; registrar a entrada em `balance_transactions`.
- Preservar os bônus de indicação já vinculados à confirmação PIX.
- Manter a proteção contra duplicidade pelo bloqueio da cobrança e por `credited_at`: reenvios do mesmo PIX retornam sucesso sem creditar novamente.
- Não alterar nem recriar tabelas e não expor qualquer segredo no navegador.

## Acesso seguro
- O endpoint usará o acesso administrativo gerenciado internamente pelo Lovable Cloud; nenhuma chave administrativa será solicitada ou fornecida ao VPS.
- `SIMPIX_API_KEY` e `SIMPIX_TOKEN` continuarão usados apenas no backend para criar e consultar cobranças.
- `SIMPIX_WEBHOOK_SECRET` continuará usado apenas no backend para autenticar notificações.

## Validação
- Testar ausência de assinatura e assinatura inválida, esperando rejeição.
- Testar payload inválido e evento não suportado, esperando erro adequado.
- Testar `transaction`, `withdraw` e `dispute` assinados.
- Testar uma confirmação PIX e repetir exatamente o mesmo evento, comprovando uma única movimentação e um único crédito no saldo.
- Confirmar que o evento processado fica auditável e que o painel recebe o saldo atualizado.

## Entrega
- Informar o nome do endpoint, a URL pública completa disponível no projeto, as tabelas e campos reutilizados e um roteiro de teste com uma cobrança de baixo valor.
- A função ficará hospedada junto ao app no Lovable Cloud; não será criada uma nova função legada separada, pois este projeto usa endpoints públicos do backend atual.
