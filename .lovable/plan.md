# Acesso seguro de suporte às contas

## Objetivo
Permitir que o administrador abra uma visão de suporte de cada usuário para conferir saldos, veículos, recompensas, depósitos, saques e indicações, sem revelar ou substituir a senha da pessoa.

## Experiência no painel
- Adicionar **Entrar como usuário** ao cartão de cada usuário.
- Abrir uma tela de suporte identificada com o usuário selecionado e um aviso permanente de que o administrador está em modo de suporte.
- Mostrar os mesmos dados principais da conta: créditos, prêmios, veículos e progresso, cobranças, saques e indicações.
- Disponibilizar **Sair do modo de suporte** para retornar ao painel administrativo.
- Manter ajustes de saldo e revisões administrativas somente nos controles já autorizados do painel.

## Segurança e auditoria
- Validar no servidor que quem abriu a conta possui papel de administrador.
- Buscar os dados do usuário no servidor; não trocar a sessão do administrador nem criar uma sessão em nome do usuário.
- Registrar início e encerramento do acesso, administrador, usuário consultado e horário.
- Não armazenar, recuperar ou exibir senhas; elas permanecem protegidas pelo serviço de autenticação.
- Não permitir que um identificador enviado pelo navegador contorne a validação de administrador.

## Detalhes técnicos
- Criar uma tabela de auditoria com acesso restrito e uma função administrativa para montar a visão de suporte.
- Expor a leitura por uma função de servidor autenticada, com verificação de papel antes de qualquer acesso privilegiado.
- Integrar a visão ao painel existente sem alterar o login normal dos usuários.
- Validar o acesso permitido para administrador e negado para usuário comum, além da apresentação em computador.
