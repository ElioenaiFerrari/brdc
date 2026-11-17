defmodule BrdcNode.BlockStore do
  @moduledoc """
  Armazenamento dos blocos (ADR-0012): contrato para trocar a implementação sem tocar no consenso nem
  no ledger. A fonte da verdade é o **log de blocos**; o estado deriva dele por replay.

  Quem implementa devolve, ao abrir, os registros já gravados (cada um é o bloco codificado por
  `BrdcLedger.Block.encode/1`), e só confirma `append/2` depois que o dado está **no disco**.
  """

  @type t :: term()
  @type recovery :: %{truncated_bytes: non_neg_integer()}

  @doc "Abre (ou cria) o armazém e devolve os registros e o que foi recuperado de uma queda."
  @callback open(path :: Path.t()) ::
              {:ok, t(), [binary()], recovery()} | {:error, term()}

  @doc "Grava um registro no fim e só volta depois do `sync`."
  @callback append(t(), binary()) :: :ok | {:error, term()}

  @callback close(t()) :: :ok
end
