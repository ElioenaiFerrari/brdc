defmodule Mix.Tasks.Brdc.Devnet.Reset do
  @shortdoc "Apaga o disco da rede de teste local (volta à gênese)"
  @moduledoc """
  Apaga os blocos e as propostas gravados em disco pela rede de teste local (`net/data`), para ela
  recomeçar da gênese na próxima subida. **Não** apaga as chaves de teste.

      mix brdc.devnet.reset [--port 4545] [--dir net]

  Recusa se houver um nó respondendo na porta (pare o nó antes). Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.Devnet

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [port: :integer, dir: :string])
    port = opts[:port] || 4545
    data = Path.join(opts[:dir] || Devnet.default_dir(), "data")

    case :gen_tcp.connect(~c"127.0.0.1", port, [], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        Mix.raise("há um nó respondendo na porta #{port}; pare-o antes de apagar o disco")

      {:error, _} ->
        if File.dir?(data) do
          File.rm_rf!(data)
          Mix.shell().info("disco apagado: #{data}")
        else
          Mix.shell().info("nada a apagar (#{data} não existe)")
        end
    end
  end
end
