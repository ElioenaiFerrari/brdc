from lib import *


def secure_channel():
    d = D("secure-channel", 1100, 560, "Como dois validadores se conectam", "A chave do certificado é a chave de consenso; quem não está no conjunto é recusado no próprio handshake", "FLUXO 04")
    d.arrow([(280, 168), (420, 168)], "link", label="TCP + TLS 1.3", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="certificado autoassinado", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="chave está no conjunto?", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="hello", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="par autenticado", at=(350, 310))
    d.node(60, 130, 220, 76, "Validador A", "brdc_p2p · channel.ex", "onca", "cliente", sub2="seed Ed25519 de consenso")
    d.node(420, 130, 220, 76, "Handshake TLS 1.3", "só :ssl do OTP", "link", "X25519 · Ed25519")
    d.node(780, 130, 220, 76, "Validador B", "brdc_p2p · cert.ex", "onca", "servidor", sub2="o mesmo, nos dois sentidos")
    d.node(780, 290, 220, 76, "verify_fun", "conjunto em vigor", "focal", "recusa estranhos")
    d.node(420, 290, 220, 76, "hello", "chain_id + genesis", "plain", "rede certa?")
    d.node(60, 290, 220, 76, "Quadros", "tamanho limitado + prazo", "boto", "cifrados")
    d.text(60, 410, "Sem CA e sem biblioteca nova: tudo é o TLS do OTP, mais a conferência da chave no conjunto.", 11, INK, weight=600)
    d.text(60, 428, "No TLS 1.3 o cliente pode terminar antes do servidor validar: só vale depois do hello.", 11, MUTED)
    d.legend([(LINK, "canal", False), (MUTED, "verificação", False), (BOTO, "resultado", False)])
    return d
