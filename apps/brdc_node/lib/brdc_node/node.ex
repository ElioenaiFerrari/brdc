defmodule BrdcNode.Node do
  @moduledoc """
  Nó local de **um validador** (Fase 7, primeiro passo): guarda o estado do ledger, recebe transações,
  valida cada uma contra o estado **como ficaria com as pendentes** e produz blocos sem nunca produzir
  bloco vazio. Com um único validador, o bloco é decidido por ele mesmo (o motor BFT e a rede entre
  validadores ainda não estão ligados a este nó: é o passo seguinte).

  - **Mempool** em ordem de chegada (por conta, o nonce já impõe a ordem), com teto.
  - **Bloco** quando há transação pendente, depois de `block_interval_ms` (o intervalo de agrupamento é a
    decisão pendente P3; aqui é só um parâmetro). `:manual` desliga o relógio e os testes chamam `produce/1`.
  - **Horário do bloco** vem do relógio injetado e nunca decresce (ADR-0016).
  - As taxas vão para a conta do próprio validador.
  - **Disco** (ADR-0012): com `:data_dir`, cada bloco é gravado (com `sync`) **antes** de entrar no estado; ao subir,
    o nó relê o log e **reexecuta** cada bloco, conferindo a raiz de estado. Sem `:data_dir`, tudo fica em memória.
    Também guarda as propostas dos órgãos (`proposals.bin`, descartáveis) e o hash da gênese (`genesis.hash`),
    que impede abrir o disco de outra rede.
  """
  use GenServer
  alias BrdcConsensus.Certificate
  alias BrdcCrypto.{Address, Ed25519, Encoding}
  alias BrdcLedger.{Block, Executor, State, Tx}
  alias BrdcNode.BlockStore.File, as: LogFile
  alias BrdcNode.{Genesis, Proposals}
  require Logger

  @max_mempool 10_000

  # --- API ---------------------------------------------------------------------------------

  @doc """
  Opções: `:genesis` (`BrdcNode.Genesis`), `:seed` (chave do validador, 32 bytes), `:block_interval_ms`
  (padrão 1000, ou `:manual`), `:clock` (`fn -> segundos end`), `:name`, `:data_dir` (pasta do disco; sem ela, tudo em memória).
  """
  def start_link(opts) do
    {gen, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen)
  end

  @doc "Estado público do nó."
  @spec status(GenServer.server()) :: map()
  def status(node), do: GenServer.call(node, :status)

  @doc "Saldo e nonce de um endereço (hash de 32 bytes). `pending: true` considera as pendentes."
  @spec account(GenServer.server(), <<_::256>>, keyword()) :: %{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }
  def account(node, addr, opts \\ []),
    do: GenServer.call(node, {:account, addr, Keyword.get(opts, :pending, false)})

  @doc """
  Contratos entre partes de um endereço (como parte A ou B), do estado **confirmado**.
  """
  @spec contracts_of(GenServer.server(), <<_::256>>) :: [map()]
  def contracts_of(node, addr), do: GenServer.call(node, {:contracts_of, addr})

  @doc "Credenciais cujo titular é o endereço (estado confirmado)."
  @spec credentials_of(GenServer.server(), <<_::256>>) :: [map()]
  def credentials_of(node, addr), do: GenServer.call(node, {:credentials_of, addr})

  @doc "Bens de um endereço: os que ele possui e os que ele está comprando (com a negociação, se houver)."
  @spec assets_of(GenServer.server(), <<_::256>>) :: [map()]
  def assets_of(node, addr), do: GenServer.call(node, {:assets_of, addr})

  @doc "Tipos de credencial cujo órgão inclui a chave pública `pub` (quem pode assinar emissões)."
  @spec types_for(GenServer.server(), <<_::256>>) :: [map()]
  def types_for(node, pub), do: GenServer.call(node, {:types_for, pub})

  @doc "Propõe uma emissão de credencial para assinatura coletiva (os campos; o documento é recalculado)."
  @spec propose(GenServer.server(), Proposals.fields()) :: {:ok, <<_::256>>} | {:error, atom()}
  def propose(node, fields), do: propose(node, :credential_issue, fields)

  @doc "Propõe uma ação de órgão (`Proposals.kinds/0`) para assinatura coletiva."
  @spec propose(GenServer.server(), Proposals.kind(), Proposals.fields()) ::
          {:ok, <<_::256>>} | {:error, atom()}
  def propose(node, kind, fields), do: GenServer.call(node, {:propose, kind, fields})

  @doc "Credenciais dos tipos cujo órgão inclui a chave pública (para propor veto e revogação)."
  @spec organ_credentials(GenServer.server(), <<_::256>>) :: [map()]
  def organ_credentials(node, pub), do: GenServer.call(node, {:organ_credentials, pub})

  @doc """
  Oferta e reserva (estado confirmado): quanto foi emitido, queimado, e o último atestado de reserva dos emissores
  (`nil` se nunca houve). A cobertura é só informação: a rede não prova a reserva em reais (ADR-0009).
  """
  @spec supply_info(GenServer.server()) :: map()
  def supply_info(node), do: GenServer.call(node, :supply_info)

  @doc "Classes de bens cujo órgão inclui a chave pública."
  @spec classes_for(GenServer.server(), <<_::256>>) :: [map()]
  def classes_for(node, pub), do: GenServer.call(node, {:classes_for, pub})

  @doc "Bens das classes cujo órgão inclui a chave pública (para propor veto e gravames)."
  @spec organ_assets(GenServer.server(), <<_::256>>) :: [map()]
  def organ_assets(node, pub), do: GenServer.call(node, {:organ_assets, pub})

  @doc "Aprovação de um membro (`chave ‖ assinatura`) a uma proposta. Devolve quantas aprovações há."
  @spec approve(GenServer.server(), <<_::256>>, binary()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def approve(node, id, approval), do: GenServer.call(node, {:approve, id, approval})

  @doc "Propostas abertas dos órgãos de que a chave faz parte, com as aprovações e o limite."
  @spec proposals_for(GenServer.server(), <<_::256>>) :: [map()]
  def proposals_for(node, pub), do: GenServer.call(node, {:proposals_for, pub})

  @doc "Recebe uma transação já assinada (bytes). Devolve o id ou o motivo da recusa."
  @spec submit(GenServer.server(), binary()) :: {:ok, <<_::256>>} | {:error, atom()}
  def submit(node, bin) when is_binary(bin), do: GenServer.call(node, {:submit, bin})

  @doc "Produz um bloco agora, se houver transação pendente (testes e modo manual)."
  @spec produce(GenServer.server()) :: {:ok, pos_integer()} | :nothing
  def produce(node), do: GenServer.call(node, :produce)

  @doc """
  Modo de **vários validadores** (M2, ADR-0027): monta a proposta de bloco com as transações do mempool, **sem**
  confirmá-la. O cabeçalho leva como `signers` o conjunto de validadores em vigor. `:nothing` se não há o que propor.
  """
  @spec build_proposal(GenServer.server()) :: {:ok, Block.t()} | :nothing
  def build_proposal(node), do: GenServer.call(node, :build_proposal)

  @doc """
  Confere um bloco recebido (como cada validador faz antes de dar prevote): cabeçalho de assinantes, horário
  plausível (`now` em segundos) e **execução completa** sobre o estado confirmado, sem alterá-lo.
  """
  @spec check_block(GenServer.server(), Block.t(), non_neg_integer()) :: :ok | {:error, term()}
  def check_block(node, block, now), do: GenServer.call(node, {:check_block, block, now})

  @doc """
  Confirma um bloco **decidido** pelo consenso: confere o certificado de commit (mais de 2/3 dos validadores,
  assinaturas e hash do bloco), executa, grava com o certificado e limpa o mempool. Idempotente para o bloco
  que já está confirmado.
  """
  @spec commit_block(GenServer.server(), Block.t(), Certificate.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def commit_block(node, block, cert), do: GenServer.call(node, {:commit_block, block, cert})

  @doc "Blocos confirmados a partir de `from`, no máximo `max`, com o certificado de cada um (sincronização)."
  @spec blocks_from(GenServer.server(), pos_integer(), pos_integer()) ::
          [{Block.t(), Certificate.t() | nil}]
  def blocks_from(node, from, max), do: GenServer.call(node, {:blocks_from, from, max})

  @doc "Quem recebe `{:brdc_tx, bytes}` a cada transação **nova** aceita no mempool (para espalhar aos pares)."
  @spec set_tx_hook(GenServer.server(), pid() | nil) :: :ok
  def set_tx_hook(node, pid), do: GenServer.call(node, {:tx_hook, pid})

  @doc "Quem se inscreve recebe `{:brdc_block, altura, [txid]}` a cada bloco."
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(node), do: GenServer.call(node, {:subscribe, self()})

  @doc "O bloco de uma altura (os últimos 1.000 ficam na memória)."
  @spec block(GenServer.server(), pos_integer()) :: {:ok, Block.t()} | :error
  def block(node, height), do: GenServer.call(node, {:block, height})

  # --- servidor ------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    genesis = Keyword.fetch!(opts, :genesis)
    seed = Keyword.fetch!(opts, :seed)
    state0 = genesis |> Genesis.ledger_params() |> State.new()

    base = %{
      genesis: genesis,
      seed: seed,
      proposer: Address.hash(Ed25519.public_key(seed)),
      mempool: [],
      blocks: %{},
      proposals: Proposals.new(),
      interval: Keyword.get(opts, :block_interval_ms, 1_000),
      clock: Keyword.get(opts, :clock, fn -> System.os_time(:second) end),
      timer: nil,
      subscribers: %{},
      certs: %{},
      tx_hook: nil,
      store: nil,
      data_dir: nil
    }

    case recover(base, state0, Keyword.get(opts, :data_dir)) do
      {:ok, s, state} -> {:ok, Map.merge(s, %{state: state, pending_state: state})}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{store: %LogFile{} = store}), do: LogFile.close(store)
  def terminate(_reason, _s), do: :ok

  @impl true
  def handle_call(:status, _from, s) do
    st = s.state

    {:reply,
     %{
       chain_id: st.params.chain_id,
       height: st.height,
       time: st.time,
       supply: State.supply(st),
       last_hash: st.last_hash,
       pending: length(s.mempool),
       transfer_base: st.params.transfer_base,
       per_byte: st.params.per_byte,
       contract_fee: st.params.contract_fee,
       credential_fee: st.params.credential_fee,
       asset_step_fee: st.params.asset_step_fee,
       asset_register_fee: st.params.asset_register_fee,
       genesis_hash: Genesis.hash(s.genesis)
     }, s}
  end

  def handle_call({:account, addr, pending?}, _from, s) do
    st = if pending?, do: s.pending_state, else: s.state
    {:reply, State.account(st, addr), s}
  end

  def handle_call({:contracts_of, addr}, _from, s) do
    list =
      for {id, c} <- Enum.sort(s.state.contracts), c.a == addr or c.b == addr do
        Map.put(c, :id, id)
      end

    {:reply, list, s}
  end

  def handle_call({:credentials_of, addr}, _from, s) do
    {:reply,
     for({id, c} <- Enum.sort(s.state.credentials), c.subject == addr, do: Map.put(c, :id, id)),
     s}
  end

  def handle_call({:assets_of, addr}, _from, s) do
    st = s.state

    mine =
      for {id, a} <- Enum.sort(st.assets), a.owner == addr or buying?(st.deals[id], addr) do
        asset_view(st, id, a, if(a.owner == addr, do: "owner", else: "buyer"))
      end

    {:reply, mine, s}
  end

  def handle_call({:types_for, pub}, _from, s) do
    {:reply,
     for({id, t} <- Enum.sort(s.state.cred_types), pub in t.organ, do: Map.put(t, :id, id)), s}
  end

  def handle_call({:propose, kind, fields}, _from, s) do
    case Proposals.put(s.proposals, view(s), kind, fields) do
      {:ok, store, id} -> {:reply, {:ok, id}, save_proposals(%{s | proposals: store})}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call(:supply_info, _from, s) do
    st = s.state

    {:reply,
     %{
       minted: st.minted,
       burned: st.burned,
       supply: State.supply(st),
       attestation: st.attestation
     }, s}
  end

  def handle_call({:organ_credentials, pub}, _from, s) do
    st = s.state

    mine =
      for {id, c} <- Enum.sort(st.credentials), pub in st.cred_types[c.type].organ do
        Map.put(c, :id, id)
      end

    {:reply, mine, s}
  end

  def handle_call({:classes_for, pub}, _from, s) do
    {:reply, for({id, c} <- Enum.sort(s.state.classes), pub in c.organ, do: Map.put(c, :id, id)),
     s}
  end

  def handle_call({:organ_assets, pub}, _from, s) do
    st = s.state

    mine =
      for {id, a} <- Enum.sort(st.assets), pub in st.classes[a.class].organ do
        asset_view(st, id, a, "class")
      end

    {:reply, mine, s}
  end

  def handle_call({:approve, id, approval}, _from, s) do
    case Proposals.approve(s.proposals, view(s), id, approval) do
      {:ok, store, n} -> {:reply, {:ok, n}, save_proposals(%{s | proposals: store})}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:proposals_for, pub}, _from, s) do
    {:reply, Proposals.list_for(s.proposals, view(s), pub), s}
  end

  def handle_call({:submit, bin}, _from, s) do
    with {:ok, tx} <- Tx.decode(bin),
         :ok <- check(length(s.mempool) < @max_mempool, :mempool_full),
         :ok <- check(not Enum.any?(s.mempool, &(Tx.id(&1) == Tx.id(tx))), :duplicate),
         {:ok, pending, _fee} <- Executor.apply_tx(at_next_block(s), tx) do
      s = %{s | mempool: s.mempool ++ [tx], pending_state: pending}
      if s.tx_hook, do: send(s.tx_hook, {:brdc_tx, bin})
      {:reply, {:ok, Tx.id(tx)}, arm(s)}
    else
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:tx_hook, pid}, _from, s), do: {:reply, :ok, %{s | tx_hook: pid}}

  def handle_call(:build_proposal, _from, s), do: {:reply, proposal(s), s}

  def handle_call({:check_block, block, now}, _from, s),
    do: {:reply, check_proposed(s, block, now), s}

  def handle_call({:commit_block, block, cert}, _from, s) do
    case commit_decided(s, block, cert) do
      {:ok, s2, height} -> {:reply, {:ok, height}, s2}
      {:already, s2} -> {:reply, {:ok, block.height}, s2}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:blocks_from, from, max}, _from, s) do
    list =
      for h <- from..(from + max - 1)//1, {:ok, b} <- [Map.fetch(s.blocks, h)] do
        {b, Map.get(s.certs, h)}
      end

    {:reply, list, s}
  end

  def handle_call(:produce, _from, s) do
    case produce_block(s) do
      {:ok, s2, height} -> {:reply, {:ok, height}, s2}
      {:nothing, s2} -> {:reply, :nothing, s2}
    end
  end

  def handle_call({:subscribe, pid}, _from, s) do
    ref = Process.monitor(pid)
    {:reply, :ok, %{s | subscribers: Map.put(s.subscribers, ref, pid)}}
  end

  def handle_call({:block, height}, _from, s) do
    {:reply, Map.fetch(s.blocks, height), s}
  end

  @impl true
  def handle_info(:produce, s) do
    s = %{s | timer: nil}

    case produce_block(s) do
      {:ok, s2, _} -> {:noreply, arm(s2)}
      {:nothing, s2} -> {:noreply, s2}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _}, s),
    do: {:noreply, %{s | subscribers: Map.delete(s.subscribers, ref)}}

  def handle_info(_msg, s), do: {:noreply, s}

  # --- produção de blocos ----------------------------------------------------------------------

  # só arma o relógio se há o que produzir e ainda não há relógio armado
  defp arm(%{interval: :manual} = s), do: s
  defp arm(%{mempool: []} = s), do: s

  defp arm(%{timer: t} = s) when t != nil, do: s
  defp arm(s), do: %{s | timer: Process.send_after(self(), :produce, s.interval)}

  defp asset_view(st, id, a, role) do
    %{
      id: id,
      class: a.class,
      meta: a.meta,
      rev: a.rev,
      owner: a.owner,
      lien_ids: a.liens |> Map.keys() |> Enum.sort(),
      lien_refs: a.liens |> Enum.sort() |> Enum.map(&elem(&1, 1)),
      role: role,
      deal: st.deals[id],
      veto_window: st.classes[a.class].veto_window
    }
  end

  defp buying?(nil, _addr), do: false
  defp buying?(deal, addr), do: deal.buyer == addr

  # sem blocos vazios, o horário do último bloco fica parado; o próximo bloco usa o relógio (nunca menos que o último).
  # A transação é conferida nesse horário (senão uma janela já vencida pareceria aberta).
  # estado confirmado no horário do próximo bloco (para propostas com prazo, como o veto)
  defp view(s), do: %{s.state | time: max(s.clock.(), s.state.time)}

  defp at_next_block(s), do: %{s.pending_state | time: max(s.clock.(), s.state.time)}

  defp produce_block(%{mempool: []} = s), do: {:nothing, s}

  defp produce_block(s) do
    {txs, rest} = take(s.mempool, s.state.params)
    time = max(s.clock.(), s.state.time)

    case Block.build(s.state, s.proposer, [s.proposer], txs, time) do
      {:ok, block, new_state} ->
        commit(s, block, nil, new_state, rest)

      {:error, {:invalid_tx, id, _reason}} ->
        # não deveria acontecer (cada tx foi validada ao entrar); descarta a ofensora e tenta de novo
        s = %{s | mempool: Enum.reject(s.mempool, &(Tx.id(&1) == id))}
        s = %{s | pending_state: replay(s.state, s.mempool)}
        produce_block(s)

      {:error, _} ->
        {:nothing, s}
    end
  end

  # grava no disco ANTES de o bloco entrar no estado: se a gravação falhar, nada mudou e as transações seguem
  # no mempool (o erro vai para o log; o operador age)
  defp commit(s, block, cert, new_state, rest) do
    case persist_block(s, block, cert) do
      :ok ->
        {kept, pending} = prune_mempool(new_state, rest)
        s = %{s | state: new_state, mempool: kept, blocks: keep(s.blocks, block)}
        s = %{s | certs: keep_cert(s.certs, block.height, cert)}
        s = %{s | proposals: Proposals.prune(s.proposals, new_state)}
        persist_proposals(s)
        s = %{s | pending_state: pending}
        notify(s, block)
        {:ok, s, block.height}

      {:error, reason} ->
        Logger.error("não consegui gravar o bloco #{block.height} no disco: #{inspect(reason)}")
        {:nothing, s}
    end
  end

  # as pendentes que ainda valem sobre o novo estado (as que ficaram inválidas, por exemplo por nonce já usado,
  # saem), mais o estado "com as pendentes"
  defp prune_mempool(state, txs) do
    Enum.reduce(txs, {[], state}, fn tx, {kept, acc} ->
      case Executor.apply_tx(acc, tx) do
        {:ok, next, _fee} -> {kept ++ [tx], next}
        {:error, _} -> {kept, acc}
      end
    end)
  end

  defp keep_cert(certs, _h, nil), do: certs
  defp keep_cert(certs, h, cert), do: certs |> Map.put(h, cert) |> Map.delete(h - 1_000)

  # --- vários validadores: proposta, conferência e confirmação com certificado ------------------------

  # signers do cabeçalho = endereços de todos os validadores em vigor, em ordem (ADR-0027)
  defp signers(s), do: s.genesis.validators |> Enum.map(&Address.hash/1) |> Enum.sort()

  defp proposal(%{mempool: []}), do: :nothing

  defp proposal(s) do
    {txs, _rest} = take(s.mempool, s.state.params)
    time = max(s.clock.(), s.state.time)

    case Block.build(s.state, s.proposer, signers(s), txs, time) do
      {:ok, block, _state} -> {:ok, block}
      {:error, _} -> :nothing
    end
  end

  defp check_proposed(s, block, now) do
    with :ok <- check(block.signers == signers(s), :bad_signers),
         :ok <- check(Block.plausible_time?(block.time, s.state.time, now), :implausible_time),
         {:ok, _state} <- Block.apply(s.state, block) do
      :ok
    end
  end

  defp commit_decided(s, block, cert) do
    if block.height <= s.state.height,
      do: already_committed(s, block),
      else: commit_new(s, block, cert)
  end

  # já confirmado: só é idempotente se for o MESMO bloco
  defp already_committed(s, block) do
    if same_block?(Map.get(s.blocks, block.height), block),
      do: {:already, s},
      else: {:error, :conflicting_block}
  end

  defp commit_new(s, block, cert) do
    with :ok <- check(cert != nil and cert.block_hash == Block.hash(block), :cert_hash_mismatch),
         :ok <- check(cert.height == block.height, :cert_height_mismatch),
         :ok <- Certificate.verify(cert, s.state.params.chain_id, s.genesis.validators),
         :ok <- check(block.signers == signers(s), :bad_signers),
         {:ok, new_state} <- Block.apply(s.state, block) do
      ids = MapSet.new(block.txs, &Tx.id/1)
      rest = Enum.reject(s.mempool, &MapSet.member?(ids, Tx.id(&1)))

      case commit(s, block, cert, new_state, rest) do
        {:ok, s2, h} -> {:ok, s2, h}
        {:nothing, _} -> {:error, :disk}
      end
    end
  end

  defp same_block?(nil, _block), do: false
  defp same_block?(a, b), do: Block.hash(a) == Block.hash(b)

  defp save_proposals(s) do
    persist_proposals(s)
    s
  end

  defp persist_block(%{store: nil}, _block, _cert), do: :ok

  defp persist_block(%{store: store}, block, cert),
    do: LogFile.append(store, record(block, cert))

  # registro novo: `0xFF ‖ 1 ‖ [bloco, certificado (vazio se não há)]`; os da M1 eram só o bloco
  defp record(block, cert) do
    cert_bin = if cert, do: Certificate.encode(cert), else: <<>>
    <<0xFF, 1>> <> Encoding.encode([:bytes, :bytes], [Block.encode(block), cert_bin])
  end

  defp parse_record(<<0xFF, 1, rest::binary>>) do
    with {:ok, [block_bin, cert_bin]} <- Encoding.decode([:bytes, :bytes], rest),
         {:ok, block} <- Block.decode(block_bin),
         {:ok, cert} <- parse_cert(cert_bin) do
      {:ok, block, cert}
    else
      _ -> {:error, :malformed}
    end
  end

  defp parse_record(old) do
    with {:ok, block} <- Block.decode(old), do: {:ok, block, nil}
  end

  defp parse_cert(<<>>), do: {:ok, nil}
  defp parse_cert(bin), do: Certificate.decode(bin)

  # --- disco: replay ao subir e propostas ----------------------------------------------------------

  defp recover(s, state, nil), do: {:ok, s, state}

  defp recover(s, state, dir) do
    with :ok <- File.mkdir_p(dir),
         :ok <- check_genesis(dir, s.genesis),
         {:ok, store, records, recovery} <- LogFile.open(Path.join(dir, "blocks.log")),
         {:ok, state, blocks, certs} <- replay_blocks(s, state, records) do
      if recovery.truncated_bytes > 0,
        do:
          Logger.warning(
            "log de blocos: cauda rasgada descartada (#{recovery.truncated_bytes} bytes)"
          )

      s = %{s | store: store, data_dir: dir, blocks: blocks, certs: certs}
      {:ok, %{s | proposals: load_proposals(dir, state)}, state}
    end
  end

  defp check_genesis(dir, genesis) do
    path = Path.join(dir, "genesis.hash")
    mine = Base.encode16(Genesis.hash(genesis), case: :lower)

    case File.read(path) do
      {:ok, ^mine} -> :ok
      {:ok, _other} -> {:error, :wrong_genesis}
      {:error, :enoent} -> File.write(path, mine, [:sync])
      {:error, _} = err -> err
    end
  end

  # cada bloco do disco é decodificado e REEXECUTADO: raiz de estado, altura e encadeamento conferem
  defp replay_blocks(s, state, records) do
    pubs = s.genesis.validators

    Enum.reduce_while(records, {:ok, state, %{}, %{}}, fn rec, {:ok, st, blocks, certs} ->
      with {:ok, block, cert} <- parse_record(rec),
           :ok <- verify_disk_cert(cert, block, st.params.chain_id, pubs),
           {:ok, st2} <- Block.apply(st, block) do
        {:cont, {:ok, st2, keep(blocks, block), keep_cert(certs, block.height, cert)}}
      else
        {:error, reason} -> {:halt, {:error, {:bad_block_on_disk, st.height + 1, reason}}}
      end
    end)
  end

  # o certificado gravado junto do bloco é conferido de novo ao subir
  defp verify_disk_cert(nil, _block, _chain, _pubs), do: :ok

  defp verify_disk_cert(cert, block, chain, pubs) do
    with :ok <- check(cert.block_hash == Block.hash(block), :cert_hash_mismatch),
         do: Certificate.verify(cert, chain, pubs)
  end

  defp load_proposals(dir, state) do
    with {:ok, bin} <- File.read(Path.join(dir, "proposals.bin")),
         {:ok, store} <- Proposals.load(bin) do
      Proposals.prune(store, state)
    else
      _ -> Proposals.new()
    end
  end

  # troca atômica: grava num arquivo ao lado e renomeia (nunca deixa um arquivo pela metade)
  defp persist_proposals(%{data_dir: nil}), do: :ok

  defp persist_proposals(%{data_dir: dir, proposals: store}) do
    path = Path.join(dir, "proposals.bin")
    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, Proposals.dump(store), [:sync]),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} -> Logger.warning("não consegui gravar as propostas: #{inspect(reason)}")
    end
  end

  # respeita os limites de bloco dos parâmetros (quantidade e bytes)
  defp take(mempool, params) do
    {taken, _bytes} =
      Enum.reduce_while(mempool, {[], 0}, fn tx, {acc, bytes} ->
        size = byte_size(Tx.encode(tx))

        if length(acc) < params.max_block_txs and bytes + size <= params.max_block_bytes,
          do: {:cont, {[tx | acc], bytes + size}},
          else: {:halt, {acc, bytes}}
      end)

    taken = Enum.reverse(taken)
    {taken, Enum.drop(mempool, length(taken))}
  end

  defp replay(state, txs) do
    Enum.reduce(txs, state, fn tx, acc ->
      case Executor.apply_tx(acc, tx) do
        {:ok, next, _fee} -> next
        {:error, _} -> acc
      end
    end)
  end

  defp keep(blocks, block) do
    blocks |> Map.put(block.height, block) |> Map.delete(block.height - 1_000)
  end

  defp notify(s, block) do
    ids = Enum.map(block.txs, &Tx.id/1)
    for {_ref, pid} <- s.subscribers, do: send(pid, {:brdc_block, block.height, ids})
    :ok
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
