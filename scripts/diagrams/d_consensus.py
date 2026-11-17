from lib import *


def consensus_round():
    d = D("consensus-round", 1100, 560, "Uma rodada de consenso", "Mais de 2/3 de precommits no mesmo bloco o tornam final; sem progresso, outra rodada com outro proponente", "FLUXO 03")
    d.arrow([(280, 168), (420, 168)], "link", label="proposta assinada", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="> 2/3 prevotes", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="trava e precommit", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "boto", label="> 2/3 precommits", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="certificado", at=(350, 310))
    d.node(60, 130, 220, 76, "Proponente", "rodízio por altura + rodada", "external", "propõe", sub2="bloco novo ou o já travado")
    d.node(420, 130, 220, 76, "Prevote", "cada validador", "link", "vota se válido")
    d.node(780, 130, 220, 76, "Trava no bloco", "só destrava com prova", "plain", "segurança")
    d.node(780, 290, 220, 76, "Precommit", "cada validador", "focal", "voto de compromisso")
    d.node(420, 290, 220, 76, "Bloco final", "decide e monta o certificado", "boto", "imediato")
    d.node(60, 290, 220, 76, "Ledger executa", "Fase 2", "store", "novo estado")
    d.text(60, 410, "Proponente em silêncio ou rede lenta: o prazo estoura e a rodada seguinte tem outro proponente.", 11, INK, weight=600)
    d.text(60, 428, "Sem quórum a rede pausa; nunca bifurca. Dois votos diferentes na mesma rodada viram evidência.", 11, MUTED)
    d.legend([(LINK, "proposta e votos", False), (MUTED, "etapas internas", False), (BOTO, "decisão final", False)])
    return d
