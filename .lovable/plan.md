# Saldo seguro e painel administrativo

## Objetivo
Impedir compras sem saldo, criar recargas PIX reais e entregar um painel administrativo seguro para a conta proprietária.

## Experiência do usuário
- Ao tentar alugar sem saldo, mostrar um aviso com o valor necessário e levar à recarga PIX.
- Após pagamento confirmado, atualizar o saldo exibido na conta.
- Permitir várias compras do mesmo veículo, sempre debitando o saldo de forma atômica.
- Registrar solicitações de saque e mostrar seus estados.

## Painel administrativo
- Restringir o acesso à conta `maloneadm@adm.com` por papel de administrador validado no servidor.
- Exibir resumo de usuários, saldo total, compras e saques pendentes.
- Listar usuários com saldo e quantidade de indicados.
- Permitir ajuste manual de saldo com motivo e histórico de auditoria.
- Listar compras, ranking dos veículos mais comprados e solicitações de saque.
- Aprovar ou rejeitar saques com proteção contra saldo negativo.

## Dados e segurança
- Criar livro-caixa, pedidos de recarga e solicitações de saque com políticas de acesso.
- Criar operações transacionais para compra, ajuste de saldo e revisão de saque.
- Remover a possibilidade de inserir veículos diretamente sem débito.
- Vincular indicações pelo código informado no cadastro.
- Integrar o provedor de pagamento recomendado para PIX; a confirmação do pagamento será a única forma automática de crédito.

## Validação
- Testar usuário sem saldo, recarga, compra repetida, saldo atualizado e gravação do veículo.
- Testar acesso negado para usuário comum e funções administrativas com a conta proprietária.
- Validar painel em celular e desktop, sem erros de interface.
