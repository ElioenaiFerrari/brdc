defmodule Mix.Tasks.Brdc.Keygen do
  @shortdoc "Gera a chave de um validador ou emissor (semente 0600 + chave pública)"
  @moduledoc """
  Gera `<dir>/<nome>.seed` (privada, permissão 0600, nunca sobrescreve) e `<dir>/<nome>.pub`.

      mix brdc.keygen NOME [--dir net]

  Imprime só o endereço da chave pública. **Nunca** versione nem copie o `.seed`: ele é o
  validador. A pasta padrão (`net/`) está no `.gitignore`.
  """
  use Mix.Task
  alias BrdcNode.Keygen

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [dir: :string])

    case rest do
      [name] -> generate(Keyword.get(opts, :dir, "net"), name)
      _ -> Mix.raise("uso: mix brdc.keygen NOME [--dir net]")
    end
  end

  defp generate(dir, name) do
    case Keygen.generate(dir, name) do
      {:ok, r} ->
        Mix.shell().info("chave criada: #{r.seed_path} (privada, 0600) e #{r.pub_path}")
        Mix.shell().info("pública: #{Base.encode16(r.public_key, case: :lower)}")

      {:error, :exists} ->
        Mix.raise("já existe #{name}.seed ou #{name}.pub em #{dir}; não vou sobrescrever")

      {:error, :invalid_name} ->
        Mix.raise("nome inválido: use 1 a 32 caracteres entre a-z, 0-9, _ e -")

      {:error, reason} ->
        Mix.raise("não consegui criar a chave: #{inspect(reason)}")
    end
  end
end
