// Compartilha a sessão da carteira (que guarda a conta destravada só em memória) entre os hooks.
let session = null;
export const setSession = (s) => {
  session = s;
};
export const getSession = () => session;
