defmodule BrdcP2p.DiscoveryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.Ed25519
  alias BrdcP2p.{AddressBook, AddressRecord, Channel, Discovery, Guard, Listener, Session}

  @chain "brdc-test"
  @genesis :crypto.hash(:sha256, "genesis-d")

  defp seed(n), do: :crypto.hash(:sha256, "disc-validator-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp vals, do: [pub(1), pub(2), pub(3)]

  defp rec(n, host \\ nil, port \\ 4000, seq \\ 1) do
    {:ok, r} = AddressRecord.sign(@chain, seed(n), host || "10.0.0.#{n}", port, seq)
    r
  end

  describe "registro assinado" do
    test "assina, confere e faz ida e volta" do
      r = rec(1)
      assert AddressRecord.valid?(r)
      assert {:ok, ^r} = AddressRecord.decode(AddressRecord.encode(r))
    end

    test "qualquer campo adulterado invalida a assinatura" do
      r = rec(1)

      for bad <- [
            %{r | host: "10.9.9.9"},
            %{r | port: 4001},
            %{r | seq: 2},
            %{r | chain_id: "outra"},
            %{r | validator: pub(2)}
          ] do
        refute AddressRecord.valid?(bad)
      end
    end

    test "host e porta inválidos são recusados" do
      for host <- ["", "a b", "x/y", "a;b", String.duplicate("a", 254), "ünï.cöde"] do
        assert {:error, :invalid_host} = AddressRecord.sign(@chain, seed(1), host, 4000, 1)
      end

      for port <- [0, 65_536, -1] do
        assert {:error, :invalid_port} = AddressRecord.sign(@chain, seed(1), "a.b", port, 1)
      end

      assert {:ok, _} = AddressRecord.sign(@chain, seed(1), "val1.brdc.example", 4000, 1)
      assert {:ok, _} = AddressRecord.sign(@chain, seed(1), "::1", 4000, 1)
    end

    test "lixo não decodifica" do
      assert {:error, :malformed} = AddressRecord.decode("lixo")
      assert {:error, :malformed} = AddressRecord.decode(<<>>)
    end

    property "mudar qualquer byte do registro nunca gera outro registro válido" do
      check all(pos <- integer(0..400), delta <- integer(1..255), max_runs: 200) do
        r = rec(1)
        bin = AddressRecord.encode(r)
        i = rem(pos, byte_size(bin))
        <<pre::binary-size(^i), b, post::binary>> = bin
        mutated = <<pre::binary, rem(b + delta, 256), post::binary>>

        case AddressRecord.decode(mutated) do
          {:ok, r2} -> assert r2 == r or not AddressRecord.valid?(r2)
          {:error, _} -> :ok
        end
      end
    end
  end

  describe "livro de endereços" do
    test "novo, atualizado com seq maior, antigo recusado" do
      b = AddressBook.new(@chain)
      assert {:ok, b, :new} = AddressBook.put(b, rec(1, "10.0.0.1", 4000, 1), vals())
      assert {:ok, b, :updated} = AddressBook.put(b, rec(1, "10.0.0.7", 4000, 2), vals())
      assert AddressBook.get(b, pub(1)).host == "10.0.0.7"
      assert {:error, :stale} = AddressBook.put(b, rec(1, "10.0.0.1", 4000, 1), vals())
      assert {:error, :stale} = AddressBook.put(b, rec(1, "10.0.0.8", 4000, 2), vals())
    end

    test "recusa estranho ao conjunto, rede errada e assinatura falsa" do
      b = AddressBook.new(@chain)
      assert {:error, :unknown_validator} = AddressBook.put(b, rec(99), vals())
      {:ok, outra} = AddressRecord.sign("outra-rede", seed(1), "a.b", 4000, 1)
      assert {:error, :wrong_chain} = AddressBook.put(b, outra, vals())
      forged = %{rec(1) | signature: <<0::512>>}
      assert {:error, :invalid} = AddressBook.put(b, forged, vals())
      # alguém tenta fixar o endereço de outro validador com a própria assinatura
      impostor = %{rec(2) | validator: pub(1)}
      assert {:error, :invalid} = AddressBook.put(b, impostor, vals())
    end

    test "rotação: quem saiu do conjunto é esquecido; só se disca para os outros" do
      {b, 3, 0} = AddressBook.put_all(AddressBook.new(@chain), [rec(1), rec(2), rec(3)], vals())
      assert length(AddressBook.dial_targets(b, pub(1), vals())) == 2
      b = AddressBook.prune(b, [pub(1), pub(2)])

      assert Enum.map(AddressBook.all(b), & &1.validator) |> Enum.sort() ==
               Enum.sort([pub(1), pub(2)])

      assert [r] = AddressBook.dial_targets(b, pub(1), [pub(1), pub(2)])
      assert r.validator == pub(2)
    end

    test "put_all conta aceitos e recusados" do
      b = AddressBook.new(@chain)
      {_b, ok, bad} = AddressBook.put_all(b, [rec(1), rec(99), rec(2)], vals())
      assert {ok, bad} == {2, 1}
    end
  end

  describe "mensagens de descoberta" do
    test "pedido e resposta" do
      {b, _, _} = AddressBook.put_all(AddressBook.new(@chain), [rec(1), rec(2)], vals())
      assert {:reply, reply, ^b} = Discovery.handle(Discovery.get_addrs(), b, vals())
      empty = AddressBook.new(@chain)
      assert {:ok, learned, 2, 0} = Discovery.handle(reply, empty, vals())
      assert length(AddressBook.all(learned)) == 2
    end

    test "resposta com registro falso: o falso é descartado, o bom é guardado" do
      forged = %{rec(2) | signature: <<1::512>>}

      msg =
        <<2>> <>
          BrdcCrypto.Encoding.encode([{:list, :bytes}], [
            [AddressRecord.encode(rec(1)), AddressRecord.encode(forged)]
          ])

      assert {:ok, book, 1, 1} = Discovery.handle(msg, AddressBook.new(@chain), vals())
      assert AddressBook.get(book, pub(1)) && is_nil(AddressBook.get(book, pub(2)))
    end

    test "mensagem malformada, lista grande demais e tipo desconhecido" do
      assert {:error, :malformed} =
               Discovery.handle(<<2, 1, 2, 3>>, AddressBook.new(@chain), vals())

      assert {:error, :malformed} = Discovery.handle(<<9>>, AddressBook.new(@chain), vals())
      assert {:error, :malformed} = Discovery.handle(<<>>, AddressBook.new(@chain), vals())
      many = for _ <- 1..65, do: AddressRecord.encode(rec(1))
      msg = <<2>> <> BrdcCrypto.Encoding.encode([{:list, :bytes}], [many])
      assert {:error, :malformed} = Discovery.handle(msg, AddressBook.new(@chain), vals())
    end

    property "lixo nunca levanta exceção" do
      check all(bin <- binary(max_length: 300)) do
        r = Discovery.handle(bin, AddressBook.new(@chain), vals())
        assert match?({:reply, _, _}, r) or match?({:ok, _, _, _}, r) or r == {:error, :malformed}
      end
    end
  end

  describe "de ponta a ponta" do
    defp cfg(n),
      do: %{seed: seed(n), chain_id: @chain, genesis_hash: @genesis, validators: &vals/0}

    # o processo é ligado ao teste e pode já ter morrido quando o on_exit roda
    defp stop_quietly(pid) do
      Listener.stop(pid)
    catch
      :exit, _ -> :ok
    end

    # sobe o validador `n` com um livro próprio (num Agent) e o serviço de descoberta
    defp node(n, records) do
      {:ok, book} =
        Agent.start_link(fn ->
          elem(AddressBook.put_all(AddressBook.new(@chain), records, vals()), 0)
        end)

      {:ok, guard} = Guard.start_link(sweep_ms: :never)

      handler = fn session ->
        Discovery.serve(session, fn -> Agent.get(book, & &1) end, &vals/0)
      end

      {:ok, l} = Listener.start_link(config: cfg(n), guard: guard, handler: handler)
      on_exit(fn -> stop_quietly(l) end)
      {Listener.port(l), book}
    end

    test "A só conhece B; pergunta a B, descobre C e disca para C pelo endereço assinado" do
      # C sobe e assina o próprio endereço com a porta real
      {port_c, _} = node(3, [])
      {:ok, rec_c} = AddressRecord.sign(@chain, seed(3), "127.0.0.1", port_c, 1)

      # B sobe sabendo de C
      {port_b, _} = node(2, [rec_c])

      # A conhece apenas B
      {:ok, rec_b} = AddressRecord.sign(@chain, seed(2), "127.0.0.1", port_b, 1)
      book_a = elem(AddressBook.put_all(AddressBook.new(@chain), [rec_b], vals()), 0)
      assert AddressBook.get(book_a, pub(3)) == nil

      {:ok, guard_a} = Guard.start_link(sweep_ms: :never)
      {:ok, conn} = Channel.connect(~c"127.0.0.1", port_b, cfg(1), timeout: 3_000)
      {:ok, id} = Guard.admit(guard_a, {127, 0, 0, 1})
      session = Session.new(conn, id, guard_a)

      assert {:ok, book_a, session, accepted} = Discovery.sync(session, book_a, vals())
      assert accepted >= 1
      Session.close(session)

      found = AddressBook.get(book_a, pub(3))
      assert found.port == port_c

      # agora A disca para C usando o que aprendeu
      assert {:ok, conn_c} =
               Channel.connect(String.to_charlist(found.host), found.port, cfg(1), timeout: 3_000)

      assert conn_c.peer == pub(3)
      Channel.close(conn_c)
    end
  end
end
