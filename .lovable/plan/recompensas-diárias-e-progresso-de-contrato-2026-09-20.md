# Recompensas diárias e progresso de contrato

## Objetivo
Transformar o cronômetro e o progresso contratual em dados reais: cada veículo completa um ciclo a cada 24 horas, por até 25 ciclos, e gera a recompensa diária prevista no catálogo.

## O que será implementado
- Registrar no banco, para cada veículo comprado, o próximo pagamento, ciclos concluídos, recompensa acumulada e encerramento do contrato.
- Processar de forma segura todos os ciclos vencidos quando o usuário abrir ou atualizar o aplicativo, inclusive ciclos acumulados enquanto esteve ausente.
- Impedir pagamento duplicado com um registro único por veículo e número do ciclo.
- Manter cada recompensa concluída como “A transferir” até o usuário tocar em **Transferir**; a transferência soma o valor a **Prêmios disponíveis** e atualiza **Transferido**.
- Atualizar automaticamente o próximo cronômetro para mais 24 horas e encerrar a geração após o 25º ciclo do veículo.
- Exibir valores reais em **Recompensas de hoje**, **Recompensas totais**, **Progresso de contrato**, **Receita de Veículos** e históricos de recompensa.
- Atualizar os saldos e resumos ao retornar ao aplicativo e quando uma transferência for concluída.
- Tornar explícita no painel administrativo a alteração de **Créditos do jogo** ou **Prêmios disponíveis**, preservando motivo e histórico de cada ajuste.
- Incluir no painel os totais gerados, pendentes de transferência e transferidos por usuário.

## Regras de negócio
- Ciclo: 24 horas corridas a partir da compra.
- Duração: quantidade configurada no catálogo, atualmente 25 ciclos.
- Valor por ciclo: `daily_amount` do veículo no momento da compra.
- Ciclos atrasados: calculados de uma vez, respeitando o limite do contrato.
- Transferência: atômica; o mesmo valor nunca pode ser transferido duas vezes.
- Ajustes administrativos: somente administrador autenticado, sem permitir saldo negativo e sempre com motivo.

## Detalhes técnicos
- Migração aditiva para armazenar estado contratual e um livro de recompensas por ciclo, com permissões e políticas de acesso.
- Funções protegidas no banco para liquidar ciclos, transferir recompensas e entregar os resumos do usuário e administrador.
- O cálculo usa o relógio do servidor, não o aparelho do usuário.
- O cronômetro exibirá o `next_reward_at` persistido, evitando reinício incorreto após recarregar a página.
- Validação com verificação de tipos e testes no aplicativo móvel e no painel em computador.
