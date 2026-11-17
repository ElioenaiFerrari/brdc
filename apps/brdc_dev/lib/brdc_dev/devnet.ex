defmodule BrdcDev.Devnet do
  @moduledoc """
  Chaves e gênese da rede de teste local (pasta `net/`, ignorada pelo git). Cria o que falta e **nunca
  sobrescreve** chaves existentes. Papéis: `v1` (validador), `i1` e `i2` (emissores, 2 de 2), `a1` e `a2`
  (autoridades raiz, 2 de 2). As janelas de contestação e veto são de 60 s, para testar sem esperar horas.
  """
  alias BrdcNode.{Genesis, Keygen}

  @roles ~w(v1 i1 i2 a1 a2)

  @type t :: %{genesis: Genesis.t(), dir: Path.t(), seeds: %{String.t() => <<_::256>>}}

  @doc "Pasta padrão (`net/` na raiz da umbrella)."
  def default_dir, do: Path.expand("../../../../net", __DIR__)

  @doc "Garante chaves e gênese em `dir` e devolve tudo carregado."
  @spec ensure(Path.t()) :: {:ok, t()} | {:error, term()}
  def ensure(dir \\ default_dir()) do
    with :ok <- ensure_keys(dir),
         {:ok, seeds} <- load_seeds(dir),
         {:ok, genesis} <- ensure_genesis(dir) do
      {:ok, %{genesis: genesis, dir: dir, seeds: seeds}}
    end
  end

  defp ensure_keys(dir) do
    Enum.reduce_while(@roles, :ok, fn role, :ok ->
      case ensure_key(dir, role) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp ensure_key(dir, role) do
    if File.exists?(Path.join(dir, role <> ".seed")) do
      :ok
    else
      with {:ok, _} <- Keygen.generate(dir, role), do: :ok
    end
  end

  defp load_seeds(dir) do
    Enum.reduce_while(@roles, {:ok, %{}}, fn role, {:ok, acc} ->
      case Keygen.load_seed(Path.join(dir, role <> ".seed")) do
        {:ok, seed} -> {:cont, {:ok, Map.put(acc, role, seed)}}
        {:error, reason} -> {:halt, {:error, {role, reason}}}
      end
    end)
  end

  defp ensure_genesis(dir) do
    path = Path.join(dir, "genesis.json")

    case File.read(path) do
      {:ok, json} -> Genesis.from_json(json)
      {:error, :enoent} -> create_genesis(dir, path)
      {:error, _} = err -> err
    end
  end

  defp create_genesis(dir, path) do
    pub = fn role ->
      {:ok, key} = Keygen.load_public(Path.join(dir, role <> ".pub"))
      key
    end

    with {:ok, g} <-
           Genesis.new(
             chain_id: "brdc-devnet",
             validators: [pub.("v1")],
             issuers: [pub.("i1"), pub.("i2")],
             threshold: 2,
             authorities: [pub.("a1"), pub.("a2")],
             authority_threshold: 2,
             contest_window: 60,
             veto_window: 60,
             min_window: 1
           ),
         :ok <- File.write(path, Genesis.to_json(g) <> "\n") do
      {:ok, g}
    end
  end
end
