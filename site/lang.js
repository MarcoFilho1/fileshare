// Idioma da página: ?lang=pt|en no link, ou a escolha feita no seletor PT | EN (guardada neste
// navegador), ou o idioma do aparelho. Roda no <head> para a página já abrir no idioma certo.
(function () {
  "use strict";
  var root = document.documentElement;
  function stored() { try { return localStorage.getItem("fileshare-lang"); } catch (e) { return null; } }
  function store(v) { try { localStorage.setItem("fileshare-lang", v); } catch (e) {} }
  var param = new URLSearchParams(location.search).get("lang");
  if (param === "pt" || param === "en") store(param);
  var lang = param || stored() || ((navigator.language || "pt").toLowerCase().startsWith("pt") ? "pt" : "en");
  function apply(l) {
    root.classList.toggle("en", l === "en");
    root.lang = l === "en" ? "en" : "pt-BR";
    document.querySelectorAll(".lang-switch button").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.lang === l));
    });
  }
  apply(lang);
  document.addEventListener("DOMContentLoaded", function () {
    apply(lang);
    document.querySelectorAll(".lang-switch button").forEach(function (b) {
      b.addEventListener("click", function () { lang = b.dataset.lang; store(lang); apply(lang); });
    });
  });
})();
