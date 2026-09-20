# PIX real para créditos do jogo

## Objetivo
Adicionar recarga PIX real pela SimPix sem alterar a identidade visual do app. O pagamento comprará **créditos do jogo não sacáveis**. Pagamentos aos jogadores usarão uma carteira separada de **prêmios sacáveis**, financiada e ajustada pela empresa.

## Fluxo do jogador
1. Em **Recarga PIX**, informar valor, nome completo e CPF.
2. Validar os campos no celular e novamente no servidor.
3. Criar uma cobrança SimPix com validade de **5 minutos**.
4. Exibir o QR Code, o código PIX copia-e-cola, botão de copiar e cronômetro discreto.
5. Mostrar os estados: aguardando pagamento, pago, expirado ou falhou.
6. Quando a SimPix confirmar o pagamento, creditar automaticamente os créditos do jogo uma única vez e atualizar o saldo na tela.
7. Se o prazo terminar, bloquear aquele QR e permitir gerar uma nova cobrança.

## Separação segura dos saldos
- Manter dois valores visivelmente distintos:
  - **Créditos do jogo:** comprados por PIX e usados para veículos e ações dentro do jogo; nunca podem ser sacados.
  - **Prêmios disponíveis:** valores concedidos pela empresa segundo regras do jogo; somente estes podem gerar solicitação de saque.
- A compra de veículos consumirá apenas créditos do jogo.
- O pedido de saque validará apenas o saldo de prêmios, nunca depósitos PIX.
- Ajustes administrativos indicarão explicitamente qual carteira foi alterada e guardarão motivo e auditoria.
- Preservar a aparência atual, mas substituir textos como “demonstrativo” e reformular “lucro/rendimento” como progresso, produção ou recompensa virtual, sem sugerir retorno do dinheiro depositado.
- Atualizar Política de Privacidade e Sobre Nós para explicar uso do CPF no pagamento, natureza dos créditos e regra dos prêmios.

## Integração SimPix
- Criar a cobrança no servidor com `POST /api/transactions`, `payment_method: Pix`, `expires_in: 300`, referência interna única e chave de idempotência.
- Nunca enviar `x-api-key` ou `x-token` ao navegador.
- Criar um endpoint público de webhook para eventos de transação.
- Validar `x-webhook-signature` com HMAC SHA-256 e comparação segura antes de qualquer alteração.
- Conferir referência, identificador SimPix, valor e status `CONFIRMED` antes de creditar.
- Tornar o crédito idempotente: notificações repetidas não poderão duplicar saldo.
- Tratar `PENDING`, `CONFIRMED`, `FAILED`, `EXPIRED`, `REFUNDED` e disputas. Estornos ou disputas serão sinalizados no painel para revisão, sem débito automático que gere saldo negativo.
- Usar consulta de status autenticada como apoio durante os cinco minutos, mantendo o webhook como confirmação principal.

## Banco de dados e segurança
- Adicionar carteira de prêmios separada ao perfil, sem reutilizar créditos do jogo para saques.
- Criar registros próprios de cobranças PIX com usuário, valor, referência, identificador SimPix, status, validade, horários e garantia de unicidade.
- Guardar somente os dados necessários: nome e CPF mascarado/últimos dígitos; o CPF completo será validado e enviado à SimPix sem ser persistido no app.
- Aplicar permissões por usuário, acesso administrativo e acesso privilegiado somente no webhook validado.
- Atualizar o livro-caixa para distinguir recarga PIX, gasto de créditos, prêmio, ajuste e saque.
- Atualizar o resumo administrativo para refletir separadamente créditos comprados, prêmios, PIX pendentes/pagos/expirados e solicitações de saque.

## Painel administrativo
- Na página `/admin`, mostrar novas recargas em tempo quase real, com nome, usuário, valor, status, horário e identificador da cobrança.
- Destacar pagamentos confirmados e atualizar os indicadores sem recarregar a página.
- Remover a aprovação manual de recargas pagas; apenas a confirmação válida da SimPix creditará o saldo.
- Manter a revisão manual de saques de prêmios e impedir aprovação acima da carteira de prêmios.

## Credenciais e ativação
- Não reutilizar as chaves expostas nas imagens.
- Após criar o endpoint do webhook, solicitar as novas `x-api-key` e `x-token` pelo formulário seguro.
- Registrar o webhook de transações na SimPix e guardar o segredo retornado no cofre do projeto.
- A SimPix não oferece ambiente de teste: nenhuma cobrança real será criada automaticamente durante o desenvolvimento. A validação final será feita com uma cobrança de baixo valor iniciada conscientemente pelo usuário.

## Validação
- Testar validação de nome, CPF, valor e autenticação.
- Testar geração e expiração do QR em 5 minutos, copiar código e retomada de cobrança pendente.
- Testar assinatura inválida, valor divergente, evento duplicado e pagamento confirmado.
- Confirmar que um PIX pago credita exatamente uma vez e aparece no app e no painel.
- Confirmar que créditos comprados não podem ser sacados e que somente prêmios permitem solicitação.
- Verificar o app no celular e o painel no computador, sem erros de interface.
