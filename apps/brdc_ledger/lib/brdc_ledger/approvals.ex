defmodule BrdcLedger.Approvals do
  @moduledoc """
  Aprovações M-de-N sobre um documento (Fase 2 e 5). Cada aprovação é `chave_pública ‖ assinatura`
  (96 bytes). Conta uma vez cada chave **distinta** do conjunto autorizado cuja assinatura confere;
  aprovação malformada, repetida ou de fora do conjunto não conta.

  Usado pelos emissores (mint, burn, atestado), pelas autoridades raiz (classes, tipos) e pelos
  órgãos (registro de bens, veto, gravames, credenciais).
  """
  alias BrdcCrypto.Ed25519

  @doc "Monta uma aprovação com a semente privada de quem aprova."
  @spec approval(binary(), <<_::256>>) :: binary()
  def approval(doc, <<_::256>> = seed), do: Ed25519.public_key(seed) <> Ed25519.sign(doc, seed)

  @doc "Chaves distintas do conjunto `keys` que assinaram `doc` corretamente."
  @spec signers(binary(), [binary()], [<<_::256>>]) :: [<<_::256>>]
  def signers(doc, approvals, keys) when is_list(approvals) do
    for <<pub::binary-32, sig::binary-64>> <- approvals,
        pub in keys,
        Ed25519.verify(doc, sig, pub),
        uniq: true,
        do: pub
  end

  @doc "Tem pelo menos `threshold` aprovações válidas?"
  @spec enough?(binary(), [binary()], [<<_::256>>], pos_integer()) :: boolean()
  def enough?(doc, approvals, keys, threshold) do
    length(signers(doc, approvals, keys)) >= threshold
  end
end
