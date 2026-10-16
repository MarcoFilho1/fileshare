// Página do QR de pareamento: lê os campos depois do "#", tira a chave do endereço (e do
// histórico) e abre o app com fileshare://pair?... Se o app não estiver instalado, o Chrome volta
// para esta mesma página com #instalar (só muda o "#", então a chave continua na memória) e ela
// mostra como instalar. Nada é enviado a lugar nenhum.
(function () {
  "use strict";
  var PACKAGE = "dev.marcofilho.fileshare";
  var $ = function (id) { return document.getElementById(id); };

  var fields = new URLSearchParams(location.hash.slice(1));
  var key = fields.get("k") || "";
  var valid = fields.get("v") === "1" && fields.get("id") && /^[A-Za-z0-9_-]{43}$/.test(key);

  // a chave sai da barra de endereço e do histórico logo depois de lida
  history.replaceState(null, "", location.pathname);

  if (!valid) {
    $("invalid").classList.remove("hidden");
    return;
  }

  var query = new URLSearchParams({ v: "1", id: fields.get("id"), name: fields.get("name") || "Mac", k: key }).toString();
  var direct = "fileshare://pair?" + query;
  var back = location.origin + location.pathname + "#instalar";
  var intent = "intent://pair?" + query + "#Intent;scheme=fileshare;package=" + PACKAGE +
    ";S.browser_fallback_url=" + encodeURIComponent(back) + ";end";

  document.querySelectorAll(".mac-name").forEach(function (el) { el.textContent = fields.get("name") || "Mac"; });
  $("ready").classList.remove("hidden");

  function showInstall() {
    $("install").classList.remove("hidden");
    $("show-install").classList.add("hidden");
  }

  $("connect").addEventListener("click", function (e) {
    e.preventDefault();
    var android = /Android/i.test(navigator.userAgent);
    location.href = android ? intent : direct;
    // se nada abriu em pouco tempo (outro navegador), oferece o link direto
    setTimeout(function () { if (!document.hidden) $("direct").classList.remove("hidden"); }, 2500);
  });
  ["direct-link", "direct-link-en"].forEach(function (id) {
    $(id).addEventListener("click", function (e) { e.preventDefault(); location.href = direct; });
  });
  $("show-install").addEventListener("click", function (e) { e.preventDefault(); showInstall(); });

  // o Chrome voltou com #instalar: o app não está no tablet
  window.addEventListener("hashchange", function () {
    if (location.hash === "#instalar") {
      showInstall();
      history.replaceState(null, "", location.pathname);
    }
  });
})();
