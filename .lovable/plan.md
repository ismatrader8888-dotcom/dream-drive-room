# Creditar ciclos em Prêmios disponíveis

## Objetivo
Fazer com que cada ciclo concluído de veículo ou central de recarga aumente diretamente o saldo de **Prêmios disponíveis**, mantendo o histórico e impedindo créditos duplicados.

## Alterações
- Atualizar o processamento seguro dos ciclos para somar o rendimento em `reward_balance`, em vez de Créditos.
- Manter um evento único por veículo e número do ciclo, o progresso do contrato e os totais de recompensas.
- Ajustar os textos das telas para identificar o rendimento como creditado em **Prêmios disponíveis**.
- Preservar compras, depósitos, roleta, códigos resgatáveis, indicações e contratos já concluídos sem recalcular pagamentos passados.

## Verificação
- Confirmar que um ciclo novo aumenta Prêmios disponíveis uma única vez.
- Confirmar que Créditos não aumentam com o ciclo.
- Conferir recompensas, progresso e histórico no celular e no painel administrativo.
