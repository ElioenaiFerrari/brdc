defmodule BrdcP2p.AddressBook do
  @moduledoc """
  Livro de endereços dos validadores (Fase 4). **Puro**: guarda o registro mais novo de cada
  validador do conjunto em vigor. Aceita um registro só se: é da mesma rede, a assinatura confere,
  o signatário **está no conjunto**, e o `seq` é **maior** que o já guardado. O tamanho é limitado
  pelo tamanho do conjunto (um registro por validador).
  """
  alias BrdcP2p.AddressRecord

  defstruct [:chain_id, records: %{}]

  @type t :: %__MODULE__{chain_id: String.t(), records: %{<<_::256>> => AddressRecord.t()}}

  @spec new(String.t()) :: t()
  def new(chain_id), do: %__MODULE__{chain_id: chain_id}

  @doc "Tenta guardar um registro. Devolve `:new` ou `:updated` em caso de sucesso."
  @spec put(t(), AddressRecord.t(), [<<_::256>>]) ::
          {:ok, t(), :new | :updated}
          | {:error, :wrong_chain | :invalid | :unknown_validator | :stale}
  def put(%__MODULE__{} = book, %AddressRecord{} = r, validators) do
    with :ok <- check(r.chain_id == book.chain_id, :wrong_chain),
         :ok <- check(AddressRecord.valid?(r), :invalid),
         :ok <- check(r.validator in validators, :unknown_validator) do
      case Map.fetch(book.records, r.validator) do
        :error ->
          {:ok, %{book | records: Map.put(book.records, r.validator, r)}, :new}

        {:ok, old} when r.seq > old.seq ->
          {:ok, %{book | records: Map.put(book.records, r.validator, r)}, :updated}

        {:ok, _old} ->
          {:error, :stale}
      end
    end
  end

  @doc "Guarda vários; devolve o livro e quantos foram aceitos e recusados."
  @spec put_all(t(), [AddressRecord.t()], [<<_::256>>]) ::
          {t(), accepted :: non_neg_integer(), rejected :: non_neg_integer()}
  def put_all(book, records, validators) do
    Enum.reduce(records, {book, 0, 0}, fn r, {b, ok, bad} ->
      case put(b, r, validators) do
        {:ok, b2, _} -> {b2, ok + 1, bad}
        {:error, _} -> {b, ok, bad + 1}
      end
    end)
  end

  @doc "Endereço guardado de um validador."
  @spec get(t(), <<_::256>>) :: AddressRecord.t() | nil
  def get(%__MODULE__{records: r}, validator), do: Map.get(r, validator)

  @doc "Lista completa dos registros (ordem estável por chave)."
  @spec all(t()) :: [AddressRecord.t()]
  def all(%__MODULE__{records: r}), do: r |> Enum.sort() |> Enum.map(&elem(&1, 1))

  @doc "Esquece quem saiu do conjunto (rotação)."
  @spec prune(t(), [<<_::256>>]) :: t()
  def prune(%__MODULE__{} = book, validators) do
    %{book | records: book.records |> Enum.filter(fn {k, _} -> k in validators end) |> Map.new()}
  end

  @doc "Quem discar: validadores do conjunto, menos eu, com endereço conhecido."
  @spec dial_targets(t(), <<_::256>>, [<<_::256>>]) :: [AddressRecord.t()]
  def dial_targets(%__MODULE__{} = book, me, validators) do
    for v <- validators, v != me, r = get(book, v), do: r
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
