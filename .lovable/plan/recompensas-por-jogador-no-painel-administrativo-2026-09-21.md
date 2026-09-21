# Recompensas por jogador no painel administrativo

## Objetivo
Mostrar, no cartão de cada jogador, o valor das recompensas de veículos geradas hoje e o total acumulado.

## Implementação
- Atualizar o resumo administrativo para calcular por jogador as recompensas do dia atual e todas as recompensas já geradas.
- Exibir os dois valores no cartão de cada usuário com os rótulos **Recompensas de hoje** e **Recompensas totais**.
- Manter os demais saldos, métricas e funções do painel sem alteração.
- Validar o painel e os tipos após a mudança.

## Detalhes técnicos
- O cálculo diário usará a data do servidor e o horário de geração registrado em cada ciclo.
- A consulta continuará protegida para administradores.
