defmodule BrdcConsensus.Engine do
  @moduledoc """
  Motor BFT de **uma altura** (Fase 3), no desenho Tendermint, **sem I/O**: recebe eventos e
  devolve ações. Não abre soquete, não lê relógio, não usa acaso. Quem o roda (o nó, ou o
  simulador) entrega mensagens, dispara os tempos-limite e executa as ações.

  ## Eventos (`handle/2`)
  `{:proposal, %Proposal{}}`, `{:vote, %Vote{}}`, `{:block, bloco}` (resposta a `:need_block`),
  `{:timeout, :propose | :prevote | :precommit, rodada}`.

  ## Ações devolvidas
  - `{:broadcast, %Proposal{} | %Vote{}}`: enviar a todos os outros validadores
  - `{:schedule_timeout, passo, rodada}`: quem roda dispara `{:timeout, passo, rodada}` depois do prazo
  - `{:need_block, rodada}`: sou o proponente; entregue um bloco com `{:block, bloco}`
  - `{:decide, bloco, %Certificate{}}`: **bloco final** com o certificado de commit
  - `{:evidence, {voto_a, voto_b}}`: um validador votou em dois blocos na mesma rodada (equivocação)

  ## Regras (resumo)
  Rodada = proposta → prevote → precommit. Mais de 2/3 de prevotes no mesmo bloco **travam**
  o validador nele (só destrava com prova de uma rodada mais nova); mais de 2/3 de precommits
  num bloco o tornam **final**. Tempo-limite sem progresso passa para a rodada seguinte, com
  outro proponente. Isso garante que **dois blocos diferentes nunca ficam finais na mesma
  altura** com até 1/3 de bizantinos.
  """
  alias BrdcConsensus.{Certificate, Proposal, Vote}

  @type step :: :propose | :prevote | :precommit

  @enforce_keys [:chain_id, :height, :validators, :seed, :pub, :hash_fn, :valid_fn]
  defstruct [
    :chain_id,
    :height,
    :validators,
    :seed,
    :pub,
    :hash_fn,
    :valid_fn,
    round: 0,
    step: :propose,
    locked: nil,
    valid: nil,
    proposals: %{},
    blocks: %{},
    votes: %{},
    fired: MapSet.new(),
    decision: nil,
    out: []
  ]

  @doc """
  Cria o motor. Opções: `:chain_id`, `:height`, `:validators` (lista ordenada de chaves
  públicas, poder igual), `:seed` (chave privada deste validador), `:hash_fn` (bloco → 32
  bytes) e `:valid_fn` (bloco → boolean, a validação do ledger).
  """
  @spec new(keyword()) :: %__MODULE__{}
  def new(opts) do
    seed = Keyword.fetch!(opts, :seed)

    %__MODULE__{
      chain_id: Keyword.fetch!(opts, :chain_id),
      height: Keyword.fetch!(opts, :height),
      validators: Keyword.fetch!(opts, :validators),
      seed: seed,
      pub: BrdcCrypto.Ed25519.public_key(seed),
      hash_fn: Keyword.fetch!(opts, :hash_fn),
      valid_fn: Keyword.fetch!(opts, :valid_fn)
    }
  end

  @doc "Proponente da rodada: rodízio determinístico entre os validadores."
  @spec proposer(%__MODULE__{}, non_neg_integer()) :: <<_::256>>
  def proposer(%__MODULE__{validators: vs, height: h}, round),
    do: Enum.at(vs, rem(h + round, length(vs)))

  @doc "Começa a altura (rodada 0)."
  @spec start(%__MODULE__{}) :: {%__MODULE__{}, [term()]}
  def start(%__MODULE__{} = e), do: e |> start_round(0) |> settle() |> flush()

  @doc "Trata um evento."
  @spec handle(%__MODULE__{}, term()) :: {%__MODULE__{}, [term()]}
  def handle(%__MODULE__{decision: d} = e, _event) when d != nil, do: {e, []}
  def handle(e, event), do: e |> event(event) |> settle() |> flush()

  @doc "Decisão tomada, se houver."
  @spec decision(%__MODULE__{}) :: nil | {term(), Certificate.t()}
  def decision(%__MODULE__{decision: d}), do: d

  # --- eventos ------------------------------------------------------------

  defp event(e, {:proposal, %Proposal{} = p}), do: ingest_proposal(e, p)
  defp event(e, {:vote, %Vote{} = v}), do: ingest_vote(e, v)

  defp event(e, {:block, block}) do
    if e.step == :propose and proposer(e, e.round) == e.pub and not own_proposal?(e) do
      hash = e.hash_fn.(block)
      propose(e, block, hash, -1)
    else
      e
    end
  end

  defp event(%{round: r, step: :propose} = e, {:timeout, :propose, r}),
    do: cast(%{e | step: :prevote}, :prevote, nil)

  defp event(%{round: r, step: :prevote} = e, {:timeout, :prevote, r}),
    do: cast(%{e | step: :precommit}, :precommit, nil)

  defp event(%{round: r} = e, {:timeout, :precommit, r}), do: start_round(e, r + 1)
  defp event(e, _), do: e

  # --- rodadas --------------------------------------------------------------

  defp start_round(e, r) do
    e = %{e | round: r, step: :propose}

    if proposer(e, r) == e.pub do
      case e.valid do
        {hash, vr} -> propose(e, Map.fetch!(e.blocks, hash), hash, vr)
        nil -> emit(e, {:need_block, r})
      end
    else
      emit(e, {:schedule_timeout, :propose, r})
    end
  end

  defp own_proposal?(e), do: Map.has_key?(e.proposals, e.round)

  defp propose(e, block, hash, valid_round) do
    p = Proposal.sign(e.chain_id, e.height, e.round, valid_round, block, hash, e.seed)
    e |> ingest_proposal(p) |> emit({:broadcast, p})
  end

  defp cast(e, type, hash) do
    v = Vote.sign(e.chain_id, type, e.height, e.round, hash, e.seed)
    e |> ingest_vote(v) |> emit({:broadcast, v})
  end

  # --- entrada de mensagens ---------------------------------------------------

  defp ingest_proposal(e, %Proposal{} = p) do
    cond do
      p.height != e.height ->
        e

      Map.has_key?(e.proposals, p.round) ->
        e

      p.proposer != proposer(e, p.round) ->
        e

      not Proposal.valid?(e.chain_id, p) ->
        e

      e.hash_fn.(p.block) != p.block_hash ->
        e

      true ->
        %{
          e
          | proposals: Map.put(e.proposals, p.round, p),
            blocks: Map.put(e.blocks, p.block_hash, p.block)
        }
    end
  end

  defp ingest_vote(e, %Vote{} = v) do
    key = {v.type, v.round}
    existing = e.votes |> Map.get(key, %{}) |> Map.get(v.voter)

    cond do
      v.height != e.height ->
        e

      v.voter not in e.validators ->
        e

      not Vote.valid?(e.chain_id, v) ->
        e

      existing == nil ->
        %{e | votes: Map.update(e.votes, key, %{v.voter => v}, &Map.put(&1, v.voter, v))}

      existing.block_hash != v.block_hash ->
        emit(e, {:evidence, {existing, v}})

      true ->
        e
    end
  end

  # --- regras, até não haver mais nada a fazer ----------------------------------

  defp settle(%{decision: d} = e) when d != nil, do: e

  defp settle(e) do
    case rule(e) do
      nil -> e
      e2 -> settle(e2)
    end
  end

  defp rule(e) do
    commit_rule(e) || skip_round_rule(e) || propose_rules(e) || prevote_rules(e) ||
      precommit_rules(e)
  end

  defp n(e), do: length(e.validators)
  defp quorum?(e, count), do: Certificate.quorum?(count, n(e))
  defp count(e, type, round), do: e.votes |> Map.get({type, round}, %{}) |> map_size()

  defp count_for(e, type, round, hash) do
    e.votes |> Map.get({type, round}, %{}) |> Map.values() |> Enum.count(&(&1.block_hash == hash))
  end

  defp once(e, flag) do
    if MapSet.member?(e.fired, flag), do: nil, else: %{e | fired: MapSet.put(e.fired, flag)}
  end

  # Mais de 2/3 de precommits num bloco que conhecemos, em qualquer rodada: decide.
  defp commit_rule(e) do
    Enum.find_value(e.proposals, fn {r, p} ->
      if quorum?(e, count_for(e, :precommit, r, p.block_hash)) and e.valid_fn.(p.block) do
        votes =
          e.votes
          |> Map.get({:precommit, r}, %{})
          |> Map.values()
          |> Enum.filter(&(&1.block_hash == p.block_hash))

        cert = %Certificate{height: e.height, round: r, block_hash: p.block_hash, votes: votes}
        emit(%{e | decision: {p.block, cert}}, {:decide, p.block, cert})
      end
    end)
  end

  # Mais de 1/3 dos validadores já estão numa rodada mais nova: pular para lá.
  defp skip_round_rule(e) do
    ahead =
      e.votes
      |> Enum.filter(fn {{_t, r}, _} -> r > e.round end)
      |> Enum.group_by(fn {{_t, r}, _} -> r end, fn {_, m} -> Map.keys(m) end)
      |> Enum.map(fn {r, lists} -> {r, lists |> List.flatten() |> Enum.uniq() |> length()} end)
      |> Enum.filter(fn {_r, c} -> c * 3 > n(e) end)
      |> Enum.map(&elem(&1, 0))

    case ahead do
      [] -> nil
      rs -> start_round(e, Enum.min(rs))
    end
  end

  # Prevotar na proposta da rodada atual (regras de bloqueio do Tendermint).
  defp propose_rules(%{step: :propose} = e) do
    with %Proposal{} = p <- Map.get(e.proposals, e.round) do
      ok? = e.valid_fn.(p.block)

      vote_for? =
        ok? and
          if p.valid_round == -1 do
            locked_ok?(e, p.block_hash, -1)
          else
            p.valid_round < e.round and
              quorum?(e, count_for(e, :prevote, p.valid_round, p.block_hash)) and
              locked_ok?(e, p.block_hash, p.valid_round)
          end

      cast(%{e | step: :prevote}, :prevote, if(vote_for?, do: p.block_hash, else: nil))
    end
  end

  defp propose_rules(_), do: nil

  defp locked_ok?(%{locked: nil}, _hash, _vr), do: true
  defp locked_ok?(%{locked: {h, _}}, hash, _vr) when h == hash, do: true
  defp locked_ok?(%{locked: {_, lr}}, _hash, vr), do: lr <= vr

  defp prevote_rules(e), do: prevote_timeout_rule(e) || lock_rule(e) || nil_prevotes_rule(e)

  # mais de 2/3 de prevotes de qualquer tipo: começa a contar o prazo do prevote
  defp prevote_timeout_rule(%{step: :prevote, round: r} = e) do
    with true <- quorum?(e, count(e, :prevote, r)),
         %{} = e2 <- once(e, {:prevote_timeout, r}) do
      emit(e2, {:schedule_timeout, :prevote, r})
    else
      _ -> nil
    end
  end

  defp prevote_timeout_rule(_), do: nil

  # proposta + mais de 2/3 de prevotes nela: guarda como válido e, se ainda em prevote, trava e dá precommit
  defp lock_rule(%{round: r, step: step} = e) when step in [:prevote, :precommit] do
    with %Proposal{} = p <- Map.get(e.proposals, r),
         true <- e.valid_fn.(p.block),
         true <- quorum?(e, count_for(e, :prevote, r, p.block_hash)),
         %{} = e2 <- once(e, {:lock, r}) do
      e2 = %{e2 | valid: {p.block_hash, r}}

      if step == :prevote do
        cast(%{e2 | locked: {p.block_hash, r}, step: :precommit}, :precommit, p.block_hash)
      else
        e2
      end
    else
      _ -> nil
    end
  end

  defp lock_rule(_), do: nil

  # mais de 2/3 de prevotes nulos: precommit nulo
  defp nil_prevotes_rule(%{step: :prevote, round: r} = e) do
    if quorum?(e, count_for(e, :prevote, r, nil)) do
      cast(%{e | step: :precommit}, :precommit, nil)
    end
  end

  defp nil_prevotes_rule(_), do: nil

  # mais de 2/3 de precommits de qualquer tipo: começa a contar o prazo do precommit
  defp precommit_rules(%{round: r} = e) do
    with true <- quorum?(e, count(e, :precommit, r)),
         %{} = e2 <- once(e, {:precommit_timeout, r}) do
      emit(e2, {:schedule_timeout, :precommit, r})
    else
      _ -> nil
    end
  end

  # --- ações --------------------------------------------------------------------

  defp emit(e, action), do: %{e | out: [action | e.out]}
  defp flush(e), do: {%{e | out: []}, Enum.reverse(e.out)}

  defimpl Inspect do
    def inspect(e, _),
      do: "#BrdcConsensus.Engine<h=#{e.height} r=#{e.round} #{e.step}, seed: [REDACTED]>"
  end
end
