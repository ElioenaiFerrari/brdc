defmodule Mix.Tasks.Brdc do
  @shortdoc "Lista os comandos mix brdc.*"
  @moduledoc """
  Lista os comandos do projeto (rede de teste, carteiras de teste, moeda e qualidade).

      mix brdc
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    BRDC: comandos de desenvolvimento (rede de TESTE, carteiras de TESTE e qualidade)

    Qualidade e documentação
      mix brdc.check [--skip-js] [--skip-docs]   formato, credo, compilação sem avisos, testes, JS e docs
      mix brdc.docs.check                        links, imagens, apps no README, molde dos fluxos, status dos ADRs
      mix brdc.js.test                           criptografia do navegador (Node) contra os vetores do Elixir
      mix brdc.diagrams                          regenera docs/diagrams/*.png (precisa do Brave)

    Rede de teste local (N validadores, cada um num processo; blocos em disco)
      mix brdc.devnet.init [--validators N]      cria a gênese e as chaves (padrão 4; `--solo` = 1)
      mix brdc.devnet.up [--interval 1s]         sobe os validadores em segundo plano (religa quem caiu)
      mix brdc.devnet.status                     quem está no ar, altura, pendentes, quórum e acordo
      mix brdc.devnet.logs [N] [--follow]        log de um validador
      mix brdc.devnet.kill N                     derruba o validador N com kill -9 (simula uma queda)
      mix brdc.devnet.down                       para todos (os blocos ficam no disco)
      mix brdc.devnet.reset [--all]              apaga blocos, diários, pids e logs (--all: e a gênese)
      mix brdc.node --index K                    roda um validador em primeiro plano
      mix phx.server                             carteira em http://localhost:4000 (acha o validador 1 em :4545;
                                                 sem rede gerenciada, embute um nó solo)

    Simulação de falhas (só DESENVOLVIMENTO; fluxo 23)
      mix brdc.devnet.equivocate [--victim K]    um validador assina dois votos conflitantes: confere se os
                                                 honestos detectam e se a rede segue viva (só detecção, não punição)

    Laboratório Docker (validadores e carteiras em containers de recursos limitados; fluxos 22 e 23)
      mix brdc.compose.init [--validators N]     chaves de teste, gênese e docker-compose.yml (pasta compose/)
      mix brdc.compose.up                        constrói a imagem, sobe tudo e espera a rede andar
      mix brdc.compose.status                    altura, pares, motor de consenso, evidências e pendentes
      mix brdc.compose.equivocate                o equivocador toma o lugar do último validador e confere a detecção
      mix brdc.compose.down [--volumes]          derruba (com --volumes apaga também os blocos)

    Explorador (somente leitura; fluxo 20) e rede entre computadores (fluxo 21)
      mix brdc.blocks [ALTURA]                   blocos recentes, ou um bloco com o certificado conferido
      mix brdc.tx ID | --pending | --of CONTA    transação, pendentes ou histórico de uma conta
      mix brdc.validator --genesis … --seed …    roda UM validador a partir de arquivos (um por computador)

    Carteiras de TESTE (frase em texto puro em net/wallets; só para simular pessoas)
      mix brdc.wallet.new NOME                   cria uma carteira de teste
      mix brdc.wallet.list                       lista as carteiras com endereço e saldo
      mix brdc.send DE PARA VALOR                transferência (taxa mínima), espera o bloco
      mix brdc.balance QUEM                      saldo e nonce (nome de carteira de teste ou endereço)

    Produção da moeda (os emissores de TESTE assinam, 2 de 2; 1 BRDC = R$ 1)
      mix brdc.reserve TOTAL                     atesta quantos reais há em caixa (lastro)
      mix brdc.mint QUEM VALOR                   emite BRDC (`brdc.fund` é atalho)
      mix brdc.burn CARTEIRA VALOR               resgate: queima BRDC do titular
      mix brdc.supply                            emitido, queimado, em circulação, reserva e cobertura
      mix brdc.simulate issuance                 ciclo completo (depósito, atestado, emissão, M-de-N,
                                                 pagamento, resgate, queima) e conferência das regras

    Órgãos e autoridades de TESTE
      mix brdc.type ID --organ HEX…              cria um tipo de credencial
      mix brdc.asset class|register …            cria classe de bens e registra bem

    Chaves e gênese (por validador)
      mix brdc.keygen …    mix brdc.genesis …
    """)
  end
end
