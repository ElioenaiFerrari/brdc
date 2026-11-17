defmodule BrdcNode.Genesis do
  @moduledoc """
  Documento de gênese da rede (Fase 4): o que todos os nós precisam **concordar** antes de
  começar. Sua **impressão digital** (`hash/1`) entra no `hello` do canal: nós com gênese
  diferente se recusam.

  Conteúdo: `chain_id`, validadores (ordem importa: define o rodízio de proponentes), emissores
  e limite M-de-N, tabela de taxas e limites de bloco (ADR-0014) e a **lista de
  partida** (`bootstrap`: onde achar os primeiros pares). Não contém segredo nenhum.

  O arquivo é JSON legível (`to_json/1`); o hash é calculado sobre a **codificação determinística**
  dos campos (ADR-0011), não sobre os bytes do JSON, então formatação não muda a rede.
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.Params
  alias BrdcP2p.AddressRecord

  @enforce_keys [:chain_id, :validators, :issuers, :threshold]
  defstruct [
    :chain_id,
    :validators,
    :issuers,
    :threshold,
    transfer_base: 1_000,
    per_byte: 1,
    max_block_txs: 1_000,
    max_block_bytes: 1_000_000,
    contest_window: 86_400,
    veto_window: 172_800,
    min_window: 60,
    max_window: 31_536_000,
    authorities: [],
    authority_threshold: 1,
    asset_register_fee: 50_000,
    asset_step_fee: 20_000,
    credential_fee: 10_000,
    contract_fee: 10_000,
    bootstrap: []
  ]

  @type bootstrap :: %{validator: <<_::256>>, host: String.t(), port: pos_integer()}
  @type t :: %__MODULE__{}

  @max_u64 0xFFFFFFFFFFFFFFFF

  @doc "Cria e valida. Devolve `{:error, motivo}` com um átomo que diz o que está errado."
  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(opts) do
    g = struct!(__MODULE__, opts)

    with :ok <- check(g.chain_id =~ ~r/\A[A-Za-z0-9._-]{1,64}\z/, :bad_chain_id),
         :ok <- check_keys(g.validators, 1..64, :bad_validators),
         :ok <- check_keys(g.issuers, 1..32, :bad_issuers),
         :ok <-
           check(
             is_integer(g.threshold) and g.threshold >= 1 and g.threshold <= length(g.issuers),
             :bad_threshold
           ),
         :ok <- check(Enum.all?([g.transfer_base, g.per_byte], &u64?/1), :bad_fees),
         :ok <-
           check(pos_u64?(g.max_block_txs) and pos_u64?(g.max_block_bytes), :bad_block_limits),
         :ok <- check_windows(g),
         :ok <- check_authorities(g),
         :ok <-
           check(
             Enum.all?(
               [g.asset_register_fee, g.asset_step_fee, g.credential_fee, g.contract_fee],
               &u64?/1
             ),
             :bad_fees
           ),
         :ok <- check_bootstrap(g) do
      {:ok, g}
    end
  end

  @doc "Impressão digital da gênese (32 bytes); é o que o `hello` compara."
  @spec hash(t()) :: <<_::256>>
  def hash(%__MODULE__{} = g) do
    boot =
      Enum.map(
        g.bootstrap,
        &Encoding.encode([{:fixed, 32}, :string, :u32], [&1.validator, &1.host, &1.port])
      )

    Hash.tagged(
      "brdc/genesis",
      Encoding.encode(
        [
          :string,
          {:list, {:fixed, 32}},
          {:list, {:fixed, 32}},
          :u32,
          :u64,
          :u64,
          :u64,
          :u64,
          :u64,
          :u64,
          :u64,
          :u64,
          {:list, {:fixed, 32}},
          :u32,
          :u64,
          :u64,
          :u64,
          :u64,
          {:list, :bytes}
        ],
        [
          g.chain_id,
          g.validators,
          g.issuers,
          g.threshold,
          g.transfer_base,
          g.per_byte,
          g.max_block_txs,
          g.max_block_bytes,
          g.contest_window,
          g.veto_window,
          g.min_window,
          g.max_window,
          g.authorities,
          g.authority_threshold,
          g.asset_register_fee,
          g.asset_step_fee,
          g.credential_fee,
          g.contract_fee,
          boot
        ]
      )
    )
  end

  @doc "Parâmetros do ledger derivados da gênese."
  @spec ledger_params(t()) :: Params.t()
  def ledger_params(%__MODULE__{} = g) do
    {:ok, p} =
      Params.new(
        chain_id: g.chain_id,
        issuers: g.issuers,
        threshold: g.threshold,
        transfer_base: g.transfer_base,
        per_byte: g.per_byte,
        max_block_txs: g.max_block_txs,
        max_block_bytes: g.max_block_bytes,
        contest_window: g.contest_window,
        veto_window: g.veto_window,
        min_window: g.min_window,
        max_window: g.max_window,
        authorities: g.authorities,
        authority_threshold: g.authority_threshold,
        asset_register_fee: g.asset_register_fee,
        asset_step_fee: g.asset_step_fee,
        credential_fee: g.credential_fee,
        contract_fee: g.contract_fee
      )

    p
  end

  @doc """
  Configuração do canal P2P para o validador de semente `seed`. `validators` é uma função
  (o conjunto em vigor pode mudar por rotação); por padrão, o da gênese.
  """
  @spec channel_config(t(), <<_::256>>, (-> [<<_::256>>]) | nil) :: map()
  def channel_config(%__MODULE__{} = g, seed, validators \\ nil) do
    %{
      seed: seed,
      chain_id: g.chain_id,
      genesis_hash: hash(g),
      validators: validators || fn -> g.validators end
    }
  end

  # --- arquivo --------------------------------------------------------------------------

  @doc "JSON legível, com o hash incluído para conferir corrupção."
  @spec to_json(t()) :: binary()
  def to_json(%__MODULE__{} = g) do
    %{
      "chain_id" => g.chain_id,
      "genesis_hash" => hex(hash(g)),
      "validators" => Enum.map(g.validators, &hex/1),
      "issuers" => Enum.map(g.issuers, &hex/1),
      "authorities" => Enum.map(g.authorities, &hex/1),
      "authority_threshold" => g.authority_threshold,
      "issuer_threshold" => g.threshold,
      "fees" => %{
        "transfer_base" => g.transfer_base,
        "per_byte" => g.per_byte,
        "asset_register" => g.asset_register_fee,
        "asset_step" => g.asset_step_fee,
        "credential" => g.credential_fee,
        "contract" => g.contract_fee
      },
      "block_limits" => %{"max_txs" => g.max_block_txs, "max_bytes" => g.max_block_bytes},
      "windows_seconds" => %{
        "contest" => g.contest_window,
        "veto" => g.veto_window,
        "min" => g.min_window,
        "max" => g.max_window
      },
      "bootstrap" =>
        Enum.map(
          g.bootstrap,
          &%{"validator" => hex(&1.validator), "host" => &1.host, "port" => &1.port}
        )
    }
    |> JSON.encode!()
  end

  @doc "Lê o JSON, valida tudo de novo e confere o hash gravado."
  @spec from_json(binary()) :: {:ok, t()} | {:error, atom()}
  def from_json(text) when is_binary(text) do
    with {:ok, %{} = m} <- decode_json(text),
         {:ok, validators} <- unhex_list(m["validators"]),
         {:ok, issuers} <- unhex_list(m["issuers"]),
         {:ok, authorities} <- unhex_list(m["authorities"] || []),
         {:ok, bootstrap} <- parse_bootstrap(m["bootstrap"]),
         {:ok, g} <-
           new(
             chain_id: m["chain_id"],
             validators: validators,
             issuers: issuers,
             threshold: m["issuer_threshold"],
             transfer_base: get_in(m, ["fees", "transfer_base"]),
             per_byte: get_in(m, ["fees", "per_byte"]),
             asset_register_fee: get_in(m, ["fees", "asset_register"]),
             asset_step_fee: get_in(m, ["fees", "asset_step"]),
             credential_fee: get_in(m, ["fees", "credential"]),
             contract_fee: get_in(m, ["fees", "contract"]),
             authorities: authorities,
             authority_threshold: m["authority_threshold"],
             max_block_txs: get_in(m, ["block_limits", "max_txs"]),
             max_block_bytes: get_in(m, ["block_limits", "max_bytes"]),
             contest_window: get_in(m, ["windows_seconds", "contest"]),
             veto_window: get_in(m, ["windows_seconds", "veto"]),
             min_window: get_in(m, ["windows_seconds", "min"]),
             max_window: get_in(m, ["windows_seconds", "max"]),
             bootstrap: bootstrap
           ),
         :ok <- check(m["genesis_hash"] == hex(hash(g)), :hash_mismatch) do
      {:ok, g}
    else
      {:error, _} = e -> e
      _ -> {:error, :malformed}
    end
  end

  # --- util -------------------------------------------------------------------------------

  defp decode_json(text) do
    case JSON.decode(text) do
      {:ok, v} -> {:ok, v}
      {:error, _} -> {:error, :malformed}
    end
  end

  defp check_keys(keys, range, reason) do
    ok? =
      is_list(keys) and length(keys) in range and length(Enum.uniq(keys)) == length(keys) and
        Enum.all?(keys, &match?(<<_::256>>, &1))

    check(ok?, reason)
  end

  # autoridades raiz (criam classes de bens e tipos de credencial): podem não existir (0), mas
  # se existirem são distintas e o limite cabe no conjunto
  defp check_authorities(%{authorities: []}), do: :ok

  defp check_authorities(g) do
    check(
      check_keys(g.authorities, 1..16, :bad_authorities) == :ok and
        is_integer(g.authority_threshold) and g.authority_threshold >= 1 and
        g.authority_threshold <= length(g.authorities),
      :bad_authorities
    )
  end

  defp check_windows(g) do
    ws = [g.contest_window, g.veto_window, g.min_window, g.max_window]

    ok? =
      Enum.all?(ws, &pos_u64?/1) and g.min_window <= g.max_window and
        g.contest_window in g.min_window..g.max_window//1 and
        g.veto_window in g.min_window..g.max_window//1

    check(ok?, :bad_windows)
  end

  defp check_bootstrap(g) do
    ok? =
      is_list(g.bootstrap) and
        Enum.all?(g.bootstrap, fn
          %{validator: v, host: h, port: p} ->
            v in g.validators and AddressRecord.check_endpoint(h, p) == :ok

          _ ->
            false
        end)

    check(ok?, :bad_bootstrap)
  end

  defp parse_bootstrap(nil), do: {:ok, []}

  defp parse_bootstrap(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn
      %{"validator" => v, "host" => h, "port" => p}, {:ok, acc} ->
        case unhex(v) do
          {:ok, key} -> {:cont, {:ok, acc ++ [%{validator: key, host: h, port: p}]}}
          :error -> {:halt, {:error, :bad_bootstrap}}
        end

      _, _ ->
        {:halt, {:error, :bad_bootstrap}}
    end)
  end

  defp parse_bootstrap(_), do: {:error, :bad_bootstrap}

  defp unhex_list(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn s, {:ok, acc} ->
      case unhex(s) do
        {:ok, k} -> {:cont, {:ok, acc ++ [k]}}
        :error -> {:halt, {:error, :malformed}}
      end
    end)
  end

  defp unhex_list(_), do: {:error, :malformed}

  defp unhex(s) when is_binary(s) do
    case Base.decode16(s, case: :mixed) do
      {:ok, <<_::256>> = k} -> {:ok, k}
      _ -> :error
    end
  end

  defp unhex(_), do: :error

  defp hex(bin), do: Base.encode16(bin, case: :lower)
  defp u64?(n), do: is_integer(n) and n >= 0 and n <= @max_u64
  defp pos_u64?(n), do: u64?(n) and n > 0
  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
