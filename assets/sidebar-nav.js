(function () {
  "use strict";

  const STORAGE_KEY = "vivax-sidebar-collapsed";
  const DESKTOP_QUERY = "(min-width: 1280px)";
  const COMPACT_DESKTOP_QUERY = "(min-width: 1280px) and (max-width: 1599.98px)";
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
    // Chrome's mobile/tablet user agent remains present in its normal mode and
    // is replaced when the user explicitly requests the desktop site. This
    // gives large tablets the compact interface without blocking that choice.
    const mobileSiteRequested = /Android|iPad|iPhone|iPod/i.test(navigator.userAgent);
    document.body.classList.toggle("vivax-mobile-device", mobileSiteRequested);

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

    const sidebarLogo = header.querySelector(".sidebar-logo");
    const mobileNav = document.querySelector("#quarto-header .quarto-secondary-nav .container-fluid");
    const breadcrumbs = mobileNav && mobileNav.querySelector(".quarto-page-breadcrumbs");
    if (sidebarLogo && mobileNav && breadcrumbs && !mobileNav.querySelector(".vivax-mobile-logo")) {
      const mobileLogo = document.createElement("a");
      mobileLogo.className = "vivax-mobile-logo";
      mobileLogo.href = header.querySelector(".sidebar-logo-link")?.getAttribute("href") || "./index.html";
      mobileLogo.setAttribute("aria-label", "Malaria Policy Repository home");

      const mobileLogoImage = document.createElement("img");
      mobileLogoImage.className = "vivax-mobile-logo-image";
      mobileLogoImage.src = sidebarLogo.getAttribute("src");
      mobileLogoImage.alt = "";
      mobileLogo.append(mobileLogoImage);
      mobileNav.insertBefore(mobileLogo, breadcrumbs);
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

    function isDesktopLayout() {
      return !mobileSiteRequested && window.matchMedia(DESKTOP_QUERY).matches;
    }

    function isCompactDesktop() {
      return isDesktopLayout() && window.matchMedia(COMPACT_DESKTOP_QUERY).matches;
    }

    let hasSavedPreference = localStorage.getItem(STORAGE_KEY) !== null;
    let compactOverride = false;

    function syncButton() {
      const desktop = isDesktopLayout();
      const collapsed = desktop && isCollapsed();
      button.setAttribute("aria-expanded", String(!collapsed));
      button.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
      button.title = collapsed ? "Expand sidebar" : "Collapse sidebar";
    }

    function apply(collapsed, persist) {
      const desktop = isDesktopLayout();
      document.body.classList.toggle("vivax-sidebar-collapsed", desktop && collapsed);
      syncButton();
      if (persist) {
        localStorage.setItem(STORAGE_KEY, collapsed ? "true" : "false");
        hasSavedPreference = true;
      }
      window.dispatchEvent(new Event("resize"));
    }

    const saved = localStorage.getItem(STORAGE_KEY);
    const initialCollapsed = isCompactDesktop()
      ? true
      : hasSavedPreference && saved === "true";
    apply(initialCollapsed, false);

    button.addEventListener("click", () => {
      const compact = isCompactDesktop();
      compactOverride = compact;
      apply(!isCollapsed(), !compact);
    });
    window.addEventListener("resize", () => {
      const desktop = isDesktopLayout();
      const compact = isCompactDesktop();
      if (!desktop) {
        document.body.classList.remove("vivax-sidebar-collapsed");
        compactOverride = false;
      } else if (compact && !compactOverride) {
        document.body.classList.add("vivax-sidebar-collapsed");
      } else if (!compact) {
        document.body.classList.toggle(
          "vivax-sidebar-collapsed",
          hasSavedPreference && localStorage.getItem(STORAGE_KEY) === "true"
        );
        compactOverride = false;
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
