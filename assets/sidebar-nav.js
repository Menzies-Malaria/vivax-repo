(function () {
  "use strict";

  const STORAGE_KEY = "vivax-sidebar-collapsed";
  const DESKTOP_QUERY = "(min-width: 992px)";
  const COMPACT_DESKTOP_QUERY = "(min-width: 992px) and (max-width: 1279.98px)";
  const icons = [
    ["index.html", "bi-geo-alt"],
    ["overview.html", "bi-house"],
    ["explore.html", "bi-bar-chart"],
    ["countries.html", "bi-people"],
    ["timeline.html", "bi-clock-history"],
    ["methods.html", "bi-journal-text"],
    ["contribute.html", "bi-pencil-square"],
    ["data.html", "bi-download"],
    ["github.com", "bi-github"],
  ];

  function iconFor(href) {
    const match = icons.find(([fragment]) => href.includes(fragment));
    return match ? match[1] : "bi-circle";
  }

  function init() {
    const sidebar = document.getElementById("quarto-sidebar");
    const header = sidebar && sidebar.querySelector(".sidebar-header");
    if (!sidebar || !header) return;

    const search = sidebar.querySelector(".sidebar-search");
    const main = document.getElementById("quarto-document-content");
    if (search && main) {
      const topSearch = document.createElement("div");
      topSearch.className = "vivax-top-search";
      topSearch.setAttribute("role", "search");
      topSearch.setAttribute("aria-label", "Search the repository");
      topSearch.append(search);
      main.prepend(topSearch);
    }

    sidebar.querySelectorAll(".sidebar-link").forEach((link) => {
      const label = link.querySelector(".menu-text");
      const text = label ? label.textContent.trim() : "Navigation";
      const icon = document.createElement("i");
      icon.className = `vivax-nav-icon bi ${iconFor(link.getAttribute("href") || "")}`;
      icon.setAttribute("aria-hidden", "true");
      link.prepend(icon);
      link.title = text;
    });

    const button = document.createElement("button");
    button.type = "button";
    button.className = "vivax-sidebar-toggle";
    button.innerHTML = '<i class="bi bi-list" aria-hidden="true"></i>';
    button.setAttribute("aria-controls", "quarto-sidebar");
    header.prepend(button);

    function isCollapsed() {
      return document.body.classList.contains("vivax-sidebar-collapsed");
    }

    let hasSavedPreference = localStorage.getItem(STORAGE_KEY) !== null;

    function syncButton() {
      const desktop = window.matchMedia(DESKTOP_QUERY).matches;
      const collapsed = desktop && isCollapsed();
      button.setAttribute("aria-expanded", String(!collapsed));
      button.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
      button.title = collapsed ? "Expand sidebar" : "Collapse sidebar";
    }

    function apply(collapsed, persist) {
      const desktop = window.matchMedia(DESKTOP_QUERY).matches;
      document.body.classList.toggle("vivax-sidebar-collapsed", desktop && collapsed);
      syncButton();
      if (persist) {
        localStorage.setItem(STORAGE_KEY, collapsed ? "true" : "false");
        hasSavedPreference = true;
      }
      window.dispatchEvent(new Event("resize"));
    }

    const saved = localStorage.getItem(STORAGE_KEY);
    const initialCollapsed = hasSavedPreference
      ? saved === "true"
      : window.matchMedia(COMPACT_DESKTOP_QUERY).matches;
    apply(initialCollapsed, false);

    button.addEventListener("click", () => apply(!isCollapsed(), true));
    window.addEventListener("resize", () => {
      const desktop = window.matchMedia(DESKTOP_QUERY).matches;
      if (!desktop) {
        document.body.classList.remove("vivax-sidebar-collapsed");
      } else if (!hasSavedPreference) {
        document.body.classList.toggle(
          "vivax-sidebar-collapsed",
          window.matchMedia(COMPACT_DESKTOP_QUERY).matches
        );
      }
      syncButton();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
