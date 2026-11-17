defmodule BrdcLedger.Credentials do
  @moduledoc """
  Credenciais (Fase 5, ADR-0019): tipos com órgão M-de-N, emissão com janela de contestação,
  validade, veto, contestação pelo titular e revogação. **Puro**: o "agora" é `state.time`.

  Tipos de transação: `14` tipo · `15` emissão · `16` contestação (titular) · `17` veto (órgão) ·
  `18` ativação (qualquer um, depois da janela) · `19` revogação (órgão).

  Estados de uma credencial: `:pending` → `:active` | `:contested` | `:vetoed`; `:pending` ou
  `:active` → `:revoked`. A entrada **nunca é apagada**: o `cred_id` fica queimado, então uma
  aprovação do órgão não emite duas vezes.
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.{Approvals, Params, State}

  @list_approvals {:list, :bytes}
  @privacy %{0 => :public, 1 => :private}

  @spec kinds() :: Range.t()
  def kinds, do: 14..19

  @doc "Taxa mínima (ADR-0014/0019): emissão e revogação 0,01; tipo 0,05; o resto sem mínimo."
  @spec min_fee(Params.t(), 14..19) :: non_neg_integer()
  def min_fee(%Params{} = p, 14), do: p.asset_register_fee
  def min_fee(%Params{} = p, kind) when kind in [15, 19], do: p.credential_fee
  def min_fee(%Params{}, _kind), do: 0

  @doc "A credencial está ativa e não expirou neste instante (`now` em segundos)?"
  @spec valid?(State.t(), String.t(), non_neg_integer()) :: boolean()
  def valid?(%State{credentials: c}, id, now) do
    case Map.fetch(c, id) do
      {:ok, %{status: :active, expires_at: e}} -> e == 0 or now < e
      _ -> false
    end
  end

  # --- documentos que o órgão / as autoridades assinam -----------------------------------

  @typedoc """
  Especificação de um tipo: `:id`, `:organ` (chaves), `:threshold`, `:contest` (janela em s),
  `:validity` (s, `0` = não expira), `:privacy` (`0` pública, `1` privada), `:ref_type` (`""` = sem
  referência) e `:revokes` (`1` = ao ativar, revoga a credencial referenciada).
  """
  @type spec :: %{
          id: String.t(),
          organ: [binary()],
          threshold: pos_integer(),
          contest: pos_integer(),
          validity: non_neg_integer(),
          privacy: 0 | 1,
          ref_type: String.t(),
          revokes: 0 | 1
        }

  @spec type_doc(String.t(), spec()) :: binary()
  def type_doc(chain, t) do
    doc(
      "type",
      [:string, :string, {:list, {:fixed, 32}}, :u32, :u64, :u64, :u8, :string, :u8],
      [chain, t.id, t.organ, t.threshold, t.contest, t.validity, t.privacy, t.ref_type, t.revokes]
    )
  end

  @spec issue_doc(String.t(), String.t(), String.t(), binary(), binary(), String.t()) :: binary()
  def issue_doc(chain, type, id, subject, data, ref) do
    doc("issue", [:string, :string, :string, {:fixed, 32}, :bytes, :string], [
      chain,
      type,
      id,
      subject,
      data,
      ref
    ])
  end

  @spec veto_doc(String.t(), String.t(), non_neg_integer()) :: binary()
  def veto_doc(chain, id, issued_at),
    do: doc("veto", [:string, :string, :u64], [chain, id, issued_at])

  @spec revoke_doc(String.t(), String.t(), String.t()) :: binary()
  def revoke_doc(chain, id, reason),
    do: doc("revoke", [:string, :string, :string], [chain, id, reason])

  defp doc(op, schema, values),
    do: Hash.tagged("brdc/cred/" <> op, Encoding.encode(schema, values))

  # --- cargas ---------------------------------------------------------------------------------

  @spec type_payload(spec(), [binary()]) :: binary()
  def type_payload(t, approvals) do
    Encoding.encode(
      [:string, {:list, {:fixed, 32}}, :u32, :u64, :u64, :u8, :string, :u8, @list_approvals],
      [
        t.id,
        t.organ,
        t.threshold,
        t.contest,
        t.validity,
        t.privacy,
        t.ref_type,
        t.revokes,
        approvals
      ]
    )
  end

  @spec issue_payload(String.t(), String.t(), binary(), binary(), String.t(), [binary()]) ::
          binary()
  def issue_payload(type, id, subject, data, ref, approvals) do
    Encoding.encode(
      [:string, :string, {:fixed, 32}, :bytes, :string, @list_approvals],
      [type, id, subject, data, ref, approvals]
    )
  end

  @spec id_payload(String.t()) :: binary()
  def id_payload(id), do: Encoding.encode([:string], [id])

  @spec veto_payload(String.t(), [binary()]) :: binary()
  def veto_payload(id, approvals),
    do: Encoding.encode([:string, @list_approvals], [id, approvals])

  @spec revoke_payload(String.t(), String.t(), [binary()]) :: binary()
  def revoke_payload(id, reason, approvals),
    do: Encoding.encode([:string, :string, @list_approvals], [id, reason, approvals])

  # --- execução ---------------------------------------------------------------------------------

  @spec run(State.t(), <<_::256>>, 14..19, binary()) :: {:ok, State.t()} | {:error, atom()}
  def run(s, _sender, 14, payload) do
    schema = [
      :string,
      {:list, {:fixed, 32}},
      :u32,
      :u64,
      :u64,
      :u8,
      :string,
      :u8,
      @list_approvals
    ]

    with {:ok, [id, organ, threshold, contest, validity, privacy, ref_type, revokes, approvals]} <-
           decode(payload, schema),
         :ok <- check(id_ok?(id, 32), :bad_id),
         :ok <- check(not Map.has_key?(s.cred_types, id), :type_exists),
         :ok <- check(organ_ok?(organ, threshold), :bad_type),
         :ok <- check(contest in s.params.min_window..s.params.max_window//1, :bad_type),
         :ok <- check(Map.has_key?(@privacy, privacy) and revokes in [0, 1], :bad_type),
         :ok <- check(ref_ok?(s, ref_type, revokes), :bad_type),
         :ok <- check(s.params.authorities != [], :no_authority),
         spec = %{
           id: id,
           organ: organ,
           threshold: threshold,
           contest: contest,
           validity: validity,
           privacy: privacy,
           ref_type: ref_type,
           revokes: revokes
         },
         d = type_doc(s.params.chain_id, spec),
         :ok <-
           check(
             Approvals.enough?(d, approvals, s.params.authorities, s.params.authority_threshold),
             :not_enough_approvals
           ) do
      type = %{
        organ: organ,
        threshold: threshold,
        contest_window: contest,
        validity: validity,
        privacy: Map.fetch!(@privacy, privacy),
        ref_type: ref_type,
        revokes_ref: revokes == 1
      }

      {:ok, %{s | cred_types: Map.put(s.cred_types, id, type)}}
    end
  end

  def run(s, _sender, 15, payload) do
    with {:ok, [type_id, id, subject, data, ref, approvals]} <-
           decode(payload, [:string, :string, {:fixed, 32}, :bytes, :string, @list_approvals]),
         {:ok, type} <- check_issue(s, type_id, id, subject, data, ref),
         d = issue_doc(s.params.chain_id, type_id, id, subject, data, ref),
         :ok <- organ_approved(type, d, approvals) do
      cred = %{
        type: type_id,
        subject: subject,
        data: data,
        ref: ref,
        status: :pending,
        issued_at: s.time,
        active_at: s.time + type.contest_window,
        expires_at: if(type.validity == 0, do: 0, else: s.time + type.validity)
      }

      {:ok, %{s | credentials: Map.put(s.credentials, id, cred)}}
    end
  end

  def run(s, sender, 16, payload) do
    with {:ok, [id]} <- decode(payload, [:string]),
         {:ok, cred} <- fetch(s.credentials, id, :no_credential),
         :ok <- check(cred.subject == sender, :not_subject),
         :ok <- check(cred.status == :pending, :bad_status),
         :ok <- check(s.time < cred.active_at, :window_closed) do
      {:ok, put_status(s, id, :contested)}
    end
  end

  def run(s, _sender, 17, payload) do
    with {:ok, [id, approvals]} <- decode(payload, [:string, @list_approvals]),
         {:ok, cred} <- fetch(s.credentials, id, :no_credential),
         :ok <- check(cred.status == :pending, :bad_status),
         :ok <- check(s.time < cred.active_at, :window_closed),
         d = veto_doc(s.params.chain_id, id, cred.issued_at),
         :ok <- organ_approved(s.cred_types[cred.type], d, approvals) do
      {:ok, put_status(s, id, :vetoed)}
    end
  end

  def run(s, _sender, 18, payload) do
    with {:ok, [id]} <- decode(payload, [:string]),
         {:ok, cred} <- fetch(s.credentials, id, :no_credential),
         :ok <- check(cred.status == :pending, :bad_status),
         :ok <- check(s.time >= cred.active_at, :window_open) do
      s = put_status(s, id, :active)
      {:ok, revoke_referenced(s, cred)}
    end
  end

  def run(s, _sender, 19, payload) do
    with {:ok, [id, reason, approvals]} <- decode(payload, [:string, :string, @list_approvals]),
         {:ok, cred} <- fetch(s.credentials, id, :no_credential),
         :ok <- check(cred.status in [:pending, :active], :bad_status),
         :ok <- check(byte_size(reason) <= 128, :bad_id),
         d = revoke_doc(s.params.chain_id, id, reason),
         :ok <- organ_approved(s.cred_types[cred.type], d, approvals) do
      {:ok, put_status(s, id, :revoked)}
    end
  end

  @doc """
  Confere os campos de uma emissão (tipo existente, id livre, dados no formato do tipo, referência válida),
  **sem** as aprovações. Usado na execução e pelo nó para aceitar propostas. Devolve o tipo.
  """
  @spec check_issue(State.t(), String.t(), String.t(), binary(), binary(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def check_issue(s, type_id, id, subject, data, ref) do
    with {:ok, type} <- fetch(s.cred_types, type_id, :no_type),
         :ok <- check(id_ok?(id, 64), :bad_id),
         :ok <- check(not Map.has_key?(s.credentials, id), :credential_exists),
         :ok <- check(data_ok?(type, data), :bad_data),
         :ok <- check_ref(s, type, ref, subject) do
      {:ok, type}
    end
  end

  # ao ativar um divórcio (tipo que revoga a referência), o casamento referenciado é revogado
  defp revoke_referenced(s, %{type: type_id, ref: ref}) do
    with true <- s.cred_types[type_id].revokes_ref,
         %{status: :active} <- s.credentials[ref] do
      put_status(s, ref, :revoked)
    else
      _ -> s
    end
  end

  defp put_status(s, id, status),
    do: %{s | credentials: Map.update!(s.credentials, id, &%{&1 | status: status})}

  # --- validações ----------------------------------------------------------------------------------

  defp ref_ok?(_s, "", 0), do: true

  defp ref_ok?(s, ref_type, revokes),
    do: ref_type != "" and Map.has_key?(s.cred_types, ref_type) and revokes in [0, 1]

  defp check_ref(_s, %{ref_type: ""}, "", _subject), do: :ok
  defp check_ref(_s, %{ref_type: ""}, _ref, _subject), do: {:error, :bad_ref}

  defp check_ref(s, %{ref_type: rt}, ref, subject) do
    case Map.fetch(s.credentials, ref) do
      {:ok, %{type: ^rt, subject: ^subject, status: :active}} -> :ok
      _ -> {:error, :bad_ref}
    end
  end

  defp data_ok?(%{privacy: :private}, data), do: byte_size(data) == 32
  defp data_ok?(%{privacy: :public}, data), do: byte_size(data) <= 512

  defp organ_approved(type, doc, approvals) do
    check(Approvals.enough?(doc, approvals, type.organ, type.threshold), :not_enough_approvals)
  end

  defp organ_ok?(organ, threshold) do
    length(organ) in 1..16 and length(Enum.uniq(organ)) == length(organ) and threshold >= 1 and
      threshold <= length(organ)
  end

  defp id_ok?(id, max), do: byte_size(id) in 1..max and String.printable?(id)

  defp fetch(map, key, reason) do
    case Map.fetch(map, key) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, reason}
    end
  end

  defp decode(payload, schema) do
    case Encoding.decode(schema, payload) do
      {:ok, v} -> {:ok, v}
      _ -> {:error, :bad_payload}
    end
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
