// Mostra o texto em português num aparelho em português; em inglês nos demais.
if (!(navigator.language || "pt").toLowerCase().startsWith("pt")) {
  document.documentElement.classList.add("en");
  document.documentElement.lang = "en";
}
