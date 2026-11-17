defmodule BrdcP2p.Discovery do
  @moduledoc """
  Descoberta de pares (Fase 4): dois validadores trocam os registros de endereço que conhecem.

  Mensagens (dentro de quadros): `1` = `get_addrs` (pede), `2` = `addrs` (responde, no máximo
  `@max_records` registros). Cada registro recebido é conferido por `AddressBook.put/3` (rede,
  assinatura, validador do conjunto, `seq` mais novo); o que não passa é descartado e conta como
  mensagem malformada **só se** a mensagem inteira não decodifica. Quem recebe nunca confia em quem
  entregou: a autoridade vem da assinatura do dono do endereço.
  """
  alias BrdcCrypto.Encoding
  alias BrdcP2p.{AddressBook, AddressRecord, Limits, Session}

  @max_records 64
  @get 1
  @addrs 2

  @doc "Monta o pedido."
  @spec get_addrs() :: binary()
  def get_addrs, do: <<@get>>

  @doc "Monta a resposta com até #{@max_records} registros do livro."
  @spec addrs(AddressBook.t()) :: binary()
  def addrs(%AddressBook{} = book) do
    recs =
      book |> AddressBook.all() |> Enum.take(@max_records) |> Enum.map(&AddressRecord.encode/1)

    <<@addrs>> <> Encoding.encode([{:list, :bytes}], [recs])
  end

  @doc """
  Trata uma mensagem recebida. Devolve `{:reply, bytes, livro}` (era um pedido),
  `{:ok, livro, aceitos, recusados}` (era uma resposta) ou `{:error, :malformed}`.
  """
  @spec handle(binary(), AddressBook.t(), [<<_::256>>]) ::
          {:reply, binary(), AddressBook.t()}
          | {:ok, AddressBook.t(), non_neg_integer(), non_neg_integer()}
          | {:error, :malformed}
  def handle(<<@get>>, book, _validators), do: {:reply, addrs(book), book}

  def handle(<<@addrs, rest::binary>>, book, validators) do
    with true <- byte_size(rest) <= Limits.max_size(:address_record) * @max_records,
         {:ok, [raw]} <- Encoding.decode([{:list, :bytes}], rest),
         true <- length(raw) <= @max_records,
         {:ok, recs} <- decode_all(raw) do
      {book, ok, bad} = AddressBook.put_all(book, recs, validators)
      {:ok, book, ok, bad}
    else
      _ -> {:error, :malformed}
    end
  end

  def handle(_other, _book, _validators), do: {:error, :malformed}

  defp decode_all(raw) do
    Enum.reduce_while(raw, {:ok, []}, fn bin, {:ok, acc} ->
      case byte_size(bin) <= Limits.max_size(:address_record) && AddressRecord.decode(bin) do
        {:ok, r} -> {:cont, {:ok, [r | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  @doc "Lado que **pergunta**: pede os endereços, lê a resposta e devolve o livro atualizado."
  @spec sync(Session.t(), AddressBook.t(), [<<_::256>>]) ::
          {:ok, AddressBook.t(), Session.t(), non_neg_integer()} | {:error, term(), Session.t()}
  def sync(session, book, validators) do
    with :ok <- Session.send(session, get_addrs()),
         {:ok, msg, session} <- Session.recv(session) do
      case handle(msg, book, validators) do
        {:ok, book, ok, _bad} -> {:ok, book, session, ok}
        _ -> {:error, :malformed, Session.malformed(session)}
      end
    else
      {:error, reason} -> {:error, reason, session}
      {:error, reason, session} -> {:error, reason, session}
    end
  end

  @doc "Lado que **responde**: atende pedidos até o par sair. `book_fun` lê o livro atual."
  @spec serve(Session.t(), (-> AddressBook.t()), (-> [<<_::256>>])) :: :done
  def serve(session, book_fun, validators) do
    case Session.recv(session, 5_000) do
      {:ok, msg, session} ->
        case handle(msg, book_fun.(), validators.()) do
          {:reply, bytes, _} ->
            Session.send(session, bytes)
            serve(session, book_fun, validators)

          _ ->
            session |> Session.malformed()
            :done
        end

      {:error, _, _} ->
        :done
    end
  end
end
