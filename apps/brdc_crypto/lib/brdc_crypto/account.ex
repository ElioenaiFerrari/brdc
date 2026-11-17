defmodule BrdcCrypto.Account do
  @moduledoc """
  Conta derivada de uma frase BIP-39 (+ passphrase), Fase 1.

  Caminho: `m/44'/1112687683'/<conta>'/0'/<índice>'` (SLIP-10 Ed25519, tudo endurecido).
  `1112687683` é "BRDC" em ASCII (0x42524443); **não está registrado no SLIP-44**
  (provisório, ver docs/concepts/03).

  A chave privada nunca aparece em `inspect/1` (redigida). Na BEAM não há
  zeroização de memória (limite documentado no THREAT-MODEL). No produto, quem
  deriva é o **navegador**; este módulo existe para testes, ferramentas de
  desenvolvimento e para provar que o JS concorda com o Elixir.
  """
  alias BrdcCrypto.{Address, Bip39, Ed25519, Slip10}

  @coin_type 0x42524443

  @enforce_keys [:seed, :public_key, :address]
  defstruct [:seed, :public_key, :address]

  @type t :: %__MODULE__{seed: <<_::256>>, public_key: <<_::256>>, address: String.t()}

  @doc "Caminho de derivação da conta `account` e do endereço `index`."
  @spec path(non_neg_integer(), non_neg_integer()) :: String.t()
  def path(account \\ 0, index \\ 0), do: "m/44'/#{@coin_type}'/#{account}'/0'/#{index}'"

  @doc "Conta a partir de uma frase válida e passphrase opcional."
  @spec from_mnemonic(String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, t()} | {:error, atom()}
  def from_mnemonic(mnemonic, passphrase \\ "", account \\ 0, index \\ 0) do
    with {:ok, _entropy} <- Bip39.to_entropy(mnemonic),
         {:ok, node_key} <-
           mnemonic |> Bip39.to_seed(passphrase) |> Slip10.derive(path(account, index)) do
      {:ok, from_seed(node_key.key)}
    end
  end

  @doc "Conta a partir da semente privada de 32 bytes."
  @spec from_seed(<<_::256>>) :: t()
  def from_seed(<<_::256>> = seed) do
    pub = Ed25519.public_key(seed)
    %__MODULE__{seed: seed, public_key: pub, address: Address.from_public_key(pub)}
  end

  @doc "Assina uma mensagem com a conta."
  @spec sign(t(), binary()) :: <<_::512>>
  def sign(%__MODULE__{seed: seed}, message), do: Ed25519.sign(message, seed)

  defimpl Inspect do
    def inspect(%{address: address}, _opts),
      do: "#BrdcCrypto.Account<#{address}, seed: [REDACTED]>"
  end
end
