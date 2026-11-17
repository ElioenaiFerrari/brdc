# Ferramentas de desenvolvimento da BRDC

**Só desenvolvimento, nunca em release.** Sobe o nó local de um validador junto com o resto da umbrella e traz as tarefas `mix brdc.*`.

```
make run                                  # carteira (porta 4000) + nó local (porta 4545)
make fund ADDR=brdc1… AMOUNT=100          # BRDC de TESTE para um endereço (assina como os emissores de teste)
make balance ADDR=brdc1…                  # saldo no nó local
```

As chaves e a gênese da rede de teste ficam em `net/` (fora do git, sementes `0600`). Fluxo: [14](../../docs/flows/14-local-node-and-send.md).
