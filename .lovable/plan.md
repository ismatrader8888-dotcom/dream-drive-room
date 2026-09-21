# Próximo passo proposto: capturar a origem exata do HTTP 502

## Objetivo
Adicionar diagnóstico seguro à criação do PIX para que uma nova falha revele se o `502` veio da aplicação SimPix, do proxy dela ou da borda Cloudflare, sem registrar credenciais ou dados pessoais.

## Alterações propostas
- Manter método, URL, autenticação e corpo da cobrança inalterados.
- Em `src/lib/pix.functions.ts`, ler a resposta uma única vez como texto e interpretar JSON quando possível.
- Em respostas com erro, registrar somente: status, `content-type`, `server`, `via`, `cf-ray`, identificador de requisição fornecido pela SimPix, corpo sanitizado e `idempotency-key` interno.
- Remover do registro qualquer chave, token, CPF, nome, e-mail, telefone ou QR Code.
- Preservar o comportamento atual: cobrança fica `FAILED` e o usuário recebe a mesma mensagem.
- Não adicionar retry, não alterar webhook, banco, tabelas ou secrets.

## Validação
- Confirmar que uma resposta JSON válida continua criando a cobrança normalmente.
- Confirmar que respostas JSON e não JSON com erro geram registros úteis e sanitizados.
- Confirmar que nenhum segredo ou dado pessoal aparece nos registros.

## Constatações que orientam o plano
- O formato atual coincide com a documentação oficial da SimPix.
- A mesma implementação produziu falhas `502` e depois uma cobrança aceita.
- Os registros atuais descartam o corpo não JSON e não armazenam cabeçalhos de diagnóstico, impedindo atribuir retroativamente o `502` a uma camada específica.
