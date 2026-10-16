// FileShare: interações do site. Revela os blocos ao rolar, deixa o menu de vidro, destaca o
// download certo para o aparelho e abre as perguntas com animação. Nada é enviado a lugar nenhum.
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.add("js");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // menu: transparente no topo, vidro ao rolar
  var nav = document.getElementById("nav");
  function onScroll() { nav.classList.toggle("scrolled", window.scrollY > 12); }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // blocos aparecem ao entrar na tela
  var items = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  }

  // as animações dos aparelhos só rodam quando estão visíveis
  var scene = document.getElementById("scene");
  if ("IntersectionObserver" in window) {
    var pauser = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { e.target.classList.toggle("paused", !e.isIntersecting); });
    });
    document.querySelectorAll(".scene").forEach(function (el) { pauser.observe(el); });
  }

  // no Android, o download do Android vem primeiro e em destaque
  if (/Android/i.test(navigator.userAgent)) {
    document.querySelectorAll(".hero-actions").forEach(function (group) {
      var mac = group.querySelector('[data-os="mac"]');
      var android = group.querySelector('[data-os="android"]');
      if (!mac || !android) return;
      mac.classList.replace("btn-ink", "btn-ghost");
      android.classList.replace("btn-ghost", "btn-ink");
      group.insertBefore(android, mac);
    });
  }

  // baixar para Mac: o download começa e a janela explica o aviso da primeira abertura
  var help = document.getElementById("mac-help");
  if (help && help.showModal) {
    var openHelp = function () { help.showModal(); };
    document.querySelectorAll('[data-os="mac"]').forEach(function (a) { a.addEventListener("click", openHelp); });
    document.querySelectorAll("[data-mac-help]").forEach(function (a) {
      a.addEventListener("click", function (e) { e.preventDefault(); openHelp(); });
    });
    help.querySelectorAll(".close, .ok").forEach(function (b) { b.addEventListener("click", function () { help.close(); }); });
    help.addEventListener("click", function (e) { if (e.target === help) help.close(); });
  }

  // perguntas: abre e fecha deslizando
  document.querySelectorAll(".faq details").forEach(function (d) {
    var summary = d.querySelector("summary");
    var answer = d.querySelector(".answer");
    summary.addEventListener("click", function (e) {
      if (reduce) return;
      e.preventDefault();
      if (d.open) {
        var h = answer.scrollHeight;
        answer.animate([{ height: h + "px", opacity: 1 }, { height: "0px", opacity: 0 }], { duration: 320, easing: "cubic-bezier(.22,1,.36,1)" })
          .onfinish = function () { d.open = false; };
      } else {
        d.open = true;
        var target = answer.scrollHeight;
        answer.animate([{ height: "0px", opacity: 0 }, { height: target + "px", opacity: 1 }], { duration: 420, easing: "cubic-bezier(.22,1,.36,1)" });
      }
    });
  });

  // leve profundidade: a cena sobe um pouco mais devagar que a página
  if (scene && !reduce) {
    var ticking = false;
    window.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(function () {
        var y = Math.min(window.scrollY, 900);
        scene.style.transform = "translateY(" + (y * -0.06).toFixed(1) + "px)";
        ticking = false;
      });
    }, { passive: true });
  }
})();
