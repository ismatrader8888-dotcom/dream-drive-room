# Substituir a SimPix pela SagacePay

## Objetivo
Migrar totalmente os novos depósitos PIX para a SagacePay, preservando o histórico, os saldos, os bônus de indicação e a proteção contra créditos duplicados.

## Alterações
- Trocar a criação de cobrança para `POST https://sagacepay.com/api/sales`, usando `x-api-key`, a mesma chave de idempotência interna e validade de 5 minutos.
- Adaptar os campos enviados: `customer`, `externalId`, `expirationInSeconds` e `postbackUrl`.
- Salvar o `id` da venda no campo existente `provider_magic_id` e o `pixCode` no campo existente `qr_code`, sem recriar tabelas nem apagar cobranças antigas.
- Trocar a consulta de status para `GET /sales/:id` e converter `paid` para `CONFIRMED`, mantendo os demais estados compatíveis.
- Criar o endpoint público `/api/public/sagacepay-webhook`, validando `x-sagacepay-timestamp` e `x-sagacepay-signature` sobre `timestamp.body`, com limite de cinco minutos contra reenvio indevido.
- Registrar os eventos na estrutura de auditoria existente e reutilizar as operações atômicas atuais para atualizar `pix_charges`, `balance_transactions`, créditos do jogo e bônus de indicação uma única vez.
- Remover a SimPix do fluxo ativo e atualizar mensagens visíveis que mencionam o provedor, sem remover o histórico antigo.

## Credenciais e ativação
- Solicitar com segurança `SAGACEPAY_API_KEY` e `SAGACEPAY_WEBHOOK_SECRET` somente após o código e a URL do webhook estarem prontos.
- Configurar na SagacePay: `https://drivingyoudreamsss.online/api/public/sagacepay-webhook`.
- Manter as credenciais exclusivamente no backend do Lovable Cloud.

## Validação
- Confirmar que criar uma recarga retorna PIX copia-e-cola e cronômetro de 5 minutos.
- Confirmar que consulta de status e webhook `sale.paid` creditam uma única vez, inclusive após reenvio do mesmo evento.
- Confirmar tratamento de `pending`, `failed`, `expired` e `refunded`.
- Confirmar rejeição de assinatura inválida e timestamp vencido.
- Fazer uma cobrança real de baixo valor, pois a documentação pública não informa ambiente de testes.
