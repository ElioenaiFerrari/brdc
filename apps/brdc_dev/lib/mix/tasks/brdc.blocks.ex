defmodule Mix.Tasks.Brdc.Blocks do
  @shortdoc "Lista os blocos mais recentes (ou mostra um bloco, conferido)"
  @moduledoc """
  Sem argumento, lista os blocos mais recentes da rede de teste: altura, hora, quem propôs, transações e
  quantos validadores assinaram.

  Com uma altura, mostra o bloco inteiro e **confere o certificado de commit** (mais de 2/3 dos validadores
  assinaram aquele mesmo bloco). Sem fixar as chaves da gênese, a conferência usa as chaves que o próprio nó
  informa e diz isso: ela prova que o bloco é consistente, não que o nó é honesto.

      mix brdc.blocks [--count N] [--before ALTURA] [--port P] [--dir net]
      mix brdc.blocks ALTURA [--port P] [--dir net]
  """
  use Mix.Task
  alias BrdcCrypto.{Address, Bech32m}
  alias BrdcDev.Cli
  alias BrdcLedger.Tx
  alias BrdcNode.{Client, Explorer}

  @impl Mix.Task
  def run(args) do
    {opts, rest, endpoint, _dir} =
      Cli.parse(args, [count: :integer, before: :integer], @moduledoc, "")

    Cli.ensure_node!(endpoint)

    case rest do
      [] -> list(endpoint, opts)
      [h] -> show(endpoint, height!(h))
      _ -> Mix.raise("use `mix brdc.blocks [ALTURA]`")
    end
  end

  defp height!(text) do
    case Integer.parse(text) do
      {h, ""} when h > 0 -> h
      _ -> Mix.raise("altura inválida: #{inspect(text)}")
    end
  end

  defp list(endpoint, opts) do
    count = min(max(opts[:count] || 15, 1), 100)

    case Client.blocks(endpoint, opts[:before] || 0, count) do
      {:ok, []} ->
        Mix.shell().info("a rede ainda não produziu blocos (só há bloco quando há transação)")

      {:ok, rows} ->
        Mix.shell().info("altura  hora                     txs  assinaturas  hash")

        for r <- rows do
          Mix.shell().info(
            "#{String.pad_trailing(to_string(r.height), 7)} #{String.pad_trailing(Explorer.time(r.time), 24)} " <>
              "#{String.pad_trailing(to_string(r.tx_count), 4)} #{String.pad_trailing(to_string(r.signers), 12)} " <>
              Explorer.hex(r.hash)
          )
        end

      {:error, reason} ->
        Mix.raise("não consegui listar: #{inspect(reason)}")
    end
  end

  defp show(endpoint, height) do
    case Client.block(endpoint, height) do
      {:ok, r} ->
        b = r.block

        Mix.shell().info("""
        bloco #{b.height}
          hash        #{Explorer.hex(r.hash, full: true)}
          anterior    #{if b.prev_hash, do: Explorer.hex(b.prev_hash, full: true), else: "(gênese)"}
          hora        #{Explorer.time(b.time)}
          proposto por #{Bech32m.encode(Address.hrp(), b.proposer)}
          raiz de estado #{if b.state_root, do: Explorer.hex(b.state_root), else: "—"}
          #{certificate_line(r)}
        transações (#{length(b.txs)})\
        """)

        for {tx, i} <- Enum.with_index(b.txs) do
          Mix.shell().info(
            "  #{i}  #{Explorer.hex(Tx.id(tx), full: true)}  #{Explorer.kind_label(tx.kind)}"
          )
        end

      {:error, "not_found"} ->
        Mix.raise("o bloco #{height} não existe (ou já saiu da memória do nó)")

      {:error, reason} ->
        Mix.raise("não consegui ler o bloco: #{inspect(reason)}")
    end
  end

  defp certificate_line(%{verified: true, certificate: c, trust: trust}) do
    "certificado  CONFERIDO: #{length(c.votes)} assinaturas válidas (mais de 2/3), #{trust_note(trust)}"
  end

  defp certificate_line(%{verified: false, reason: why}),
    do: "certificado  NÃO CONFERIDO (#{why}): não confie neste bloco"

  defp trust_note(:pinned), do: "contra as chaves fixadas"

  defp trust_note(:node_reported),
    do: "contra as chaves que o próprio nó informou (fixe as da gênese para confiança total)"
end
