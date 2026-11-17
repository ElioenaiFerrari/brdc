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


def limits_and_bans():
    d = D("limits-and-bans", 1100, 560, "Limites e banimento na porta de pares", "O IP é checado antes do handshake e a chave depois; ofensas somam pontos até o banimento temporário", "FLUXO 05")
    d.arrow([(280, 168), (420, 168)], "link", label="IP banido ou cheio?", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="handshake + hello", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="chave banida ou cheia?", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="mensagens", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="pontos > limite", at=(350, 310))
    d.node(60, 130, 220, 76, "Conexão TCP", "listener.ex", "external", "chega", sub2="de qualquer IP")
    d.node(420, 130, 220, 76, "Admissão por IP", "limits.ex · Guard", "link", "antes do handshake")
    d.node(780, 130, 220, 76, "Canal TLS", "channel.ex", "plain", "chave no conjunto")
    d.node(780, 290, 220, 76, "Admissão por chave", "limits.ex · Guard", "focal", "máx. por validador")
    d.node(420, 290, 220, 76, "Sessão", "session.ex", "plain", "taxa e tamanho")
    d.node(60, 290, 220, 76, "Banimento temporário", "chave (e IP, exceto loopback)", "boto", "expira sozinho")
    d.text(60, 410, "Quadro gigante bane de uma vez; mau hello, malformado e excesso de taxa somam pontos.", 11, INK, weight=600)
    d.text(60, 428, "Loopback nunca é banido por IP: todos os nós de uma máquina de testes dividem o endereço.", 11, MUTED)
    d.legend([(LINK, "admissão", False), (MUTED, "sessão", False), (BOTO, "punição", False)])
    return d


def peer_discovery():
    d = D("peer-discovery", 1100, 560, "Como um validador descobre os outros", "Cada endereço é assinado pelo dono; quem repassa não pode falsificar nem rebaixar um registro", "FLUXO 06")
    d.arrow([(280, 168), (420, 168)], "link", label="get_addrs", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="addrs (até 64)", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="confere cada um", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="seq maior vence", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="disca pelo endereço", at=(350, 310))
    d.node(60, 130, 220, 76, "Validador A", "conhece só o B", "onca", "pergunta")
    d.node(420, 130, 220, 76, "Validador B", "livro de endereços", "link", "responde", sub2="sabe de A, B e C")
    d.node(780, 130, 220, 76, "Resposta", "registros assinados", "plain", "dados")
    d.node(780, 290, 220, 76, "Confere", "rede, assinatura, conjunto", "focal", "descarta o falso")
    d.node(420, 290, 220, 76, "Livro de A", "address_book.ex", "store", "um por validador")
    d.node(60, 290, 220, 76, "Validador C", "descoberto por A", "boto", "conexão TLS")
    d.text(60, 410, "O registro do C foi assinado pelo C: o B só o repassa e não pode alterar host, porta ou seq.", 11, INK, weight=600)
    d.text(60, 428, "Registro antigo reenviado é recusado (seq menor ou igual); quem saiu do conjunto é esquecido.", 11, MUTED)
    d.legend([(LINK, "pergunta e resposta", False), (MUTED, "verificação", False), (BOTO, "resultado", False)])
    return d


def keygen_and_genesis():
    d = D("keygen-and-genesis", 1100, 560, "Como uma rede de teste nasce", "Cada validador gera a própria chave; a gênese junta só as chaves públicas e fixa as regras da rede", "FLUXO 07")
    d.arrow([(280, 168), (420, 168)], "link", label="mix brdc.keygen", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="só a parte pública", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="mix brdc.genesis", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="hash da gênese", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="hello confere", at=(350, 310))
    d.node(60, 130, 220, 76, "Cada operador", "um por validador e emissor", "onca", "na própria máquina")
    d.node(420, 130, 220, 76, "Chave privada", "nome.seed · permissão 0600", "focal", "nunca sai", sub2="não sobrescreve")
    d.node(780, 130, 220, 76, "Chave pública", "nome.pub", "plain", "pode circular")
    d.node(780, 290, 220, 76, "genesis.json", "validadores, emissores, taxas", "link", "sem segredo", sub2="e lista de partida")
    d.node(420, 290, 220, 76, "Impressão digital", "hash determinístico", "store", "32 bytes")
    d.node(60, 290, 220, 76, "Nós com a mesma gênese", "se aceitam no hello", "boto", "rede única")
    d.text(60, 410, "Gênese diferente = hash diferente = nós se recusam, mesmo com chaves do mesmo conjunto.", 11, INK, weight=600)
    d.text(60, 428, "A ordem dos validadores entra no hash porque define o rodízio de proponentes.", 11, MUTED)
    d.legend([(LINK, "geração", False), (MUTED, "dados", False), (BOTO, "conferência", False)])
    return d


def public_port():
    d = D("public-port", 1100, 560, "Porta pública para carteira e explorador", "Poucos tipos de pedido, tamanho e taxa limitados; quem pergunta reverifica tudo", "FLUXO 08")
    d.arrow([(280, 168), (420, 168)], "link", label="IP admitido?", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="tipo na lista?", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="tamanho e taxa", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="handler do nó", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="resposta ou erro", at=(350, 310))
    d.node(60, 130, 220, 76, "Cliente", "carteira ou explorador", "onca", "sem identidade")
    d.node(420, 130, 220, 76, "Guard", "teto por IP e total", "link", "banimento")
    d.node(780, 130, 220, 76, "4 tipos de pedido", "status, enviar tx, bloco, conta", "plain", "lista fixa")
    d.node(780, 290, 220, 76, "Limites", "por tipo e por conexão", "focal", "tamanho · taxa · prazo")
    d.node(420, 290, 220, 76, "Handler isolado", "falha vira erro genérico", "store", "o nó decide")
    d.node(60, 290, 220, 76, "Cliente reverifica", "assinaturas e certificado", "boto", "não confia no nó")
    d.text(60, 410, "Tipo desconhecido, corpo acima do máximo ou excesso de taxa derrubam a conexão.", 11, INK, weight=600)
    d.text(60, 428, "Não é cifrada nem autenticada: por isso o cliente nunca aceita nada sem conferir a prova.", 11, MUTED)
    d.legend([(LINK, "admissão", False), (MUTED, "validação", False), (BOTO, "resposta", False)])
    return d
