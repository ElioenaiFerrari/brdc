# Guia de conceitos

Este guia existe para você **entender cada peça** da BRDC, sem pressupor que já conhece blockchain. Cada página explica o conceito do zero, mostra um exemplo em Elixir (os trechos marcados "roda hoje" foram executados de verdade; os "ilustrativos" mostram a ideia e ainda não existem no código) e diz como a BRDC o usa.

Leia na ordem; cada uma se apoia na anterior.

1. [Blockchain e estado](01-blockchain-and-state.md): o que é uma cadeia de blocos, o que é estado e por que "determinismo" importa.
2. [Hash e assinatura](02-hash-and-signature.md): impressões digitais de dados, assinaturas digitais e hash etiquetado.
3. [Carteira HD e passphrase](03-hd-wallet-and-passphrase.md): frase de 12/24 palavras, a 25ª palavra, derivação de chaves e endereços.
4. [Consenso BFT](04-bft-consensus.md): como vários computadores que não confiam uns nos outros concordam sobre um bloco.
5. [Stablecoin e emissores](05-stablecoin-and-issuers.md): o que mantém 1 BRDC = 1 BRL, mint, burn e o que a chain consegue (e não consegue) provar.
6. [Contratos nativos](06-native-contracts.md): por que não há máquina virtual, módulos nativos e modelos declarativos.
7. [P2P e canal seguro (TLS 1.3 mútuo)](07-p2p-and-secure-channel.md): como os nós conversam com segurança.
8. [Credenciais e bens](08-credentials-and-assets.md): CNH, identificação, casamento, divórcio e transferência de propriedade.
9. [OTP e desempenho](09-otp-and-performance.md): processos, supervisão, e onde GenStage, Broadway, Flow e Reactor cabem (e onde não).
10. [Como ler o código da Fase 1](10-reading-phase-1-code.md): mapa de leitura de `brdc_crypto`, com exemplos que rodam.
11. [Como ler o código da Fase 2](11-reading-phase-2-code.md): mapa de leitura de `brdc_ledger`.
12. [Como ler o código da Fase 3](12-reading-phase-3-code.md): mapa de leitura de `brdc_consensus`.
13. [Como ler o código da Fase 5, parte de bens](13-reading-phase-5a-code.md): mapa de leitura de bens e propriedade.
14. [Como ler o código da Fase 5, parte de credenciais](14-reading-phase-5b-code.md): mapa de leitura de credenciais.

Termos novos estão no [GLOSSARY](../GLOSSARY.md). Ao fim de cada fase de implementação, a página correspondente ganha a seção **"Como ler o código desta fase"**.
