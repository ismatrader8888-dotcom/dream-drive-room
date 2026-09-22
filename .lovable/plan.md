# Bônus de cadastro, Dolphin Mini ECO e roleta diária

## Objetivo
Adicionar um bônus imediato e único para novos usuários, ampliar o catálogo com um veículo de entrada, restringir saques por progresso real e criar uma roleta diária segura na Central de Tarefas.

## O que será implementado
- Creditar uma única vez R$ 15 em Créditos quando um novo cadastro for concluído.
- Exibir, no primeiro acesso após o cadastro, o pop-up: “🎉 Parabéns! Seu bônus foi liberado!”, informando que R$ 15 já foram creditados.
- Não conceder esse bônus retroativamente às contas existentes.
- Adicionar o **BYD Dolphin Mini ECO** em **New York** por **R$ 50**, seguindo a faixa de 7%: R$ 3,50 por ciclo de 24h e R$ 87,50 em 25 ciclos.
- Permitir solicitar saque de Prêmios disponíveis somente após o jogador acumular pelo menos R$ 30 em recompensas totais geradas por veículos.
- Mostrar claramente quanto falta para liberar o saque quando o requisito ainda não for atingido.
- Colocar uma roleta animada na aba **Tarefa pessoal** da Central de Tarefas.
- Exibir na roleta os prêmios de R$ 1, R$ 2, R$ 5, R$ 10, R$ 20 e R$ 50 em Créditos.
- Fazer o resultado real cair somente em R$ 1, R$ 2 ou R$ 5, decidido no servidor.
- Creditar o prêmio automaticamente em Créditos e liberar uma nova rodada 24 horas depois do último giro.
- Exibir cronômetro para a próxima rodada e preservar o estado ao fechar ou recarregar o aplicativo.

## Segurança e consistência
- O bônus, o giro e os créditos serão processados no banco, sem confiar no relógio ou no resultado calculado pelo aparelho.
- Cada conta receberá o bônus de cadastro no máximo uma vez.
- Cada giro terá registro próprio e proteção contra duplo crédito.
- A regra mínima de R$ 30 será validada no banco no momento do pedido de saque, não apenas na tela.
- A roleta não alterará Prêmios disponíveis; seus valores entram somente em Créditos.

## Validação
- Testar novo cadastro, pop-up único e saldo inicial de R$ 15.
- Confirmar que contas existentes não recebem o bônus.
- Testar compra do Dolphin Mini ECO e seus valores no catálogo.
- Testar saque bloqueado abaixo de R$ 30 de recompensas totais e permitido a partir de R$ 30, respeitando o saldo de Prêmios disponíveis.
- Testar animação, crédito único, recarga da página e bloqueio da roleta por 24 horas em celular.
- Verificar que não há erros de tela nem créditos duplicados.
