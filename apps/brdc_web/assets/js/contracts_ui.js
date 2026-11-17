// Textos em português dos modelos de contrato (a lógica e as regras vêm do Elixir: ver crypto/contracts.mjs).
// `type`: "brdc" (valor em BRDC), "minutes" (digitado em minutos), "days" (em dias) ou "count" (inteiro).
export const UI = {
  "compra-venda": {
    short: "cv",
    title: "Compra e venda",
    help: "O comprador deposita o preço na rede e confirma o recebimento para liberá-lo ao vendedor. Se o prazo vencer sem confirmação, o dinheiro volta ao comprador.",
    roles: { a: "Vendedor", b: "Comprador" },
    terms: {
      price: { label: "Preço (BRDC)", type: "brdc" },
      duration: { label: "Prazo para confirmar (minutos)", type: "minutes" },
    },
    states: { open: ["Aguardando o comprador", "yellow"], funded: ["Dinheiro retido na rede", "blue"], done: ["Concluído", "green"], refunded: ["Devolvido ao comprador", "neutral"], cancelled: ["Cancelado", "neutral"] },
    actions: { accept: "Aceitar e depositar o preço", confirm: "Confirmar recebimento", refund: "Devolver o dinheiro", refund_expired: "Devolver ao comprador (prazo vencido)", cancel: "Cancelar" },
  },
  aluguel: {
    short: "al",
    title: "Aluguel",
    help: "O locatário deposita uma caução e paga as parcelas direto ao locador. No fim, a caução cobre as parcelas em aberto e o resto volta ao locatário.",
    roles: { a: "Locador", b: "Locatário" },
    terms: {
      rent: { label: "Valor da parcela (BRDC)", type: "brdc" },
      period: { label: "Intervalo entre parcelas (dias)", type: "days" },
      periods: { label: "Número de parcelas", type: "count" },
      deposit: { label: "Caução (BRDC)", type: "brdc" },
      grace: { label: "Tolerância no fim (dias)", type: "days" },
    },
    states: { open: ["Aguardando o locatário", "yellow"], active: ["Em andamento", "blue"], closed: ["Encerrado", "green"], cancelled: ["Cancelado", "neutral"] },
    actions: { accept: "Aceitar e depositar a caução", pay_rent: "Pagar uma parcela", settle: "Encerrar e liquidar a caução", settle_paid: "Liberar a caução (tudo pago)", cancel: "Cancelar" },
  },
  emprestimo: {
    short: "em",
    title: "Empréstimo",
    help: "O credor deixa o valor retido ao criar; o devedor aceita e recebe, e devolve o valor combinado (juros, se houver, já dentro dele). Sem garantia: o atraso só é registrado.",
    roles: { a: "Credor", b: "Devedor" },
    terms: {
      principal: { label: "Valor emprestado (BRDC)", type: "brdc" },
      repay: { label: "Valor a devolver (BRDC)", type: "brdc" },
      duration: { label: "Prazo para devolver (dias)", type: "days" },
    },
    states: { open: ["Aguardando o devedor", "yellow"], active: ["Em andamento", "blue"], repaid: ["Pago", "green"], defaulted: ["Em atraso (registrado)", "yellow"], cancelled: ["Cancelado", "neutral"] },
    actions: { accept: "Aceitar e receber o valor", repay: "Devolver o valor", mark_default: "Registrar o atraso", cancel: "Cancelar e recuperar o valor" },
  },
};

export const TYPE_FACTOR = { minutes: 60n, days: 86_400n };
