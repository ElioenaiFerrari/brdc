from lib import *


def asset_trade():
    d = D("asset-trade", 1100, 560, "Transferência de propriedade de um bem", "O dinheiro fica em escrow durante a janela: o órgão pode vetar antes do prazo, qualquer um finaliza depois", "FLUXO 09")
    d.arrow([(280, 168), (420, 168)], "link", label="aceite do comprador", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="começa a janela", at=(710, 150))
    d.arrow([(530, 206), (530, 290)], "boto", label="antes do prazo", at=(600, 248))
    d.arrow([(890, 206), (890, 290)], "boto", label="depois do prazo", at=(960, 248))
    d.arrow([(420, 328), (280, 328)], "boto", label="devolve", at=(350, 310))
    d.node(60, 130, 220, 76, "Oferta do dono", "bem sem gravame", "onca", "tipo 7", sub2="comprador e preço")
    d.node(420, 130, 220, 76, "Escrow", "preço sai do comprador", "focal", "tipo 8", sub2="prazo = hora do bloco + janela")
    d.node(780, 130, 220, 76, "Janela de veto", "em segundos (ADR-0016)", "plain", "24 h ou 48 h")
    d.node(420, 290, 220, 76, "Veto do órgão", "aprovação M-de-N", "boto", "tipo 10")
    d.node(780, 290, 220, 76, "Finalização", "qualquer um envia", "link", "tipo 11", sub2="dono muda, escrow vai ao vendedor")
    d.node(60, 290, 220, 76, "Escrow volta", "ao comprador", "plain", "negociação cancelada")
    d.text(60, 410, "Gravame do órgão bloqueia a oferta e impede a finalização até ser removido.", 11, INK, weight=600)
    d.text(60, 428, "A chain confia no órgão para saber quem é o dono; ela só executa as regras e guarda o escrow.", 11, MUTED)
    d.legend([(LINK, "etapa do comprador", False), (MUTED, "janela", False), (BOTO, "desfechos possíveis", False)])
    return d


def credential_lifecycle():
    d = D("credential-lifecycle", 1100, 560, "Ciclo de vida de uma credencial", "Nasce pendente, ganha validade depois da janela de contestação e pode ser revogada pelo órgão", "FLUXO 10")
    d.arrow([(280, 168), (420, 168)], "link", label="emissão M-de-N", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="passou a janela", at=(710, 150))
    d.arrow([(530, 206), (530, 290)], "boto", label="titular contesta / órgão veta", at=(640, 248))
    d.arrow([(890, 206), (890, 290)], "boto", label="expira ou órgão revoga", at=(990, 248))
    d.node(60, 130, 220, 76, "Órgão emite", "tipo 15 · cred_id único", "onca", "pública ou privada", sub2="dados ou compromisso")
    d.node(420, 130, 220, 76, "Pendente", "janela de contestação", "focal", "em segundos")
    d.node(780, 130, 220, 76, "Ativa", "ativada por qualquer um", "link", "tipo 18", sub2="vale até expirar")
    d.node(420, 290, 220, 76, "Descartada", "contestada ou vetada", "plain", "tipos 16 e 17", sub2="id queimado")
    d.node(780, 290, 220, 76, "Sem validade", "expirada ou revogada", "boto", "tipo 19")
    d.node(60, 290, 220, 76, "Divórcio ativado", "referencia o casamento", "store", "revoga o casamento", sub2="um por cônjuge")
    d.text(60, 410, "Privada guarda só um compromisso de 32 bytes: quem recebe os dados confere contra ele.", 11, INK, weight=600)
    d.text(60, 428, "A chain prova quem declarou o quê e quando; não prova que a declaração é verdadeira.", 11, MUTED)
    d.legend([(LINK, "emissão", False), (MUTED, "ciclo normal", False), (BOTO, "saídas", False)])
    return d
