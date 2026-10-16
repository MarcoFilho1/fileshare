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

  // a animação do Mac e do tablet só roda quando está visível
  var scene = document.getElementById("scene");
  if (scene && "IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      scene.classList.toggle("paused", !entries[0].isIntersecting);
    }).observe(scene);
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
