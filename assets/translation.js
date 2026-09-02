(function () {
  "use strict";

  const STORAGE_KEY = "vivax-language";
  const script = document.currentScript;
  const assetBase = new URL("translations/", script.src);
  let sourceStrings = {};
  const translations = {};
  let currentLanguage = "en";

  function preserveWhitespace(original, replacement) {
    const leading = original.match(/^\s*/)[0];
    const trailing = original.match(/\s*$/)[0];
    return `${leading}${replacement}${trailing}`;
  }

  function dictionary(language) {
    const values = language === "en" ? sourceStrings : translations[language];
    const map = new Map();
    if (!values) return map;
    Object.keys(sourceStrings).forEach((key) => {
      Object.values(translations).forEach((other) => {
        if (other[key] && values[key]) map.set(other[key], values[key]);
      });
      if (sourceStrings[key] && values[key]) map.set(sourceStrings[key], values[key]);
    });
    return map;
  }

  function translateRoot(root, language) {
    const map = dictionary(language);
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.parentElement) return NodeFilter.FILTER_REJECT;
        if (node.parentElement.closest("a, script, style, code, pre, table, figure, iframe, canvas, svg, .cell, .cell-output, .html-widget, .vivax-chart, .vivax-language-control")) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach((node) => {
      const trimmed = node.nodeValue.trim();
      if (map.has(trimmed)) node.nodeValue = preserveWhitespace(node.nodeValue, map.get(trimmed));
    });

    root.querySelectorAll("[title], [aria-label], [placeholder]").forEach((element) => {
      if (element.closest("a, table, figure, iframe, .cell, .cell-output, .html-widget, .vivax-chart")) return;
      ["title", "aria-label", "placeholder"].forEach((attribute) => {
        const value = element.getAttribute(attribute);
        if (value && map.has(value.trim())) element.setAttribute(attribute, map.get(value.trim()));
      });
    });
  }

  function applyLanguage(language) {
    currentLanguage = ["es", "fr", "pt"].includes(language) ? language : "en";
    document.documentElement.lang = currentLanguage;
    translateRoot(document.body, currentLanguage);
    localStorage.setItem(STORAGE_KEY, currentLanguage);
    const select = document.getElementById("vivax-language-select");
    if (select) select.value = currentLanguage;
  }

  function addSelector() {
    const navbar = document.querySelector("#quarto-header .navbar-nav.ms-auto");
    if (!navbar) return;
    const item = document.createElement("li");
    item.className = "nav-item vivax-language-control";
    item.innerHTML = [
      '<label class="visually-hidden" for="vivax-language-select">Language</label>',
      '<select id="vivax-language-select" class="form-select form-select-sm" aria-label="Language">',
      '<option value="en">English</option>',
      '<option value="es">Español</option>',
      '<option value="fr">Français</option>',
      '<option value="pt">Português</option>',
      "</select>",
    ].join("");
    navbar.prepend(item);
    item.querySelector("select").addEventListener("change", (event) => {
      applyLanguage(event.target.value);
    });
  }

  async function loadJson(name) {
    const response = await fetch(new URL(name, assetBase));
    if (!response.ok) throw new Error(`Could not load ${name}`);
    return response.json();
  }

  async function init() {
    try {
      const [source, spanish, french, portuguese] = await Promise.all([
        loadJson("en.json"),
        loadJson("es.json"),
        loadJson("fr.json"),
        loadJson("pt.json"),
      ]);
      sourceStrings = source.strings || {};
      translations.es = spanish.strings || {};
      translations.fr = french.strings || {};
      translations.pt = portuguese.strings || {};
      addSelector();
      const requested = new URLSearchParams(window.location.search).get("lang");
      applyLanguage(requested || localStorage.getItem(STORAGE_KEY) || "en");
    } catch (error) {
      console.error("Vivax translation prototype could not start:", error);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
