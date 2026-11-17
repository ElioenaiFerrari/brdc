defmodule BrdcNode.Keygen do
  @moduledoc """
  Gera e carrega a chave de um validador ou emissor (Fase 4).

  A **semente privada** (32 bytes) nasce aqui, com o acaso criptográfico do sistema, e é gravada
  em `<dir>/<nome>.seed` (hexadecimal) com permissão `0600`, **sem nunca sobrescrever** um arquivo
  existente. A chave pública vai para `<dir>/<nome>.pub`. A semente nunca é impressa nem devolvida
  em texto; `.seed` está no `.gitignore`. Na BEAM não há zeroização de memória (limite documentado).
  """
  alias BrdcCrypto.Ed25519

  @name ~r/\A[a-z0-9_-]{1,32}\z/

  @type result :: %{seed_path: Path.t(), pub_path: Path.t(), public_key: <<_::256>>}

  @doc "Gera `<nome>.seed` e `<nome>.pub` em `dir`. Recusa nome inválido e arquivo existente."
  @spec generate(Path.t(), String.t()) ::
          {:ok, result()} | {:error, :invalid_name | :exists | File.posix()}
  def generate(dir, name) when is_binary(dir) and is_binary(name) do
    seed_path = Path.join(dir, name <> ".seed")
    pub_path = Path.join(dir, name <> ".pub")

    with :ok <- check_name(name),
         :ok <- File.mkdir_p(dir),
         _ = File.chmod(dir, 0o700),
         :ok <- check_absent([seed_path, pub_path]),
         seed = :crypto.strong_rand_bytes(32),
         :ok <- write_secret(seed_path, Base.encode16(seed, case: :lower) <> "\n"),
         pub = Ed25519.public_key(seed),
         :ok <- File.write(pub_path, Base.encode16(pub, case: :lower) <> "\n") do
      {:ok, %{seed_path: seed_path, pub_path: pub_path, public_key: pub}}
    end
  end

  @doc "Lê a semente; recusa arquivo legível por grupo ou outros."
  @spec load_seed(Path.t()) ::
          {:ok, <<_::256>>} | {:error, :insecure_permissions | :malformed | File.posix()}
  def load_seed(path) do
    with {:ok, %File.Stat{mode: mode}} <- File.stat(path),
         :ok <- check_private(mode),
         {:ok, text} <- File.read(path) do
      decode_hex32(text)
    end
  end

  @doc "Lê uma chave pública (hexadecimal de 64 caracteres)."
  @spec load_public(Path.t()) :: {:ok, <<_::256>>} | {:error, :malformed | File.posix()}
  def load_public(path) do
    with {:ok, text} <- File.read(path), do: decode_hex32(text)
  end

  defp check_name(name), do: if(name =~ @name, do: :ok, else: {:error, :invalid_name})

  defp check_absent(paths),
    do: if(Enum.any?(paths, &File.exists?/1), do: {:error, :exists}, else: :ok)

  # cria vazio e exclusivo, fecha a permissão ANTES de escrever o segredo
  defp write_secret(path, content) do
    with {:ok, io} <- File.open(path, [:write, :exclusive]),
         :ok <- File.chmod(path, 0o600),
         :ok <- IO.binwrite(io, content) do
      File.close(io)
    end
  end

  defp check_private(mode) do
    if Bitwise.band(mode, 0o077) == 0, do: :ok, else: {:error, :insecure_permissions}
  end

  defp decode_hex32(text) do
    case text |> String.trim() |> Base.decode16(case: :mixed) do
      {:ok, <<_::256>> = bin} -> {:ok, bin}
      _ -> {:error, :malformed}
    end
  end
end
