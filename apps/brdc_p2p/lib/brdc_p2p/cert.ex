defmodule BrdcP2p.Cert do
  @moduledoc """
  Certificado X.509 autoassinado a partir da semente Ed25519 do validador (ADR-0015).

  Não há autoridade certificadora: o certificado só existe para o TLS aceitar a chave. A
  confiança vem de a chave pública estar no conjunto de validadores, conferida em
  `BrdcP2p.Channel`. Nome e validade são fixos e sem significado de segurança.
  """

  @ed25519 {1, 3, 101, 112}

  @type t :: %{der: binary(), key: {:ECPrivateKey, binary()}, public_key: <<_::256>>}

  @doc "Gera o certificado e a chave privada no formato que o `:ssl` espera."
  @spec generate(<<_::256>>) :: t()
  def generate(<<_::256>> = seed) do
    {pub, _} = :crypto.generate_key(:eddsa, :ed25519, seed)
    priv = {:ECPrivateKey, 1, seed, {:namedCurve, @ed25519}, pub, :asn1_NOVALUE}

    dn =
      {:rdnSequence, [[{:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, "brdc-validator"}}]]}

    alg = {:SignatureAlgorithm, @ed25519, :asn1_NOVALUE}

    tbs =
      {:OTPTBSCertificate, :v3, 1, alg, dn,
       {:Validity, {:utcTime, ~c"260101000000Z"}, {:generalTime, ~c"20500101000000Z"}}, dn,
       {:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, @ed25519, :asn1_NOVALUE},
        {:ECPoint, pub}}, :asn1_NOVALUE, :asn1_NOVALUE, []}

    %{
      der: :public_key.pkix_sign(tbs, priv),
      key: {:ECPrivateKey, :public_key.der_encode(:ECPrivateKey, priv)},
      public_key: pub
    }
  end

  @doc "Chave pública Ed25519 de um certificado (DER ou já decodificado). `:error` se não for Ed25519."
  @spec public_key(binary() | tuple()) :: {:ok, <<_::256>>} | :error
  def public_key(der) when is_binary(der) do
    der |> :public_key.pkix_decode_cert(:otp) |> public_key()
  rescue
    _ -> :error
  end

  def public_key({:OTPCertificate, tbs, _, _}) when is_tuple(tbs) do
    case elem(tbs, 7) do
      {:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, @ed25519, _}, {:ECPoint, <<_::256>> = pub}} ->
        {:ok, pub}

      _ ->
        :error
    end
  end

  def public_key(_), do: :error
end
