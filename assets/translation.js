(function () {
  "use strict";

  const STORAGE_KEY = "vivax-language";
  const script = document.currentScript;
  const assetBase = new URL("translations/", script.src);
  let sourceStrings = {};
  const translations = {};
  const loads = {};
  let currentLanguage = "en";
  let observer;
  let languageRequest = 0;
  let translateProfileTables = false;

  function preserveWhitespace(original, replacement) {
    const leading = original.match(/^\s*/)[0];
    const trailing = original.match(/\s*$/)[0];
    return `${leading}${replacement}${trailing}`;
  }

  function unwrapSpeciesNames(root) {
    const scope = root.nodeType === Node.ELEMENT_NODE ? root : root.parentElement;
    if (!scope) return;
    const names = [];
    if (scope.matches && scope.matches("em[data-vivax-species]")) names.push(scope);
    names.push(...scope.querySelectorAll("em[data-vivax-species]"));
    names.forEach((name) => {
      const parent = name.parentNode;
      if (!parent) return;
      name.replaceWith(document.createTextNode(name.textContent || ""));
      parent.normalize();
    });
  }

  function italiciseSpeciesNames(root) {
    const scope = root.nodeType === Node.ELEMENT_NODE ? root : root.parentElement;
    if (!scope) return;
    const pattern = /\b(?:Plasmodium\s+vivax|P\.?\s+vivax)\b/gi;
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || parent.closest("script, style, code, pre, textarea, em, i")) {
          return NodeFilter.FILTER_REJECT;
        }
        pattern.lastIndex = 0;
        return pattern.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach((node) => {
      const text = node.nodeValue;
      const fragment = document.createDocumentFragment();
      let cursor = 0;
      pattern.lastIndex = 0;
      for (const match of text.matchAll(pattern)) {
        fragment.append(document.createTextNode(text.slice(cursor, match.index)));
        const emphasis = document.createElement("em");
        emphasis.dataset.vivaxSpecies = "true";
        emphasis.textContent = match[0];
        fragment.append(emphasis);
        cursor = match.index + match[0].length;
      }
      fragment.append(document.createTextNode(text.slice(cursor)));
      node.replaceWith(fragment);
    });
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

  function isExcluded(element) {
    if (element.closest("script, style, code, pre, figure, iframe, canvas, svg, .cell, .cell-output, .html-widget, .vivax-chart, .vivax-language-control")) {
      return true;
    }
    if (element.closest("table") && !translateProfileTables) return true;
    const link = element.closest("a");
    const translatableLink = link && (
      link.matches(".sidebar-link, .policy-map-profile-link, .profile-back-link, .country-card, .country-contact-request__link") ||
      link.closest("#TOC")
    );
    return Boolean(link && !translatableLink);
  }

  function translateRoot(root, language) {
    const map = dictionary(language);
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.parentElement) return NodeFilter.FILTER_REJECT;
        if (isExcluded(node.parentElement)) {
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
      if (isExcluded(element)) return;
      ["title", "aria-label", "placeholder"].forEach((attribute) => {
        const value = element.getAttribute(attribute);
        const replacement = value && map.get(value.trim());
        if (replacement && replacement !== value.trim()) element.setAttribute(attribute, replacement);
      });
    });
  }

  async function ensureLanguage(language) {
    if (language === "en") return;
    if (!loads.en) loads.en = loadJson("en.json");
    if (!loads[language]) loads[language] = loadJson(`${language}.json`);
    const [source, target] = await Promise.all([loads.en, loads[language]]);
    sourceStrings = source.strings || {};
    translations[language] = target.strings || {};
  }

  async function applyLanguage(language) {
    const requestedLanguage = ["es", "fr", "pt"].includes(language) ? language : "en";
    const request = ++languageRequest;
    try {
      await ensureLanguage(requestedLanguage);
    } catch (error) {
      console.error(`Could not load ${requestedLanguage} translations:`, error);
      return;
    }
    if (request !== languageRequest) return;
    currentLanguage = requestedLanguage;
    document.documentElement.lang = currentLanguage;
    unwrapSpeciesNames(document.body);
    translateRoot(document.body, currentLanguage);
    italiciseSpeciesNames(document.body);
    localStorage.setItem(STORAGE_KEY, currentLanguage);
    const select = document.getElementById("vivax-language-select");
    if (select) select.value = currentLanguage;
    window.dispatchEvent(new CustomEvent("vivax-language-change", {
      detail: { language: currentLanguage },
    }));
  }

  function addSelector() {
    if (document.getElementById("vivax-language-select")) return;

    let host = document.querySelector(".vivax-top-search") || document.querySelector("#quarto-sidebar .sidebar-header");
    if (!host && document.querySelector(".country-profile-locator[data-country]")) {
      const titleBlock = document.querySelector("#title-block-header");
      if (titleBlock) {
        host = document.createElement("div");
        host.className = "vivax-profile-language-bar";
        titleBlock.prepend(host);
      }
    }
    if (!host) return;
    const item = document.createElement("div");
    item.className = "vivax-language-control";
    item.innerHTML = [
      '<label class="visually-hidden" for="vivax-language-select">Language</label>',
      '<select id="vivax-language-select" class="form-select form-select-sm" aria-label="Language">',
      '<option value="en">English</option>',
      '<option value="es">Español</option>',
      '<option value="fr">Français</option>',
      '<option value="pt">Português</option>',
      "</select>",
    ].join("");
    host.append(item);
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
      translateProfileTables = Boolean(
        document.querySelector(".country-profile-locator[data-country]")
      );
      addSelector();
      const requested = new URLSearchParams(window.location.search).get("lang");
      await applyLanguage(requested || localStorage.getItem(STORAGE_KEY) || "en");
      observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.type === "attributes" && currentLanguage !== "en") {
            translateRoot(mutation.target, currentLanguage);
          }
          mutation.addedNodes.forEach((node) => {
            const root = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
            if (!root) return;
            if (currentLanguage !== "en") translateRoot(root, currentLanguage);
            italiciseSpeciesNames(root);
          });
        });
      });
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["title", "aria-label", "placeholder"],
      });
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
