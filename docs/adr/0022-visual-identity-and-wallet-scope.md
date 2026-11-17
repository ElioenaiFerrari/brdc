# ADR-0022 — Identidade visual escura com as cores do Brasil e escopo da carteira

**Status:** Aceito (dono do produto, 2026-11-17: instruções diretas na conversa) · Complementa o [ADR-0006](0006-web-wallet-liveview-and-browser-crypto.md).

## Contexto
O dono do produto pediu que a BRDC tenha identidade **própria** (não a do Teko): carteira, logo e demais peças em estilo **escuro**, com as **cores do Brasil** (verde, azul, amarelo e branco), no estilo de uma carteira fintech moderna (referência enviada: fundo quase preto com brilho suave, cartões escuros arredondados, números grandes, botão branco em pílula, teclado numérico). Também pediu que a carteira **emita bens, contratos e credenciais**, não só envie e receba.

## Decisão
1. **Identidade:** tema **único escuro** (`brdc`), cores e tokens em [docs/design/README.md](../design/README.md), fontes do sistema (CSP estrita, sem terceiros), componentes sem JavaScript e sem estilo em linha.
2. **Logo:** marca (moeda azul e verde com losango amarelo) e versão com a palavra.
3. **Escopo da carteira:** cinco seções (Início, Bens, Contratos, Credenciais, Atividade). Emitir e operar bens, credenciais e contratos faz parte da carteira.
4. **Assinatura coletiva:** os M-de-N dos órgãos viram **propostas** que cada membro assina no próprio navegador, vendo o conteúdo em texto claro; com M aprovações, qualquer membro envia.
5. **Navegação:** barra inferior no celular (até 5 itens); no desktop, uma barra superior ou lateral (a definir na implementação).

## Consequências e limites honestos
- Os **diagramas de documentação** ainda usam o tema claro herdado do Teko; migrar para o tema escuro da BRDC é uma decisão separada (regerar os PNGs).
- Só tema escuro: quem preferir claro não tem opção por ora.
- A palavra do logo é texto, não contorno vetorizado.
- A tela de assinatura coletiva e o canal das propostas ainda **não existem**: são o desenho da Fase 6.
- Mostrar em texto claro o que cada assinante assina (o "o que você está assinando") é requisito de segurança, não de beleza: um órgão não deve assinar um documento que não entende.
