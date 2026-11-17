from lib import *


def block_execution():
    d = D("block-execution", 1100, 560, "Como um bloco é executado", "Tudo ou nada: uma transação inválida recusa o bloco inteiro e o estado não muda", "FLUXO 02")
    d.arrow([(280, 168), (420, 168)], "link", label="cabeçalho ok?", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="cada tx, em ordem", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="taxas somadas", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="raiz de estado", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="igual ao cabeçalho?", at=(350, 310))
    d.node(60, 130, 220, 76, "Bloco recebido", "block.ex", "external", "do consenso", sub2="altura, prev_hash, signers")
    d.node(420, 130, 220, 76, "Confere limites", "block.ex", "link", "sem bloco vazio")
    d.node(780, 130, 220, 76, "Executa as txs", "executor.ex", "focal", "assinatura, nonce, saldo")
    d.node(780, 290, 220, 76, "Reparte a taxa", "block.ex", "plain", "entre quem assinou")
    d.node(420, 290, 220, 76, "Calcula a raiz", "state.ex", "store", "Merkle das contas")
    d.node(60, 290, 220, 76, "Novo estado", "ou recusa total", "boto", "atômico")
    d.text(60, 410, "A oferta nunca muda numa transferência: só mint e burn, aprovados por M-de-N emissores.", 11, INK, weight=600)
    d.text(60, 428, "A taxa não some: vai para os validadores, então saldos somados = emitido − queimado.", 11, MUTED)
    d.legend([(LINK, "validação", False), (MUTED, "execução", False), (BOTO, "resultado", False)])
    return d
