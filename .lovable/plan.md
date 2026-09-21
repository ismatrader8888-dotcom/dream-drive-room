# Atualizar credenciais SimPix do ambiente publicado

## Configuração confirmada
- Endpoint público: `https://drivingyoudreamsss.online/api/public/simpix-webhook`
- Eventos do webhook: `transaction`, `withdraw` e `dispute`
- O domínio está ativo, é o domínio principal e o projeto está publicado.

## Próximos passos
- Abrir o formulário seguro para substituir `SIMPIX_API_KEY`, `SIMPIX_TOKEN` e `SIMPIX_WEBHOOK_SECRET`.
- Manter as credenciais somente no ambiente protegido do backend, sem expô-las no site.
- Confirmar que os três nomes continuam cadastrados após a atualização.
- Testar o endpoint público sem assinatura e confirmar que ele rejeita a chamada, demonstrando que a validação está ativa.

## Dados esperados
- `SIMPIX_API_KEY`: chave iniciada por `pk_`
- `SIMPIX_TOKEN`: token iniciado por `sk_`
- `SIMPIX_WEBHOOK_SECRET`: segredo iniciado por `whsec_`
