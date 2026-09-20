# Indicações e bônus por depósitos confirmados

## Objetivo
Criar o programa de indicação da BYD Driving com vínculo único no cadastro, bônus automáticos em créditos do jogo e acompanhamento completo pelo jogador e pela administração.

## Regras do programa
- O código de convite poderá ser informado somente ao criar a conta e não poderá ser alterado depois.
- Se o código informado não existir, o cadastro será bloqueado com uma mensagem clara; o usuário poderá corrigi-lo ou remover o código.
- Não será permitido usar o próprio código.
- Quando o primeiro depósito PIX válido do convidado for confirmado:
  - o convidado receberá uma única vez 5% do valor em créditos do jogo;
  - o dono do código receberá 15% do valor em créditos do jogo.
- Em cada depósito PIX confirmado seguinte, somente o dono do código receberá 15% em créditos do jogo.
- Reenvios do webhook ou novas consultas do mesmo pagamento nunca duplicarão créditos nem bônus.

## Banco de dados e segurança
- Criar registros próprios para vínculos de indicação e recompensas, com valor do depósito, percentual, crédito concedido, beneficiário, cobrança relacionada e data.
- Preservar os vínculos já capturados em `referred_by`, associando-os ao dono correto do código quando válidos.
- Atualizar a confirmação PIX em uma única transação: confirmar a cobrança, creditar o depósito, aplicar os bônus correspondentes e registrar tudo no livro-caixa.
- Manter os bônus exclusivamente em créditos do jogo, sem adicioná-los aos prêmios sacáveis.
- Impedir duplicidade com garantias no banco para cada cobrança e tipo de bônus.
- Expor aos jogadores somente os dados necessários da própria equipe; dados completos ficarão restritos à administração.

## Experiência do jogador
- Validar o código antes de enviar o cadastro e mostrar “Código de convite inválido” quando necessário.
- Preencher automaticamente o código quando o acesso vier por um link `?ind=CODIGO`.
- Na página **Minha Equipe**, listar todos os convidados:
  - **Inválido** enquanto ainda não houver depósito confirmado;
  - **Eficiente** após o primeiro depósito confirmado.
- Mostrar totais de membros, membros eficazes, depósitos confirmados e créditos recebidos por indicação.
- Na página **Recompensas por convite**, exibir o histórico dos bônus de 15% e, para o novo usuário, o bônus único de 5%.

## Painel administrativo
- Exibir indicadores de indicações totais, membros eficazes, volume confirmado indicado e créditos distribuídos.
- Em cada usuário, mostrar código, quem o convidou, quantidade total de convidados, quantidade eficaz e bônus acumulado.
- Criar uma área de indicações com convidador, convidado, situação, primeiro depósito, total depositado e bônus concedidos.
- Nas recargas, indicar quando houve bônus de 5% e/ou comissão de 15% e seus beneficiários.

## Validação
- Testar cadastro sem código, com código válido, inválido e próprio.
- Testar primeiro depósito, depósitos seguintes e webhook repetido.
- Confirmar os percentuais e arredondamento monetário em duas casas decimais.
- Confirmar que os bônus aparecem no saldo, na equipe, no histórico e no painel administrativo.
- Verificar as telas no celular e o painel no computador.
