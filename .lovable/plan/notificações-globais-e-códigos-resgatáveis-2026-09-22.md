# Notificações globais e códigos resgatáveis

## Objetivo
Permitir que o administrador publique avisos para todas as contas e crie códigos promocionais que adicionam Créditos quando resgatados em Intercâmbio.

## O que será criado

### Notificações
- Nova área **Notificações** no painel administrativo para escrever título e mensagem e publicar para todas as contas.
- Cada aviso novo abre como popup para cada usuário; o usuário pode fechar e continuar usando o aplicativo.
- O sininho do perfil mostrará a quantidade de avisos não lidos e abrirá uma lista com o histórico.
- Abrir ou fechar o aviso registra a leitura somente para aquela conta, sem remover o aviso dos demais usuários.
- Avisos publicados também alcançarão contas criadas futuramente enquanto permanecerem ativos.

### Códigos resgatáveis
- Nova área **Códigos** no painel administrativo para definir o código e o valor em Créditos.
- Lista administrativa com código, valor, situação e quantidade de resgates; será possível ativar ou desativar um código.
- A tela **Intercâmbio** validará o código no banco e mostrará confirmação ou erro.
- Cada conta poderá usar cada código somente uma vez.
- O crédito, o registro do resgate e o histórico de saldo serão gravados juntos, evitando crédito duplicado mesmo com cliques repetidos.

## Segurança e dados
- Criar tabelas protegidas para avisos, leituras individuais, códigos e resgates.
- Somente administradores poderão publicar avisos e criar/alterar códigos.
- Usuários autenticados verão avisos ativos e somente seus próprios estados de leitura e resgates.
- O valor do código será validado no banco; o navegador nunca poderá escolher ou alterar o valor creditado.
- O histórico de Créditos receberá uma movimentação identificada como resgate de código.

## Integração nas telas
- Substituir os números fixos do sininho por dados reais.
- Adicionar popup global e painel de notificações no perfil.
- Conectar o formulário já existente de Intercâmbio ao resgate real e atualizar o saldo imediatamente.
- Adicionar as duas novas abas no painel administrativo sem alterar compras, PIX, saques, veículos ou indicações.

## Verificação
- Validar criação e publicação de aviso pelo administrador.
- Confirmar popup, fechamento, contador e histórico no sininho em uma conta de usuário.
- Confirmar resgate válido, saldo atualizado, histórico criado, bloqueio de segundo resgate e código desativado/inválido.
- Conferir o painel administrativo em computador e as telas do usuário em celular.
