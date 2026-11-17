defmodule Mix.Tasks.Brdc.Asset do
  @shortdoc "SIMULA autoridades e órgão criando classe e registrando bem (só dev)"
  @moduledoc """
  Cria classes de bens e registra bens na rede de teste local. SÓ DESENVOLVIMENTO: as autoridades raiz e os
  membros do órgão são chaves de teste.

      mix brdc.asset class imovel --organ <chave pública hex> [--organ ...] [--threshold 1] [--veto 60]
      mix brdc.asset register imovel casa-1 <endereço do dono> "Rua A, 10" --signer <semente hex> [--signer ...]

  Na carteira, o órgão de teste são as contas da frase de teste com passphrases `m1`, `m2`, `m3`
  (veja `docs/flows/17`); o registro é assinado por `--organ-test N` desses membros (padrão 2).
  Opções comuns: `--port 4545`, `--dir net`.
  """
  use Mix.Task
  alias BrdcCrypto.{Account, Address}
  alias BrdcDev.{Authority, Devnet}

  @test_mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
  @test_passphrases ["m1", "m2", "m3"]

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          organ: [:string, :keep],
          threshold: :integer,
          veto: :integer,
          organ_test: :integer,
          port: :integer,
          dir: :string
        ]
      )

    Mix.Task.run("app.config")
    endpoint = {~c"127.0.0.1", opts[:port] || 4545}
    {:ok, devnet} = Devnet.ensure(opts[:dir] || Devnet.default_dir())

    case rest do
      ["class", id] ->
        class(endpoint, devnet, id, opts)

      ["register", class, id, owner, meta] ->
        register(endpoint, devnet, %{class: class, id: id, owner: owner, meta: meta}, opts)

      _ ->
        Mix.raise("uso: mix brdc.asset class ID --organ HEX… | register CLASSE ID DONO DESCRICAO")
    end
  end

  defp class(endpoint, devnet, id, opts) do
    organ = opts |> Keyword.get_values(:organ) |> Enum.map(&unhex!/1)
    if organ == [], do: Mix.raise("informe ao menos um --organ")

    attrs = %{
      id: id,
      organ: organ,
      threshold: opts[:threshold] || 1,
      veto_window: opts[:veto] || 60
    }

    done(Authority.create_class(endpoint, devnet, attrs), "classe #{id}")
  end

  defp register(endpoint, devnet, %{owner: owner} = a, opts) do
    {:ok, owner_hash} = Address.decode(owner)
    n = opts[:organ_test] || 2

    seeds =
      for p <- Enum.take(@test_passphrases, n),
          do: elem(Account.from_mnemonic(@test_mnemonic, p), 1).seed

    done(
      Authority.register_asset(endpoint, devnet, seeds, %{a | owner: owner_hash}),
      "bem #{a.id}"
    )
  end

  defp done({:ok, txid}, what),
    do:
      Mix.shell().info(
        "#{what} enviado ao nó: #{Base.encode16(txid, case: :lower)} (aparece no próximo bloco)"
      )

  defp done({:error, reason}, what), do: Mix.raise("#{what}: #{inspect(reason)}")

  defp unhex!(text) do
    case Base.decode16(text, case: :mixed) do
      {:ok, <<_::256>> = key} -> key
      _ -> Mix.raise("chave pública inválida (64 caracteres hexadecimais): #{text}")
    end
  end
end
