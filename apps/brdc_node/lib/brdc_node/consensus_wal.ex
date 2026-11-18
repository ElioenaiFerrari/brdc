defmodule BrdcNode.ConsensusWal do
  @moduledoc """
  Diário de segurança do consenso (ADR-0012, M3): grava, **antes de transmitir**, cada proposta e cada voto
  que este validador assina, para que uma queda e um reinício **nunca** o levem a assinar algo que
  contradiga o que já saiu da máquina (voto duplo = equivocação, que a rede pune).

  Regra de uso (de quem roda o motor): receber as ações do `Engine`, chamar `persist_own/2` e **só se
  voltar `:ok`** executar as transmissões. Se a gravação falhar, **nada** é transmitido.

  - Formato: o mesmo log com soma de verificação do `BrdcNode.BlockStore.File`; cada registro é
    `1 ‖ voto` ou `2 ‖ proposta` (codificação de `Vote.encode/1` e `Proposal.encode/2`).
  - Uma cauda rasgada (queda no meio da gravação) é descartada: a mensagem **não chegou a sair**, porque a
    transmissão só acontece depois do `sync`.
  - Registro **ilegível** no meio é erro fatal (`{:bad_wal, índice}`): sem o diário íntegro o validador
    **não** vota (é preferível ficar parado a arriscar a equivocação).
  - O diário é de **uma altura**: `open/5` descarta o que for de alturas anteriores.
  """
  alias BrdcConsensus.{Proposal, Vote}
  alias BrdcNode.BlockStore.File, as: LogFile

  @enforce_keys [:store, :path, :pub, :enc, :dec]
  defstruct [:store, :path, :pub, :enc, :dec]

  @type t :: %__MODULE__{}

  @doc """
  Abre o diário de `height` e devolve as mensagens **próprias** dessa altura, na ordem em que saíram.
  `block_encode`/`block_decode` ensinam a (de)codificar o bloco que viaja na proposta.
  """
  @spec open(Path.t(), non_neg_integer(), <<_::256>>, (term() -> binary()), (binary() ->
                                                                               {:ok, term()}
                                                                               | {:error, term()})) ::
          {:ok, t(), [Vote.t() | Proposal.t()]} | {:error, term()}
  def open(path, height, pub, block_encode, block_decode) do
    with {:ok, store, records, _recovery} <- LogFile.open(path),
         {:ok, all} <- decode_all(records, block_decode) do
      wal = %__MODULE__{store: store, path: path, pub: pub, enc: block_encode, dec: block_decode}
      keep = Enum.filter(all, &(height_of(&1) == height))

      if length(keep) == length(all) do
        {:ok, wal, keep}
      else
        # sobrou coisa de altura antiga: reescreve só com a altura atual
        rewrite(wal, keep)
      end
    end
  end

  @doc """
  Grava (com `sync`) as mensagens **próprias** entre as ações do motor, na ordem. `:ok` só se **todas**
  foram gravadas; só então o chamador pode transmitir.
  """
  @spec persist_own(t(), [term()]) :: :ok | {:error, term()}
  def persist_own(%__MODULE__{} = wal, actions) do
    actions
    |> Enum.flat_map(fn
      {:broadcast, msg} -> if own?(wal, msg), do: [msg], else: []
      _ -> []
    end)
    |> Enum.reduce_while(:ok, fn msg, :ok ->
      case LogFile.append(wal.store, encode(wal, msg)) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc "Passa para outra altura: o diário da altura decidida não serve mais e é esvaziado."
  @spec advance(t()) :: {:ok, t()} | {:error, term()}
  def advance(%__MODULE__{} = wal) do
    with {:ok, wal, []} <- rewrite(wal, []), do: {:ok, wal}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{store: store}), do: LogFile.close(store)

  # --- interno ---------------------------------------------------------------------------------------

  defp own?(%{pub: pub}, %Vote{voter: v}), do: v == pub
  defp own?(%{pub: pub}, %Proposal{proposer: p}), do: p == pub
  defp own?(_, _), do: false

  defp height_of(%Vote{height: h}), do: h
  defp height_of(%Proposal{height: h}), do: h

  defp encode(_wal, %Vote{} = v), do: <<1, Vote.encode(v)::binary>>
  defp encode(wal, %Proposal{} = p), do: <<2, Proposal.encode(p, wal.enc)::binary>>

  defp decode_all(records, block_decode) do
    records
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {rec, i}, {:ok, acc} ->
      case decode(rec, block_decode) do
        {:ok, msg} -> {:cont, {:ok, [msg | acc]}}
        :error -> {:halt, {:error, {:bad_wal, i}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp decode(<<1, bin::binary>>, _), do: ok_or_error(Vote.decode(bin))

  defp decode(<<2, bin::binary>>, block_decode),
    do: ok_or_error(Proposal.decode(bin, block_decode))

  defp decode(_, _), do: :error

  defp ok_or_error({:ok, msg}), do: {:ok, msg}
  defp ok_or_error(_), do: :error

  # troca atômica: grava o novo conteúdo ao lado, renomeia por cima e reabre
  defp rewrite(wal, keep) do
    LogFile.close(wal.store)
    tmp = wal.path <> ".tmp"
    File.rm(tmp)

    with {:ok, tmp_store, [], _} <- LogFile.open(tmp),
         :ok <- append_all(tmp_store, wal, keep),
         :ok <- LogFile.close(tmp_store),
         :ok <- File.rename(tmp, wal.path),
         {:ok, store, _, _} <- LogFile.open(wal.path) do
      {:ok, %{wal | store: store}, keep}
    end
  end

  defp append_all(store, wal, msgs) do
    Enum.reduce_while(msgs, :ok, fn m, :ok ->
      case LogFile.append(store, encode(wal, m)) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end
end
