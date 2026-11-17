defmodule Mix.Tasks.Brdc.Genesis do
  @shortdoc "Monta o documento de gênese da rede a partir das chaves públicas"
  @moduledoc """
  Monta `genesis.json` com validadores, emissores, taxas e a lista de partida.

      mix brdc.genesis --chain-id brdc-devnet --validators v1,v2,v3 --issuers i1,i2 --threshold 2 \\
        --peer v1=127.0.0.1:4001 --peer v2=127.0.0.1:4002 [--dir net] [--out net/genesis.json]
        [--authorities a1,a2 --authority-threshold 2]   # criam classes de bens e tipos de credencial
        [--contest-window 60 --veto-window 60 --min-window 1]   # segundos; rede de teste

  Os nomes são lidos de `<dir>/<nome>.pub` (criados por `mix brdc.keygen`). A **ordem** dos
  validadores define o rodízio de proponentes. Só chaves públicas entram no arquivo.
  """
  use Mix.Task
  alias BrdcNode.{Genesis, Keygen}

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          chain_id: :string,
          validators: :string,
          issuers: :string,
          authorities: :string,
          authority_threshold: :integer,
          threshold: :integer,
          peer: :keep,
          contest_window: :integer,
          veto_window: :integer,
          min_window: :integer,
          dir: :string,
          out: :string
        ]
      )

    dir = Keyword.get(opts, :dir, "net")
    out = Keyword.get(opts, :out, Path.join(dir, "genesis.json"))

    validators = names(opts[:validators]) |> Enum.map(&public!(dir, &1))
    issuers = names(opts[:issuers]) |> Enum.map(&public!(dir, &1))
    authorities = names(opts[:authorities]) |> Enum.map(&public!(dir, &1))
    bootstrap = opts |> Keyword.get_values(:peer) |> Enum.map(&peer!(&1, dir))

    case Genesis.new(
           [
             chain_id: opts[:chain_id] || "brdc-devnet",
             validators: validators,
             issuers: issuers,
             threshold: opts[:threshold] || length(issuers),
             bootstrap: bootstrap,
             authorities: authorities,
             authority_threshold: opts[:authority_threshold] || max(length(authorities), 1)
           ] ++ windows(opts)
         ) do
      {:ok, g} ->
        File.mkdir_p!(Path.dirname(out))
        File.write!(out, Genesis.to_json(g) <> "\n")
        Mix.shell().info("gênese gravada em #{out}")
        Mix.shell().info("hash: #{Base.encode16(Genesis.hash(g), case: :lower)}")

      {:error, reason} ->
        Mix.raise("gênese inválida: #{reason}")
    end
  end

  # só repassa as janelas que o operador informou; o resto fica no padrão (ADR-0016)
  defp windows(opts), do: Keyword.take(opts, [:contest_window, :veto_window, :min_window])

  defp names(nil), do: []
  defp names(s), do: s |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp public!(dir, name) do
    case Keygen.load_public(Path.join(dir, name <> ".pub")) do
      {:ok, key} -> key
      {:error, reason} -> Mix.raise("não consegui ler #{name}.pub em #{dir}: #{inspect(reason)}")
    end
  end

  defp peer!(spec, dir) do
    with [name, addr] <- String.split(spec, "=", parts: 2),
         [host, port] <- String.split(addr, ":", parts: 2),
         {port, ""} <- Integer.parse(port) do
      %{validator: public!(dir, name), host: host, port: port}
    else
      _ -> Mix.raise("--peer inválido (use nome=host:porta): #{spec}")
    end
  end
end
