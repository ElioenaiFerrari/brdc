defmodule BrdcLedger.LedgerTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Account, Ed25519}
  alias BrdcLedger.{Block, Executor, Params, State, Tx}

  @chain "brdc-test"

  defp seed(n), do: :crypto.hash(:sha256, "brdc-test-seed-#{n}")
  defp acct(n), do: Account.from_seed(seed(n))
  defp addr(n), do: BrdcCrypto.Address.hash(acct(n).public_key)

  defp state(threshold \\ 2) do
    issuers = for n <- 101..103, do: Ed25519.public_key(seed(n))
    {:ok, p} = Params.new(chain_id: @chain, issuers: issuers, threshold: threshold)
    State.new(p)
  end

  defp tx(kind, n, nonce, fee, payload, chain \\ @chain) do
    %Tx{
      chain_id: chain,
      kind: kind,
      nonce: nonce,
      fee: fee,
      sender_pub: acct(n).public_key,
      payload: payload
    }
    |> Tx.sign(seed(n))
  end

  defp mint(to_n, amount, ref, issuers \\ [101, 102], sender \\ 9, nonce \\ 0) do
    doc = Tx.issuance_doc(:mint, @chain, addr(to_n), amount, ref)
    approvals = for i <- issuers, do: Tx.approval(doc, seed(i))
    tx(2, sender, nonce, 0, Tx.issuance_payload(addr(to_n), amount, ref, approvals))
  end

  defp burn(n, amount, ref, nonce, fee, issuers \\ [101, 102]) do
    doc = Tx.issuance_doc(:burn, @chain, addr(n), amount, ref)
    approvals = for i <- issuers, do: Tx.approval(doc, seed(i))
    tx(3, n, nonce, fee, Tx.issuance_payload(addr(n), amount, ref, approvals))
  end

  defp transfer(from, to, amount, nonce, fee \\ 5_000),
    do: tx(1, from, nonce, fee, Tx.transfer_payload(addr(to), amount))

  defp ok!({:ok, s, _}), do: s

  describe "assinatura e codificação" do
    test "ida e volta e assinatura válida" do
      t = transfer(1, 2, 10, 0)
      assert {:ok, ^t} = Tx.decode(Tx.encode(t))
      assert Tx.valid_signature?(t)
    end

    test "adulterar qualquer campo invalida a assinatura" do
      t = transfer(1, 2, 10, 0)

      for bad <- [
            %{t | nonce: 1},
            %{t | fee: 1},
            %{t | chain_id: "x"},
            %{t | payload: t.payload <> "x"},
            %{t | kind: 2}
          ] do
        refute Tx.valid_signature?(bad)
      end
    end

    test "lixo não decodifica" do
      assert {:error, :malformed} = Tx.decode("lixo")
    end
  end

  describe "mint e burn por M-de-N" do
    test "mint com aprovações suficientes cria moeda e conta a oferta" do
      s = ok!(Executor.apply_tx(state(), mint(1, 1_000_000, "pix-1")))
      assert State.balance(s, addr(1)) == 1_000_000
      assert State.supply(s) == 1_000_000
    end

    test "mint com menos aprovações que o limite é recusado" do
      assert {:error, :not_enough_approvals} = Executor.apply_tx(state(), mint(1, 5, "r", [101]))
    end

    test "aprovação repetida do mesmo emissor conta uma vez" do
      assert {:error, :not_enough_approvals} =
               Executor.apply_tx(state(), mint(1, 5, "r", [101, 101]))
    end

    test "quem não é emissor não aprova" do
      assert {:error, :not_enough_approvals} =
               Executor.apply_tx(state(), mint(1, 5, "r", [101, 7]))
    end

    test "aprovação de um valor não vale para outro" do
      doc = Tx.issuance_doc(:mint, @chain, addr(1), 5, "r")
      approvals = for i <- [101, 102], do: Tx.approval(doc, seed(i))
      bad = tx(2, 9, 0, 0, Tx.issuance_payload(addr(1), 6, "r", approvals))
      assert {:error, :not_enough_approvals} = Executor.apply_tx(state(), bad)
    end

    test "a mesma referência não emite duas vezes" do
      s = ok!(Executor.apply_tx(state(), mint(1, 5, "dup")))
      assert {:error, :ref_used} = Executor.apply_tx(s, mint(1, 5, "dup", [101, 102], 9, 1))
    end

    test "burn reduz saldo e oferta; só o dono queima" do
      s = ok!(Executor.apply_tx(state(), mint(1, 10_000, "m")))
      s = ok!(Executor.apply_tx(s, burn(1, 4_000, "b", 0, 0)))
      assert State.balance(s, addr(1)) == 6_000
      assert State.supply(s) == 6_000

      doc = Tx.issuance_doc(:burn, @chain, addr(1), 1, "x")
      ap = for i <- [101, 102], do: Tx.approval(doc, seed(i))
      stolen = tx(3, 2, 0, 0, Tx.issuance_payload(addr(1), 1, "x", ap))
      assert {:error, :not_sender} = Executor.apply_tx(s, stolen)
    end
  end

  describe "transferência" do
    setup do
      {:ok, s: ok!(Executor.apply_tx(state(), mint(1, 1_000_000, "m")))}
    end

    test "move saldo, cobra a taxa e sobe o nonce", %{s: s} do
      t = transfer(1, 2, 100_000, 0)
      {:ok, s2, fee} = Executor.apply_tx(s, t)
      assert fee == 5_000
      assert State.balance(s2, addr(2)) == 100_000
      assert State.balance(s2, addr(1)) == 1_000_000 - 100_000 - 5_000
      assert State.account(s2, addr(1)).nonce == 1
    end

    test "replay e nonce fora de ordem são recusados", %{s: s} do
      t = transfer(1, 2, 10, 0)
      s2 = ok!(Executor.apply_tx(s, t))
      assert {:error, :bad_nonce} = Executor.apply_tx(s2, t)
      assert {:error, :bad_nonce} = Executor.apply_tx(s, transfer(1, 2, 10, 5))
    end

    test "outra rede, saldo insuficiente, taxa baixa e valor zero", %{s: s} do
      assert {:error, :wrong_chain} =
               Executor.apply_tx(s, tx(1, 1, 0, 5_000, Tx.transfer_payload(addr(2), 1), "outra"))

      assert {:error, :insufficient_funds} = Executor.apply_tx(s, transfer(1, 2, 2_000_000, 0))
      assert {:error, :fee_too_low} = Executor.apply_tx(s, transfer(1, 2, 1, 0, 10))
      assert {:error, :bad_amount} = Executor.apply_tx(s, transfer(1, 2, 0, 0))
    end

    test "taxa mínima segue a tabela do ADR-0014", %{s: s} do
      t = transfer(1, 2, 1, 0)
      assert Executor.min_fee(s.params, t) == 1_000 + byte_size(Tx.encode(t))
    end
  end

  describe "bloco" do
    setup do
      s = ok!(Executor.apply_tx(state(), mint(1, 1_000_000, "m")))
      {:ok, s: s}
    end

    test "executa, reparte a taxa entre quem assinou e mantém a oferta", %{s: s} do
      proposer = addr(50)
      signers = [proposer, addr(51), addr(52)]
      txs = [transfer(1, 2, 1_000, 0, 5_000), transfer(1, 3, 1_000, 1, 5_000)]
      {:ok, block, s2} = Block.build(s, proposer, signers, txs)

      assert State.total_balances(s2) == State.supply(s2)
      # taxa total 10_000 / 3 = 3_333, sobra 1 para o proponente
      assert State.balance(s2, addr(51)) == 3_333
      assert State.balance(s2, proposer) == 3_334
      assert s2.height == 1
      assert s2.last_hash == Block.hash(block)
      assert {:ok, s3} = Block.apply(s, block)
      assert State.root(s3) == State.root(s2)
    end

    test "bloco com uma transação inválida é recusado inteiro", %{s: s} do
      proposer = addr(50)
      bad = [transfer(1, 2, 1, 0), transfer(1, 2, 1, 7)]
      assert {:error, {:invalid_tx, _, :bad_nonce}} = Block.build(s, proposer, [proposer], bad)
    end

    test "sem bloco vazio, altura e prev_hash conferidos, state_root adulterado recusado", %{s: s} do
      proposer = addr(50)
      assert {:error, :empty_block} = Block.build(s, proposer, [proposer], [])
      {:ok, block, _} = Block.build(s, proposer, [proposer], [transfer(1, 2, 1, 0)])
      assert {:error, :bad_state_root} = Block.apply(s, %{block | state_root: <<0::256>>})
      assert {:error, :bad_height} = Block.apply(s, %{block | height: 5})
      assert {:error, :bad_prev_hash} = Block.apply(s, %{block | prev_hash: <<1::256>>})
      assert {:error, :proposer_not_signer} = Block.apply(s, %{block | signers: [addr(51)]})
    end

    test "raiz de estado é determinística e muda com qualquer saldo", %{s: s} do
      assert State.root(s) == State.root(s)
      s2 = State.put_account(s, addr(1), %{balance: 1, nonce: 0})
      refute State.root(s) == State.root(s2)
    end
  end

  describe "atestado de reserva" do
    defp attest(seq, reserve, ref, issuers \\ [101, 102], nonce \\ 0) do
      doc = Tx.attestation_doc(@chain, seq, reserve, ref)
      ap = for i <- issuers, do: Tx.approval(doc, seed(i))
      tx(4, 9, nonce, 0, Tx.attestation_payload(seq, reserve, ref, ap))
    end

    test "M emissores publicam a reserva; a cobertura compara com a oferta" do
      s = ok!(Executor.apply_tx(state(), mint(1, 1_000_000, "m")))
      assert State.coverage(s) == :none
      s = ok!(Executor.apply_tx(s, attest(1, 1_500_000, "extrato-1", [101, 102], 1)))
      assert State.coverage(s) == {:covered, 500_000}
      s = ok!(Executor.apply_tx(s, attest(2, 900_000, "extrato-2", [101, 102], 2)))
      assert State.coverage(s) == {:under, -100_000}
    end

    test "sem aprovações suficientes, sequência repetida ou pulada são recusadas" do
      assert {:error, :not_enough_approvals} =
               Executor.apply_tx(state(), attest(1, 5, "r", [101]))

      assert {:error, :bad_sequence} = Executor.apply_tx(state(), attest(2, 5, "r"))
      s = ok!(Executor.apply_tx(state(), attest(1, 5, "r")))
      assert {:error, :bad_sequence} = Executor.apply_tx(s, attest(1, 6, "r", [101, 102], 1))
    end

    test "o atestado muda a raiz de estado, mas não mexe em saldos nem na oferta" do
      s0 = state()
      s1 = ok!(Executor.apply_tx(s0, attest(1, 5, "r")))
      refute State.root(s0) == State.root(s1)
      assert State.supply(s1) == 0
    end

    test "subcobertura é só informação: nada é congelado (ADR-0009)" do
      s = ok!(Executor.apply_tx(state(), mint(1, 1_000_000, "m")))
      s = ok!(Executor.apply_tx(s, attest(1, 10, "r", [101, 102], 1)))
      assert {:under, _} = State.coverage(s)
      assert {:ok, _, _} = Executor.apply_tx(s, transfer(1, 2, 10, 0))
    end
  end

  describe "parâmetros" do
    test "limite precisa caber no conjunto e emissores são distintos" do
      pub = Ed25519.public_key(seed(1))
      assert {:error, :bad_threshold} = Params.new(chain_id: "x", issuers: [pub], threshold: 2)
      assert {:error, :bad_issuers} = Params.new(chain_id: "x", issuers: [pub, pub], threshold: 1)
      assert {:error, :bad_issuers} = Params.new(chain_id: "x", issuers: [], threshold: 1)
    end
  end
end
