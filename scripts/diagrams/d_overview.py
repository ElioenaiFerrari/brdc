from lib import *


def architecture_overview():
    d = D("architecture-overview", 1100, 640, "Arquitetura da BRDC", "A chave nunca sai do navegador do usuário; os validadores só enxergam transações já assinadas", "VISÃO GERAL")
    d.arrow([(280, 168), (420, 168)], "link", label="tx assinada", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="JSON-RPC", at=(710, 150))
    d.arrow([(530, 206), (530, 290)], "default", label="tx no mempool", at=(600, 248))
    d.arrow([(420, 328), (280, 328)], "default", label="bloco decidido", at=(350, 310))
    d.arrow([(640, 328), (780, 328)], "boto", both=True)
    d.arrow([(530, 366), (530, 450)], "boto")
    d.node(60, 130, 220, 76, "Carteira web", "apps/brdc_web · LiveView", "onca", "navegador", sub2="chaves nascem e ficam aqui")
    d.node(420, 130, 220, 76, "Nó (RPC)", "apps/brdc_node", "link", "OTP")
    d.node(780, 130, 220, 76, "Explorador", "apps/brdc_web", "external", "leitura")
    d.node(60, 290, 220, 76, "Ledger", "apps/brdc_ledger", "boto", "estado", sub2="moeda · bens · credenciais")
    d.node(420, 290, 220, 76, "Consenso BFT", "apps/brdc_consensus", "focal", "finalidade imediata")
    d.node(780, 290, 220, 76, "Outros validadores", "apps/brdc_p2p · TLS 1.3", "plain", "rede P2P")
    d.node(420, 450, 220, 76, "Blocos e estado", "armazenamento local", "store", "disco")
    d.text(60, 410, "O ledger não conhece rede nem consenso:", 11, INK, weight=600)
    d.text(60, 428, "recebe um bloco decidido e devolve o novo estado.", 11, MUTED)
    d.legend([(LINK, "transação assinada", False), (MUTED, "dados", False), (BOTO, "estado e gossip entre nós", False)])
    return d
