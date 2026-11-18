defmodule BrdcDev.Wallets do
  @moduledoc """
  Carteiras de TESTE nomeadas, guardadas em `net/wallets/NOME.json` (fora do git). **Só desenvolvimento:** a frase
  fica em texto puro no arquivo, porque serve para as ferramentas assinarem por você. No produto a frase nasce
  e vive só no navegador (ADR-0020/0021); aqui o objetivo é simular pessoas (Alice, Bob) sem abrir o navegador.
  """
  alias BrdcCrypto.{Account, Address, Bip39}

  @name ~r/\A[a-z0-9][a-z0-9_-]{0,31}\z/

  @type wallet :: %{name: String.t(), mnemonic: String.t(), account: Account.t()}

  @spec dir(Path.t()) :: Path.t()
  def dir(net_dir), do: Path.join(net_dir, "wallets")

  @doc "Nome válido: minúsculas, dígitos, `-` e `_`, até 32 caracteres."
  @spec valid_name?(term()) :: boolean()
  def valid_name?(name), do: is_binary(name) and Regex.match?(@name, name)

  @doc "Cria uma carteira de teste nova (frase de 12 palavras). Recusa nome repetido e nome inválido."
  @spec create(Path.t(), String.t()) :: {:ok, wallet()} | {:error, :bad_name | :exists}
  def create(net_dir, name) do
    cond do
      not valid_name?(name) ->
        {:error, :bad_name}

      File.exists?(path(net_dir, name)) ->
        {:error, :exists}

      true ->
        mnemonic = Bip39.generate(128)
        File.mkdir_p!(dir(net_dir))
        {:ok, account} = Account.from_mnemonic(mnemonic, "")

        File.write!(
          path(net_dir, name),
          JSON.encode!(%{"name" => name, "mnemonic" => mnemonic, "address" => account.address}) <>
            "\n"
        )

        {:ok, %{name: name, mnemonic: mnemonic, account: account}}
    end
  end

  @doc "Cria a carteira se ainda não existe; devolve a existente senão."
  @spec ensure(Path.t(), String.t()) :: {:ok, wallet()} | {:error, term()}
  def ensure(net_dir, name) do
    case create(net_dir, name) do
      {:error, :exists} -> load(net_dir, name)
      other -> other
    end
  end

  @spec load(Path.t(), String.t()) ::
          {:ok, wallet()} | {:error, :bad_name | :not_found | :corrupt}
  def load(net_dir, name) do
    with true <- valid_name?(name) || {:error, :bad_name},
         {:ok, text} <- File.read(path(net_dir, name)) |> or_not_found(),
         {:ok, %{"mnemonic" => mnemonic}} <- JSON.decode(text) |> or_corrupt(),
         {:ok, account} <- Account.from_mnemonic(mnemonic, "") |> or_corrupt() do
      {:ok, %{name: name, mnemonic: mnemonic, account: account}}
    end
  end

  @doc "Nomes das carteiras de teste, em ordem."
  @spec names(Path.t()) :: [String.t()]
  def names(net_dir) do
    net_dir
    |> dir()
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".json"))
    |> Enum.sort()
  end

  @doc """
  Resolve quem é: o nome de uma carteira de teste (`{:wallet, wallet}`, com chave para assinar) ou um endereço
  `brdc1…` (`{:address, hash}`, só para receber ou consultar).
  """
  @spec resolve(Path.t(), String.t()) ::
          {:wallet, wallet()} | {:address, <<_::256>>} | {:error, term()}
  def resolve(net_dir, who) do
    if String.starts_with?(who, "brdc1") do
      case Address.decode(who) do
        {:ok, hash} -> {:address, hash}
        {:error, reason} -> {:error, {:bad_address, reason}}
      end
    else
      with {:ok, w} <- load(net_dir, who), do: {:wallet, w}
    end
  end

  @doc "Endereço (hash de 32 bytes) de quem foi resolvido."
  @spec hash({:wallet, wallet()} | {:address, <<_::256>>}) :: <<_::256>>
  def hash({:wallet, w}), do: Address.hash(w.account.public_key)
  def hash({:address, h}), do: h

  defp path(net_dir, name), do: Path.join(dir(net_dir), name <> ".json")

  defp or_not_found({:error, :enoent}), do: {:error, :not_found}
  defp or_not_found(other), do: other
  defp or_corrupt({:ok, _} = ok), do: ok
  defp or_corrupt(_), do: {:error, :corrupt}
end
