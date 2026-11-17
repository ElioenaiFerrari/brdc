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
