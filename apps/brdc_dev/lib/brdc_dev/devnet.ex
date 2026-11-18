defmodule BrdcDev.Devnet do
  @moduledoc """
  Chaves e gênese da rede de teste local (pasta `net/`, ignorada pelo git). Cria o que falta e **nunca
  sobrescreve** chaves existentes. Papéis: `v1`…`vN` (validadores), `i1` e `i2` (emissores, 2 de 2), `a1` e
  `a2` (autoridades raiz, 2 de 2). As janelas de contestação e veto são de 60 s, para testar sem esperar horas.

  O número de validadores é decidido **na criação da gênese** (`validators: n`, padrão 1) e não muda depois: um
  conjunto diferente é outra rede (`mix brdc.devnet.reset --all`).
  """
  alias BrdcNode.{Genesis, Keygen}

  @fixed_roles ~w(i1 i2 a1 a2)

  @type t :: %{genesis: Genesis.t(), dir: Path.t(), seeds: %{String.t() => <<_::256>>}}

  @doc "Pasta padrão (`net/` na raiz da umbrella)."
  def default_dir, do: Path.expand("../../../../net", __DIR__)

  @doc """
  Garante chaves e gênese em `dir` e devolve tudo carregado. Com `validators: n` (só vale se a gênese ainda não
  existe) cria `n` validadores; com a gênese já criada, vale o número que ela tem.

  **Com a gênese já criada, nada é gerado:** carrega só as sementes que existem na pasta. Isso importa numa rede
  montada por arquivos entre computadores, onde cada máquina tem só as suas sementes (as dos outros validadores
  são apenas `.pub`): gerar uma semente nova em silêncio não bateria com a gênese. Quem precisa de uma semente
  que falta recebe um erro claro (`seed!/2`).
  """
  @spec ensure(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def ensure(dir \\ default_dir(), opts \\ []) do
    case existing_validators(dir) do
      nil -> create(dir, Keyword.get(opts, :validators, 1), opts)
      n -> load_existing(dir, n)
    end
  end

  defp create(dir, n, opts) do
    roles = validator_roles(n) ++ @fixed_roles

    with :ok <- ensure_keys(dir, roles),
         {:ok, seeds} <- load_seeds(dir, roles),
         {:ok, genesis} <- ensure_genesis(dir, n, opts) do
      {:ok, %{genesis: genesis, dir: dir, seeds: seeds}}
    end
  end

  defp load_existing(dir, n) do
    roles =
      Enum.filter(
        validator_roles(n) ++ @fixed_roles,
        &File.exists?(Path.join(dir, &1 <> ".seed"))
      )

    with {:ok, seeds} <- load_seeds(dir, roles),
         {:ok, genesis} <- ensure_genesis(dir, n, []) do
      {:ok, %{genesis: genesis, dir: dir, seeds: seeds}}
    end
  end

  @doc "A semente do papel `role`, ou um erro que diz o que fazer se esta máquina não a tem."
  @spec seed!(t(), String.t()) :: <<_::256>>
  def seed!(%{seeds: seeds, dir: dir}, role) do
    case Map.fetch(seeds, role) do
      {:ok, seed} ->
        seed

      :error ->
        raise ArgumentError,
              "esta máquina não tem #{role}.seed em #{dir}: quem assina como #{role} precisa rodar este comando " <>
                "(a semente nunca é copiada entre computadores)"
    end
  end

  @doc "Papéis dos validadores: v1 até vN."
  @spec validator_roles(pos_integer()) :: [String.t()]
  def validator_roles(n), do: for(i <- 1..n, do: "v#{i}")

  @doc "Quantos validadores tem a gênese já criada em `dir` (`nil` se ainda não há gênese)."
  @spec existing_validators(Path.t()) :: pos_integer() | nil
  def existing_validators(dir) do
    with {:ok, json} <- File.read(Path.join(dir, "genesis.json")),
         {:ok, g} <- Genesis.from_json(json) do
      length(g.validators)
    else
      _ -> nil
    end
  end

  defp ensure_keys(dir, roles) do
    Enum.reduce_while(roles, :ok, fn role, :ok ->
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

  defp load_seeds(dir, roles) do
    Enum.reduce_while(roles, {:ok, %{}}, fn role, {:ok, acc} ->
      case Keygen.load_seed(Path.join(dir, role <> ".seed")) do
        {:ok, seed} -> {:cont, {:ok, Map.put(acc, role, seed)}}
        {:error, reason} -> {:halt, {:error, {role, reason}}}
      end
    end)
  end

  defp ensure_genesis(dir, n, opts) do
    path = Path.join(dir, "genesis.json")

    case File.read(path) do
      {:ok, json} -> Genesis.from_json(json)
      {:error, :enoent} -> create_genesis(dir, path, n, opts)
      {:error, _} = err -> err
    end
  end

  # `opts[:chain_id]` (padrão brdc-devnet) e `opts[:bootstrap]`: função `índice -> {host, porta}` que diz onde achar
  # cada validador (o laboratório Docker usa o nome do serviço). Sem ela, a gênese não leva pares de partida.
  defp create_genesis(dir, path, n, opts) do
    pub = fn role ->
      {:ok, key} = Keygen.load_public(Path.join(dir, role <> ".pub"))
      key
    end

    with {:ok, g} <-
           Genesis.new(
             chain_id: opts[:chain_id] || "brdc-devnet",
             validators: Enum.map(validator_roles(n), pub),
             bootstrap: bootstrap(n, opts[:bootstrap], pub),
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

  defp bootstrap(_n, nil, _pub), do: []

  defp bootstrap(n, where, pub) do
    for i <- 1..n do
      {host, port} = where.(i)
      %{validator: pub.("v#{i}"), host: host, port: port}
    end
  end
end
