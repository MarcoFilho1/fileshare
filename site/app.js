// FileShare: interações do site. Nada é enviado a lugar nenhum.
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.add("js");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var $ = function (s, el) { return (el || document).querySelector(s); };
  var $$ = function (s, el) { return Array.prototype.slice.call((el || document).querySelectorAll(s)); };
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }

  // ---------- faixa de novidade (fechar fica lembrado) ----------
  var banner = $("#banner");
  if (banner) {
    if (store("fileshare-banner") === "v2.3.0") banner.classList.add("closed");
    $(".x", banner).addEventListener("click", function () { banner.classList.add("closed"); store("fileshare-banner", "v2.3.0"); });
  }

  // ---------- menu: borda ao rolar; tela cheia no celular ----------
  var nav = $("#nav");
  function onScroll() { nav.classList.toggle("scrolled", window.scrollY > 8); }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
  var sheet = $("#sheet-menu"), menuBtn = $(".menu-btn");
  function setMenu(open) {
    sheet.classList.toggle("open", open);
    sheet.setAttribute("aria-hidden", String(!open));
    menuBtn.setAttribute("aria-expanded", String(open));
    document.body.classList.toggle("locked", open);
  }
  menuBtn.addEventListener("click", function () { setMenu(true); });
  $(".close", sheet).addEventListener("click", function () { setMenu(false); });
  $$("nav a, .brand", sheet).forEach(function (a) { a.addEventListener("click", function () { setMenu(false); }); });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") setMenu(false); });

  // ---------- revelação ao rolar ----------
  if (reduce || !("IntersectionObserver" in window)) {
    $$(".reveal").forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.1 });
    $$(".reveal").forEach(function (el) { io.observe(el); });
  }

  // as cenas animadas só rodam quando estão visíveis
  if ("IntersectionObserver" in window) {
    var pauser = new IntersectionObserver(function (es) {
      es.forEach(function (e) { e.target.classList.toggle("paused", !e.isIntersecting); });
    });
    $$(".scene, .story-art").forEach(function (el) { pauser.observe(el); });
  }

  // ---------- no Android, o download do Android vem primeiro ----------
  if (/Android/i.test(navigator.userAgent)) {
    $$(".hero-actions").forEach(function (g) {
      var mac = $('[data-os="mac"]', g), and = $('[data-os="android"]', g);
      if (!mac || !and) return;
      mac.classList.replace("btn-ink", "btn-ghost"); and.classList.replace("btn-ghost", "btn-ink");
      g.insertBefore(and, mac);
    });
  }

  // ---------- baixar para Mac: janela com o passo a passo ----------
  var help = $("#mac-help");
  if (help && help.showModal) {
    var openHelp = function () { help.showModal(); };
    $$('[data-os="mac"]').forEach(function (a) { a.addEventListener("click", openHelp); });
    $$("[data-mac-help]").forEach(function (a) { a.addEventListener("click", function (e) { e.preventDefault(); openHelp(); }); });
    $$(".close, .ok", help).forEach(function (b) { b.addEventListener("click", function () { help.close(); }); });
    help.addEventListener("click", function (e) { if (e.target === help) help.close(); });
  }

  // ---------- perguntas: abre e fecha deslizando ----------
  $$(".faq details").forEach(function (d) {
    var answer = $(".answer", d);
    $("summary", d).addEventListener("click", function (e) {
      if (reduce) return;
      e.preventDefault();
      if (d.open) {
        answer.animate([{ height: answer.scrollHeight + "px", opacity: 1 }, { height: "0px", opacity: 0 }], { duration: 300, easing: "cubic-bezier(.22,1,.36,1)" }).onfinish = function () { d.open = false; };
      } else {
        d.open = true;
        answer.animate([{ height: "0px", opacity: 0 }, { height: answer.scrollHeight + "px", opacity: 1 }], { duration: 420, easing: "cubic-bezier(.22,1,.36,1)" });
      }
    });
  });

  // ---------- partículas ----------
  // Traços curtos espalhados num anel em volta do centro, girando devagar; perto do ponteiro eles
  // se afastam. Só azuis (e cinza no fundo claro).
  function field(canvas, opts) {
    if (!canvas) return;
    var ctx = canvas.getContext("2d"), dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0, pts = [], mouse = { x: -9999, y: -9999 }, visible = true, t0 = performance.now();
    function resize() {
      var r = canvas.getBoundingClientRect(); W = r.width; H = r.height;
      canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      var n = Math.round(Math.min(opts.max, (W * H) / opts.density));
      pts = [];
      for (var i = 0; i < n; i++) {
        var a = Math.random() * Math.PI * 2;
        var rr = opts.inner + Math.pow(Math.random(), 0.7) * (1 - opts.inner);
        pts.push({ a: a, r: rr, s: (0.4 + Math.random()) * opts.speed * (Math.random() < 0.5 ? 1 : 0.6), c: opts.colors[(Math.random() * opts.colors.length) | 0], l: 2 + Math.random() * 4, ox: 0, oy: 0 });
      }
    }
    function frame(now) {
      if (!visible) return;
      var t = (now - t0) / 1000;
      ctx.clearRect(0, 0, W, H);
      var cx = W / 2, cy = H * opts.cy, rx = W * opts.rx, ry = H * opts.ry;
      for (var i = 0; i < pts.length; i++) {
        var p = pts[i], a = p.a + (reduce ? 0 : t * p.s);
        var x = cx + Math.cos(a) * rx * p.r, y = cy + Math.sin(a) * ry * p.r;
        var dx = x - mouse.x, dy = y - mouse.y, d2 = dx * dx + dy * dy, R = 130;
        if (d2 < R * R) { var f = (1 - Math.sqrt(d2) / R) * 22; var d = Math.sqrt(d2) || 1; p.ox += (dx / d * f - p.ox) * 0.15; p.oy += (dy / d * f - p.oy) * 0.15; }
        else { p.ox *= 0.92; p.oy *= 0.92; }
        x += p.ox; y += p.oy;
        var tx = -Math.sin(a), ty = Math.cos(a) * (ry / rx);
        var tl = Math.sqrt(tx * tx + ty * ty) || 1; tx /= tl; ty /= tl;
        ctx.strokeStyle = p.c; ctx.lineWidth = opts.width; ctx.lineCap = "round";
        ctx.globalAlpha = opts.alpha * (0.35 + 0.65 * p.r);
        ctx.beginPath(); ctx.moveTo(x - tx * p.l / 2, y - ty * p.l / 2); ctx.lineTo(x + tx * p.l / 2, y + ty * p.l / 2); ctx.stroke();
      }
      ctx.globalAlpha = 1;
      if (!reduce) requestAnimationFrame(frame);
    }
    resize();
    window.addEventListener("resize", resize);
    var host = canvas.parentElement;
    host.addEventListener("pointermove", function (e) { var r = canvas.getBoundingClientRect(); mouse.x = e.clientX - r.left; mouse.y = e.clientY - r.top; });
    host.addEventListener("pointerleave", function () { mouse.x = mouse.y = -9999; });
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) {
        var was = visible; visible = es[0].isIntersecting;
        if (visible && !was) requestAnimationFrame(frame);
      }).observe(canvas);
    }
    requestAnimationFrame(frame);
  }
  var dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  field($("#field"), { max: 900, density: 1400, inner: 0.42, rx: 0.62, ry: 0.62, cy: 0.5, speed: 0.025, width: 1.6, alpha: dark ? 0.9 : 0.85,
    colors: dark ? ["#5b8fff", "#8fb4ff", "#2f6fea", "#3a3f4a"] : ["#1c5fe0", "#4ea6ff", "#2166f5", "#9db7ec", "#c4cbd6"] });
  field($("#grow-field"), { max: 700, density: 1600, inner: 0.25, rx: 0.7, ry: 0.75, cy: 0.5, speed: 0.02, width: 1.4, alpha: 0.75, colors: ["#5b8fff", "#8fb4ff", "#2f6fea", "#ffffff"] });
  field($("#night-field"), { max: 600, density: 1500, inner: 0.3, rx: 0.65, ry: 0.9, cy: 0.15, speed: 0.02, width: 1.4, alpha: 0.8, colors: ["#5b8fff", "#8fb4ff", "#2f6fea", "#ffffff"] });

  // ---------- rolagem: cartão que cresce e palavras que acendem ----------
  var card = $("#grow-card"), growSec = card && card.closest(".grow");
  var words = [];
  $$("[data-words]").forEach(function (p) {
    var parts = p.textContent.trim().split(/\s+/);
    p.textContent = "";
    parts.forEach(function (w, i) {
      var s = document.createElement("span"); s.className = "w"; s.textContent = w;
      p.appendChild(s); if (i < parts.length - 1) p.appendChild(document.createTextNode(" "));
    });
  });
  var ticking = false;
  function onScrollFx() {
    ticking = false;
    var vh = window.innerHeight;
    if (card && !reduce && window.innerWidth > 760) {
      var r = growSec.getBoundingClientRect();
      var p = Math.min(1, Math.max(0, -r.top / (r.height - vh) * 1.4));
      card.style.setProperty("--p", p.toFixed(3));
    }
    if (!reduce) {
      $$("[data-words]").forEach(function (p) {
        if (getComputedStyle(p).display === "none") return;
        var r = p.getBoundingClientRect();
        var prog = Math.min(1, Math.max(0, (vh * 0.85 - r.top) / (r.height + vh * 0.35)));
        var ws = $$(".w", p), on = Math.round(prog * ws.length);
        ws.forEach(function (w, i) { w.classList.toggle("on", i < on); });
      });
    }
  }
  window.addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(onScrollFx); } }, { passive: true });
  window.addEventListener("resize", onScrollFx);
  onScrollFx();
  // o idioma pode trocar o parágrafo visível
  $$(".lang-switch button").forEach(function (b) { b.addEventListener("click", function () { setTimeout(onScrollFx, 0); }); });

  // ---------- no dia a dia: a cena à direita acompanha o texto ----------
  var items = $$(".daily .item"), stage = $(".daily .viewer"), arts = stage ? $$(".story-art", stage) : [];
  function setActive(i) {
    items.forEach(function (it, k) { it.classList.toggle("on", k === i); });
    arts.forEach(function (a, k) {
      var on = k === i;
      if (on && !a.classList.contains("active")) { a.classList.remove("play"); void a.offsetWidth; a.classList.add("play"); }
      a.classList.toggle("active", on);
      if (!on) a.classList.remove("play");
    });
  }
  var mq = window.matchMedia("(max-width: 900px)");
  function placeArts() {
    // no celular, cada cena vai para baixo do seu texto; no computador, todas ficam na coluna fixa
    arts.forEach(function (a, k) {
      if (mq.matches) { $(".art-slot", items[k]).appendChild(a); a.classList.add("active", "play"); }
      else { stage.appendChild(a); }
    });
    if (!mq.matches) setActive(0);
  }
  if (stage) {
    placeArts();
    mq.addEventListener("change", placeArts);
    if ("IntersectionObserver" in window) {
      var stIo = new IntersectionObserver(function (es) {
        if (mq.matches) return;
        es.forEach(function (e) { if (e.isIntersecting) setActive(items.indexOf(e.target)); });
      }, { rootMargin: "-45% 0px -45% 0px" });
      items.forEach(function (it) { stIo.observe(it); });
    }
  }

  // ---------- carrossel de recursos ----------
  var rail = $("#rail");
  if (rail) {
    var prev = $(".features .prev"), next = $(".features .next");
    var step = function () { var c = $(".fcard", rail); return c ? c.getBoundingClientRect().width + 16 : 300; };
    prev.addEventListener("click", function () { rail.scrollBy({ left: -step(), behavior: reduce ? "auto" : "smooth" }); });
    next.addEventListener("click", function () { rail.scrollBy({ left: step(), behavior: reduce ? "auto" : "smooth" }); });
    var upd = function () { prev.disabled = rail.scrollLeft < 8; next.disabled = rail.scrollLeft + rail.clientWidth > rail.scrollWidth - 8; };
    rail.addEventListener("scroll", upd, { passive: true }); window.addEventListener("resize", upd); upd();
  }

  // ---------- rodapé: as letras de FileShare flutuam perto do ponteiro ----------
  var word = $("#word");
  if (word && !reduce) {
    var letters = $$("span", word);
    word.addEventListener("pointermove", function (e) {
      letters.forEach(function (l) {
        var r = l.getBoundingClientRect(), d = Math.abs(e.clientX - (r.left + r.width / 2));
        var lift = Math.max(0, 1 - d / 260) * 0.16;
        var base = l.classList.contains("up") ? 0.22 : 0;
        l.style.transform = "translateY(" + (-(base + lift)).toFixed(3) + "em)";
      });
    });
    word.addEventListener("pointerleave", function () { letters.forEach(function (l) { l.style.transform = ""; }); });
  }
})();
