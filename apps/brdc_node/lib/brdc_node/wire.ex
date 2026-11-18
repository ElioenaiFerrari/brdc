defmodule BrdcNode.Wire do
  @moduledoc """
  Mensagens entre validadores (M2): um byte de tipo e o corpo, com a codificação determinística do projeto.
  Cada quadro do canal TLS leva **uma** mensagem.

  | tipo | mensagem | corpo |
  |---|---|---|
  | 1 | `{:tx, bytes}` | transação assinada (até 64 KiB) |
  | 2 | `{:proposal, %Proposal{}}` | proposta com o bloco |
  | 3 | `{:vote, %Vote{}}` | prevote ou precommit |
  | 4 | `{:status, altura, último_hash}` | onde o par está (para sincronizar) |
  | 5 | `{:get_blocks, de, máximo}` | pede blocos a partir de uma altura (máx. #{16}) |
  | 6 | `{:blocks, [{bloco, certificado}]}` | resposta; cada bloco vem com o certificado de commit |

  `decode/1` **recusa** lixo, sobras, tipo desconhecido, pedido grande demais e bloco ou certificado malformado:
  quem recebe trata como mau comportamento do par (ponto no `Guard`).
  """
  alias BrdcConsensus.{Certificate, Proposal, Vote}
  alias BrdcCrypto.Encoding
  alias BrdcLedger.Block

  @max_tx 65_536
  @max_blocks 16

  @type msg ::
          {:tx, binary()}
          | {:proposal, Proposal.t()}
          | {:vote, Vote.t()}
          | {:status, non_neg_integer(), binary() | nil}
          | {:get_blocks, pos_integer(), pos_integer()}
          | {:blocks, [{Block.t(), Certificate.t()}]}

  @doc "Máximo de blocos por resposta."
  @spec max_blocks() :: pos_integer()
  def max_blocks, do: @max_blocks

  @spec encode(msg()) :: binary()
  def encode({:tx, bin}) when is_binary(bin), do: <<1, bin::binary>>
  def encode({:proposal, %Proposal{} = p}), do: <<2, Proposal.encode(p, &Block.encode/1)::binary>>
  def encode({:vote, %Vote{} = v}), do: <<3, Vote.encode(v)::binary>>

  def encode({:status, height, last}),
    do: <<4, Encoding.encode([:u64, :bytes], [height, last || <<>>])::binary>>

  def encode({:get_blocks, from, max}),
    do: <<5, Encoding.encode([:u64, :u32], [from, max])::binary>>

  def encode({:blocks, list}) do
    entries =
      for {block, %Certificate{} = cert} <- list do
        Encoding.encode([:bytes, :bytes], [Block.encode(block), Certificate.encode(cert)])
      end

    <<6, Encoding.encode([{:list, :bytes}], [entries])::binary>>
  end

  @spec decode(binary()) :: {:ok, msg()} | {:error, :malformed}
  def decode(<<1, tx::binary>>) when byte_size(tx) in 1..@max_tx, do: {:ok, {:tx, tx}}

  def decode(<<2, bin::binary>>) do
    case Proposal.decode(bin, &Block.decode/1) do
      {:ok, p} -> {:ok, {:proposal, p}}
      _ -> {:error, :malformed}
    end
  end

  def decode(<<3, bin::binary>>), do: wrap(:vote, Vote.decode(bin))

  def decode(<<4, bin::binary>>) do
    case Encoding.decode([:u64, :bytes], bin) do
      {:ok, [h, last]} when byte_size(last) in [0, 32] ->
        {:ok, {:status, h, if(last == <<>>, do: nil, else: last)}}

      _ ->
        {:error, :malformed}
    end
  end

  def decode(<<5, bin::binary>>) do
    case Encoding.decode([:u64, :u32], bin) do
      {:ok, [from, max]} when from >= 1 and max in 1..@max_blocks ->
        {:ok, {:get_blocks, from, max}}

      _ ->
        {:error, :malformed}
    end
  end

  def decode(<<6, bin::binary>>) do
    with {:ok, [entries]} <- Encoding.decode([{:list, :bytes}], bin),
         true <- length(entries) <= @max_blocks,
         {:ok, list} <- decode_blocks(entries) do
      {:ok, {:blocks, list}}
    else
      _ -> {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp wrap(tag, {:ok, v}), do: {:ok, {tag, v}}
  defp wrap(_, _), do: {:error, :malformed}

  defp decode_blocks(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn e, {:ok, acc} ->
      with {:ok, [bb, cb]} <- Encoding.decode([:bytes, :bytes], e),
           {:ok, block} <- Block.decode(bb),
           {:ok, cert} <- Certificate.decode(cb) do
        {:cont, {:ok, [{block, cert} | acc]}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end
end
