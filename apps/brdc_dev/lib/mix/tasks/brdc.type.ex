defmodule Mix.Tasks.Brdc.Type do
  @shortdoc "SIMULA as autoridades criando um tipo de credencial (só dev)"
  @moduledoc """
  Cria um tipo de credencial na rede de teste local, assinando como as autoridades raiz de teste.

      mix brdc.type cnh --organ <chave pública hex> [--organ <hex> ...] [--threshold 2]
          [--contest 60] [--validity 0] [--private] [--port 4545] [--dir net]

  `--organ` é a **chave pública (64 caracteres hexadecimais)** de cada membro do órgão; a carteira mostra a
  sua. `--threshold` é o M do M-de-N. Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.{Authority, Devnet}

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          organ: [:string, :keep],
          threshold: :integer,
          contest: :integer,
          validity: :integer,
          private: :boolean,
          port: :integer,
          dir: :string
        ]
      )

    Mix.Task.run("app.config")

    with [id] <- rest,
         organ when organ != [] <- opts |> Keyword.get_values(:organ) |> Enum.map(&unhex!/1),
         {:ok, devnet} <- Devnet.ensure(opts[:dir] || Devnet.default_dir()),
         attrs = %{
           id: id,
           organ: organ,
           threshold: opts[:threshold] || length(organ),
           contest: opts[:contest] || 60,
           validity: opts[:validity] || 0,
           privacy: if(opts[:private], do: 1, else: 0)
         },
         {:ok, txid} <- Authority.create_type({~c"127.0.0.1", opts[:port] || 4545}, devnet, attrs) do
      Mix.shell().info("tipo #{id} enviado ao nó: #{Base.encode16(txid, case: :lower)}")
      Mix.shell().info("aparece depois do próximo bloco (cerca de 1 s)")
    else
      {:error, reason} ->
        Mix.raise("não consegui: #{inspect(reason)}")

      other ->
        Mix.raise(
          "uso: mix brdc.type ID --organ CHAVE_PUBLICA_HEX [--organ ...] [--threshold M] (recebi #{inspect(other, limit: 3)})"
        )
    end
  end

  defp unhex!(text) do
    case Base.decode16(text, case: :mixed) do
      {:ok, <<_::256>> = key} -> key
      _ -> Mix.raise("chave pública inválida (esperava 64 caracteres hexadecimais): #{text}")
    end
  end
end
