defmodule BrdcNode.BlockStore.File do
  @moduledoc """
  Log de blocos em um arquivo só (ADR-0012), com a biblioteca padrão do OTP (`:file`), sem dependência.

  Cada registro: `tamanho (4 bytes) ‖ soma (16 bytes) ‖ conteúdo`, onde a soma é a SHA3-256 do
  conteúdo truncada em 16 bytes. Escrita só com **`sync`** antes de confirmar.

  **Recuperação ao abrir:**
  - registro **incompleto no fim** (queda no meio da escrita), ou registro **completo com soma errada
    que é o último do arquivo** (escrita rasgada): o arquivo é **truncado** no último registro inteiro
    e o nó continua dali;
  - registro com soma errada **com mais dados depois dele**: corrupção no meio, **erro fatal**
    (`{:corrupt, índice}`): quem opera resincroniza de outros nós, nunca "conserta" no escuro.
  """
  @behaviour BrdcNode.BlockStore

  @header 20
  @max_record 16 * 1024 * 1024

  defstruct [:io, :path]

  @type t :: %__MODULE__{io: :file.io_device(), path: Path.t()}

  @impl true
  def open(path) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, data} <- read_existing(path),
         {:ok, records, good, total} <- scan(data),
         {:ok, io} <- :file.open(String.to_charlist(path), [:read, :write, :binary, :raw]) do
      with :ok <- truncate(io, good, total),
           {:ok, _} <- :file.position(io, good) do
        {:ok, %__MODULE__{io: io, path: path}, records, %{truncated_bytes: total - good}}
      else
        {:error, _} = err ->
          :file.close(io)
          err
      end
    end
  end

  @impl true
  def append(%__MODULE__{io: io}, record) when is_binary(record) do
    size = byte_size(record)

    if size > @max_record do
      {:error, :record_too_big}
    else
      frame = <<size::32, checksum(record)::binary-16, record::binary>>

      with :ok <- :file.write(io, frame), do: :file.sync(io)
    end
  end

  @impl true
  def close(%__MODULE__{io: io}), do: :file.close(io)

  # --- leitura e recuperação -----------------------------------------------------------------------

  defp read_existing(path) do
    case File.read(path) do
      {:ok, data} -> {:ok, data}
      {:error, :enoent} -> {:ok, <<>>}
      {:error, _} = err -> err
    end
  end

  # devolve {registros, bytes bons, bytes totais}
  defp scan(data), do: scan(data, 0, 0, [], byte_size(data))

  defp scan(<<>>, _index, good, acc, total), do: {:ok, Enum.reverse(acc), good, total}

  # cabeçalho incompleto no fim: cauda truncada
  defp scan(rest, _index, good, acc, total) when byte_size(rest) < @header,
    do: {:ok, Enum.reverse(acc), good, total}

  defp scan(<<size::32, sum::binary-16, rest::binary>>, index, good, acc, total) do
    cond do
      # tamanho absurdo: só pode ser lixo
      size > @max_record ->
        bad(rest, index, good, acc, total)

      # registro incompleto no fim: cauda truncada
      byte_size(rest) < size ->
        {:ok, Enum.reverse(acc), good, total}

      true ->
        <<record::binary-size(^size), tail::binary>> = rest

        if checksum(record) == sum do
          scan(tail, index + 1, good + @header + size, [record | acc], total)
        else
          bad(tail, index, good, acc, total)
        end
    end
  end

  # soma errada ou tamanho absurdo: se não há mais nada depois, é a última escrita rasgada;
  # se há, a corrupção está no meio do log
  defp bad(<<>>, _index, good, acc, total), do: {:ok, Enum.reverse(acc), good, total}
  defp bad(_tail, index, _good, _acc, _total), do: {:error, {:corrupt, index}}

  defp truncate(_io, good, total) when good == total, do: :ok

  defp truncate(io, good, _total) do
    with {:ok, _} <- :file.position(io, good), :ok <- :file.truncate(io), do: :file.sync(io)
  end

  defp checksum(record), do: binary_part(:crypto.hash(:sha3_256, record), 0, 16)
end
