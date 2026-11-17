from lib import *


def phrase_to_address():
    d = D("phrase-to-address", 1100, 560, "Da frase ao endereço", "Cada passo é determinístico: a mesma frase e a mesma passphrase sempre dão o mesmo endereço", "FLUXO 01")
    d.arrow([(280, 168), (420, 168)], "link", label="PBKDF2, 2048 voltas", at=(350, 150))
    d.arrow([(640, 168), (780, 168)], "default", label="HMAC-SHA512", at=(710, 150))
    d.arrow([(890, 206), (890, 290)], "default", label="m/44'/…/conta'/0'/índice'", at=(890, 250))
    d.arrow([(780, 328), (640, 328)], "default", label="Ed25519", at=(710, 310))
    d.arrow([(420, 328), (280, 328)], "boto", label="hash etiquetado + bech32m", at=(350, 310))
    d.node(60, 130, 220, 76, "Frase + passphrase", "BIP-39 · bip39.ex", "onca", "só no navegador", sub2="a 25ª palavra entra aqui")
    d.node(420, 130, 220, 76, "Semente (64 bytes)", "bip39.ex", "link", "bytes")
    d.node(780, 130, 220, 76, "Chave mestra", "SLIP-10 · slip10.ex", "plain", "bytes")
    d.node(780, 290, 220, 76, "Chave privada", "32 bytes · account.ex", "onca", "nunca sai do navegador")
    d.node(420, 290, 220, 76, "Chave pública", "ed25519.ex", "focal", "32 bytes")
    d.node(60, 290, 220, 76, "Endereço brdc1…", "address.ex", "boto", "público")
    d.text(60, 410, "Outra passphrase muda a semente e, por consequência, tudo o que vem depois:", 11, INK, weight=600)
    d.text(60, 428, "é uma carteira completamente diferente, e esquecê-la perde os fundos.", 11, MUTED)
    d.legend([(LINK, "derivação", False), (MUTED, "chave e caminho", False), (BOTO, "dado público", False)])
    return d
