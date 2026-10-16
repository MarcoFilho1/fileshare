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
  // Ícones minúsculos de arquivos (documento, imagem, planilha, PDF, pasta, música, zip, código,
  // vídeo, link, prancheta) espalhados num anel em volta do centro, girando devagar; perto do ponteiro eles se
  // afastam. Cada ícone é desenhado uma vez num sprite e só é copiado a cada quadro.
  var ICONS = {
    doc: function (c) { c.beginPath(); c.moveTo(3, 1); c.lineTo(7.5, 1); c.lineTo(10, 3.5); c.lineTo(10, 11); c.lineTo(3, 11); c.closePath(); c.moveTo(7.5, 1); c.lineTo(7.5, 3.5); c.lineTo(10, 3.5); c.moveTo(4.8, 6.3); c.lineTo(8.2, 6.3); c.moveTo(4.8, 8.4); c.lineTo(8.2, 8.4); c.stroke(); },
    image: function (c) { c.beginPath(); c.rect(1.3, 2.3, 9.4, 7.4); c.moveTo(1.6, 9.2); c.lineTo(4.6, 6); c.lineTo(6.6, 8); c.lineTo(8, 6.7); c.lineTo(10.4, 9.2); c.stroke(); c.beginPath(); c.arc(7.9, 4.6, 0.95, 0, 7); c.fill(); },
    csv: function (c) { c.beginPath(); c.rect(1.5, 2, 9, 8); c.moveTo(1.5, 4.7); c.lineTo(10.5, 4.7); c.moveTo(1.5, 7.3); c.lineTo(10.5, 7.3); c.moveTo(4.8, 2); c.lineTo(4.8, 10); c.stroke(); },
    pdf: function (c) { c.beginPath(); c.moveTo(3, 1); c.lineTo(7.5, 1); c.lineTo(10, 3.5); c.lineTo(10, 11); c.lineTo(3, 11); c.closePath(); c.moveTo(7.5, 1); c.lineTo(7.5, 3.5); c.lineTo(10, 3.5); c.stroke(); c.fillRect(1.6, 6, 6.6, 3.2); },
    folder: function (c) { c.beginPath(); c.moveTo(1.3, 3); c.lineTo(4.6, 3); c.lineTo(5.8, 4.3); c.lineTo(10.7, 4.3); c.lineTo(10.7, 9.8); c.lineTo(1.3, 9.8); c.closePath(); c.stroke(); },
    music: function (c) { c.beginPath(); c.moveTo(5, 9); c.lineTo(5, 2.6); c.lineTo(10, 1.6); c.lineTo(10, 8); c.stroke(); c.beginPath(); c.arc(3.7, 9, 1.4, 0, 7); c.arc(8.7, 8, 1.4, 0, 7); c.fill(); },
    zip: function (c) { c.beginPath(); c.rect(2.5, 1, 7, 10); c.moveTo(6, 1); c.lineTo(6, 2); c.moveTo(6, 3); c.lineTo(6, 4); c.moveTo(6, 5); c.lineTo(6, 6); c.stroke(); c.strokeRect(5, 7, 2, 2); },
    code: function (c) { c.beginPath(); c.moveTo(4.4, 3.4); c.lineTo(1.6, 6); c.lineTo(4.4, 8.6); c.moveTo(7.6, 3.4); c.lineTo(10.4, 6); c.lineTo(7.6, 8.6); c.stroke(); },
    video: function (c) { c.beginPath(); c.rect(1.3, 2.3, 9.4, 7.4); c.stroke(); c.beginPath(); c.moveTo(4.9, 4.4); c.lineTo(8, 6); c.lineTo(4.9, 7.6); c.closePath(); c.fill(); },
    link: function (c) {
      // dois elos (pílulas) encaixados, na diagonal
      function pill(x) { c.moveTo(x + 1.7, -1.7); c.lineTo(x + 3.9, -1.7); c.arc(x + 3.9, 0, 1.7, -Math.PI / 2, Math.PI / 2); c.lineTo(x + 1.7, 1.7); c.arc(x + 1.7, 0, 1.7, Math.PI / 2, Math.PI * 1.5); }
      c.save(); c.translate(6, 6); c.rotate(-Math.PI / 4); c.beginPath(); pill(-5.2); pill(-0.4); c.stroke(); c.restore();
    },
    clip: function (c) { c.beginPath(); c.rect(2.3, 2.2, 7.4, 9); c.moveTo(4.6, 6); c.lineTo(7.4, 6); c.moveTo(4.6, 8); c.lineTo(7.4, 8); c.stroke(); c.fillRect(4.2, 1, 3.6, 2.2); }
  };
  var KINDS = Object.keys(ICONS), sprites = {};
  function sprite(kind, color, dpr) {
    var key = kind + color + dpr;
    if (sprites[key]) return sprites[key];
    var px = Math.ceil(16 * dpr), cv = document.createElement("canvas");
    cv.width = cv.height = px;
    var c = cv.getContext("2d");
    c.scale(px / 12, px / 12);
    c.strokeStyle = c.fillStyle = color; c.lineWidth = 1.15; c.lineJoin = c.lineCap = "round";
    ICONS[kind](c);
    return (sprites[key] = cv);
  }
  function field(canvas, opts) {
    if (!canvas) return;
    var ctx = canvas.getContext("2d"), dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0, pts = [], mouse = { x: -9999, y: -9999 }, visible = true, t0 = performance.now();
    function resize() {
      var r = canvas.getBoundingClientRect(); W = r.width; H = r.height;
      canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
      var n = Math.round(Math.min(opts.max, (W * H) / opts.density));
      pts = [];
      for (var i = 0; i < n; i++) {
        var a = Math.random() * Math.PI * 2;
        var rr = opts.inner + Math.pow(Math.random(), 0.7) * (1 - opts.inner);
        var kind = KINDS[(Math.random() * KINDS.length) | 0], col = opts.colors[(Math.random() * opts.colors.length) | 0];
        pts.push({ a: a, r: rr, s: (0.4 + Math.random()) * opts.speed * (Math.random() < 0.5 ? 1 : 0.6),
          img: sprite(kind, col, dpr), z: opts.size * (0.75 + Math.random() * 0.5) * (0.7 + 0.45 * rr),
          rot: (Math.random() - 0.5) * 0.7, spin: (Math.random() - 0.5) * 0.4, ox: 0, oy: 0 });
      }
    }
    function frame(now) {
      if (!visible) return;
      var t = (now - t0) / 1000;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      var cx = W / 2, cy = H * opts.cy, rx = W * opts.rx, ry = H * opts.ry;
      for (var i = 0; i < pts.length; i++) {
        var p = pts[i], a = p.a + (reduce ? 0 : t * p.s);
        var x = cx + Math.cos(a) * rx * p.r, y = cy + Math.sin(a) * ry * p.r;
        var dx = x - mouse.x, dy = y - mouse.y, d2 = dx * dx + dy * dy, R = 130;
        if (d2 < R * R) { var f = (1 - Math.sqrt(d2) / R) * 26; var d = Math.sqrt(d2) || 1; p.ox += (dx / d * f - p.ox) * 0.15; p.oy += (dy / d * f - p.oy) * 0.15; }
        else { p.ox *= 0.92; p.oy *= 0.92; }
        x += p.ox; y += p.oy;
        var rot = p.rot + (reduce ? 0 : t * p.spin), cs = Math.cos(rot) * dpr, sn = Math.sin(rot) * dpr;
        var k = 1;
        // Em tela estreita o texto ocupa a largura toda: no meio, os ícones quase somem.
        if (W < 700) k = Math.max(0.1, Math.min(1, (Math.abs(x - cx) / (W / 2) - 0.6) / 0.3));
        ctx.globalAlpha = opts.alpha * (0.35 + 0.65 * p.r) * k;
        ctx.setTransform(cs, sn, -sn, cs, x * dpr, y * dpr);
        ctx.drawImage(p.img, -p.z / 2, -p.z / 2, p.z, p.z);
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
  field($("#field"), { max: 240, density: 4200, size: 15, inner: 0.42, rx: 0.62, ry: 0.62, cy: 0.5, speed: 0.025, alpha: dark ? 0.9 : 0.85,
    colors: dark ? ["#5b8fff", "#8fb4ff", "#2f6fea", "#3a3f4a"] : ["#1c5fe0", "#4ea6ff", "#2166f5", "#9db7ec", "#c4cbd6"] });
  field($("#grow-field"), { max: 200, density: 4800, size: 15, inner: 0.25, rx: 0.7, ry: 0.75, cy: 0.5, speed: 0.02, alpha: 0.75, colors: ["#5b8fff", "#8fb4ff", "#2f6fea", "#ffffff"] });
  field($("#night-field"), { max: 170, density: 4600, size: 15, inner: 0.3, rx: 0.65, ry: 0.9, cy: 0.15, speed: 0.02, alpha: 0.8, colors: ["#5b8fff", "#8fb4ff", "#2f6fea", "#ffffff"] });

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
        l.style.transform = "translateY(" + (-lift).toFixed(3) + "em)";
      });
    });
    word.addEventListener("pointerleave", function () { letters.forEach(function (l) { l.style.transform = ""; }); });
  }
})();
