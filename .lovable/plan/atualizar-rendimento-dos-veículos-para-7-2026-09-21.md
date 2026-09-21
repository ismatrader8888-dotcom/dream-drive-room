# Atualizar rendimento dos veículos para 7%

## Objetivo
Reduzir a recompensa de cada ciclo de 24 horas de 9% para 7%, recalcular o retorno dos 25 ciclos e adicionar uma nova opção BYD Dolphin Mini de R$ 90 em New York.

## Alterações
- Atualizar o catálogo exibido no app para usar 7% do preço por ciclo e 175% do preço ao final dos 25 ciclos.
- Adicionar o novo **BYD Dolphin Mini — New York** por **R$ 90,00**, com **R$ 6,30 por ciclo** e **R$ 157,50 em 25 ciclos**.
- Atualizar os registros do catálogo no banco, preservando IDs, compras e histórico existentes.
- Aplicar a taxa de 7% aos contratos já adquiridos: ajustar a recompensa dos próximos ciclos, além dos textos de valor diário e retorno exibidos nesses veículos.
- Manter recompensas de ciclos já concluídos sem alteração retroativa.
- Garantir que novas compras e renovações copiem os novos valores de 7% corretamente.

## Valores recalculados
| Preço | Por ciclo (7%) | Retorno em 25 ciclos |
|---:|---:|---:|
| R$ 90,00 | R$ 6,30 | R$ 157,50 |
| R$ 212,50 | R$ 14,88 | R$ 371,88 |
| R$ 250,00 | R$ 17,50 | R$ 437,50 |
| R$ 287,50 | R$ 20,13 | R$ 503,13 |
| R$ 425,00 | R$ 29,75 | R$ 743,75 |
| R$ 500,00 | R$ 35,00 | R$ 875,00 |
| R$ 800,00 | R$ 56,00 | R$ 1.400,00 |
| R$ 920,00 | R$ 64,40 | R$ 1.610,00 |
| R$ 1.150,00 | R$ 80,50 | R$ 2.012,50 |
| R$ 1.500,00 | R$ 105,00 | R$ 2.625,00 |

## Detalhes técnicos
- Atualizar `vehicle_catalog.daily_amount` e `vehicle_catalog.return_amount` com arredondamento monetário de duas casas.
- Atualizar `user_vehicles.reward_per_cycle`, `daily` e `return_value` somente para os ciclos futuros dos contratos existentes; `vehicle_reward_events` anteriores permanecem intactos.
- Inserir o novo veículo com um identificador próprio, sem substituir o Dolphin Mini atual de R$ 250.
- Sincronizar os mesmos valores na lista visual do app e validar filtros, compra, renovação e exibição dos veículos adquiridos.
