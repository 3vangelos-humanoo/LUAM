// Bridge between LUAM's native side and the preview page.
//   LUAM.setContent(html)  – replace the body, keeping the scroll position
//   LUAM.scrollToLine(n)   – scroll so source line n is at the top
//   LUAM.setStyle(css)     – replace the theme stylesheet
//   LUAM.renderRich()      – typeset .luam-math (KaTeX) and pre.mermaid;
//                            resolves when done (used before printing)
// and posts {topLine} to the "luam" message handler as the user scrolls, and
// {toggleTask: line} when a task checkbox is clicked.
(function () {
  "use strict";

  let suppressUntil = 0;
  let lastPosted = 0;

  // [data-line] elements with their document offsets, in line order.
  function anchors() {
    const list = [];
    for (const el of document.querySelectorAll("[data-line]")) {
      const line = parseInt(el.getAttribute("data-line"), 10);
      if (!isNaN(line)) list.push({ line, top: el.getBoundingClientRect().top + window.scrollY });
    }
    list.sort((a, b) => a.line - b.line || a.top - b.top);
    return list;
  }

  function scrollToLine(line) {
    const list = anchors();
    if (list.length === 0) return;
    let before = list[0], after = null;
    for (const a of list) {
      if (a.line <= line) before = a;
      else { after = a; break; }
    }
    let y = before.top;
    if (after && after.line > before.line && line > before.line) {
      y += (after.top - before.top) * (line - before.line) / (after.line - before.line);
    }
    suppressUntil = Date.now() + 150;
    window.scrollTo(0, Math.max(0, y - 8));
  }

  function topLine() {
    const list = anchors();
    const y = window.scrollY + 8;
    let before = null, after = null;
    for (const a of list) {
      if (a.top <= y) before = a;
      else { after = a; break; }
    }
    if (!before) return 1;
    if (!after || after.top === before.top) return before.line;
    const f = (y - before.top) / (after.top - before.top);
    return before.line + (after.line - before.line) * f;
  }

  function setContent(html) {
    const y = window.scrollY;
    document.getElementById("luam-content").innerHTML = html;
    suppressUntil = Date.now() + 150;
    window.scrollTo(0, y);
    renderRich();
  }

  // ---- Math and diagrams -------------------------------------------------
  // The libraries load on first use. In the app they come from the bundle
  // through the luam-vendor: scheme; an exported page sets LUAM_VENDOR to CDN
  // URLs (with integrity hashes) instead.

  const vendor = window.LUAM_VENDOR || {
    katexJS: { src: "luam-vendor:///katex.min.js" },
    katexCSS: { src: "luam-vendor:///katex.min.css" },
    mermaid: { src: "luam-vendor:///mermaid.min.js" },
  };
  const loading = {};

  function load(key) {
    if (loading[key]) return loading[key];
    const item = vendor[key];
    loading[key] = new Promise((resolve, reject) => {
      const css = key.endsWith("CSS");
      const el = document.createElement(css ? "link" : "script");
      if (css) { el.rel = "stylesheet"; el.href = item.src; } else { el.src = item.src; }
      if (item.integrity) { el.integrity = item.integrity; el.crossOrigin = "anonymous"; }
      el.onload = resolve;
      el.onerror = () => { delete loading[key]; reject(new Error("could not load " + item.src)); };
      document.head.appendChild(el);
    });
    return loading[key];
  }

  async function renderMath(root) {
    const nodes = root.querySelectorAll(".luam-math:not([data-rendered])");
    if (nodes.length === 0) return;
    try {
      await Promise.all([load("katexJS"), load("katexCSS")]);
    } catch (e) {
      return; // Leave the TeX source showing.
    }
    for (const el of nodes) {
      if (!el.isConnected) continue;
      const tex = el.textContent;
      try {
        window.katex.render(tex, el, {
          displayMode: el.classList.contains("luam-math-display"),
          throwOnError: false,
        });
        el.setAttribute("data-rendered", "");
      } catch (e) {
        el.textContent = tex;
        el.title = String(e.message || e);
      }
    }
  }

  // Rendered SVG by theme + source, so a diagram isn't redrawn on every
  // keystroke elsewhere in the document.
  const diagrams = new Map();
  let diagramTheme = null;
  let diagramCounter = 0;

  function isDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  async function renderDiagrams(root) {
    const nodes = [...root.querySelectorAll("pre.mermaid:not([data-rendered])")];
    if (nodes.length === 0) return;
    try {
      await load("mermaid");
    } catch (e) {
      return;
    }
    const theme = isDark() ? "dark" : "default";
    if (theme !== diagramTheme) {
      window.mermaid.initialize({ startOnLoad: false, theme, securityLevel: "strict" });
      diagramTheme = theme;
    }
    for (const el of nodes) {
      // The source outlives the SVG that replaces it, for re-theming.
      if (!el.hasAttribute("data-source")) el.setAttribute("data-source", el.textContent);
      const source = el.getAttribute("data-source");
      const key = theme + "\n" + source;
      let svg = diagrams.get(key);
      if (!svg) {
        const id = "luam-diagram-" + (++diagramCounter);
        try {
          svg = (await window.mermaid.render(id, source)).svg;
        } catch (e) {
          // Mermaid can leave its scratch element behind on a syntax error.
          for (const junk of [document.getElementById(id), document.getElementById("d" + id)]) junk?.remove();
          el.classList.add("mermaid-error");
          el.title = String(e.message || e);
          continue;
        }
        if (diagrams.size > 64) diagrams.delete(diagrams.keys().next().value);
        diagrams.set(key, svg);
      }
      if (!el.isConnected) continue;
      el.innerHTML = svg;
      el.setAttribute("data-rendered", "");
    }
  }

  function renderRich() {
    const root = document.getElementById("luam-content") || document.body;
    return Promise.all([renderMath(root), renderDiagrams(root)]);
  }

  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      for (const el of document.querySelectorAll("pre.mermaid[data-rendered]")) el.removeAttribute("data-rendered");
      renderRich();
    });
  }

  function post(message) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.luam;
    if (handler) handler.postMessage(message);
  }

  // The checkbox flips at once; the edited source re-renders it moments later.
  document.addEventListener("click", (event) => {
    const box = event.target;
    if (!(box instanceof HTMLInputElement) || !box.hasAttribute("data-task-line")) return;
    post({ toggleTask: parseInt(box.getAttribute("data-task-line"), 10) });
  });

  function setStyle(css) {
    let style = document.getElementById("luam-style");
    if (!style) {
      style = document.createElement("style");
      style.id = "luam-style";
      document.head.appendChild(style);
    }
    style.textContent = css;
  }

  window.addEventListener("scroll", () => {
    if (Date.now() < suppressUntil) return;
    const line = topLine();
    if (Math.abs(line - lastPosted) < 0.05) return;
    lastPosted = line;
    post({ topLine: line });
  }, { passive: true });

  window.LUAM = { setContent, scrollToLine, setStyle, renderRich };

  // Exported pages have their content from the start.
  if (document.querySelector("#luam-content .luam-math, #luam-content pre.mermaid")) renderRich();
})();
