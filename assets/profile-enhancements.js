/* global d3, topojson */
(function () {
  "use strict";

  const WORLD_URL = "https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json";
  const TOPOJSON_URL = "https://cdn.jsdelivr.net/npm/topojson-client@3/dist/topojson-client.min.js";
  const DESKTOP = "(min-width: 992px)";
  const aliases = {
    "cabo verde": "cape verde",
    "central african republic": "central african rep",
    "cote d ivoire": "ivory coast",
    "democratic republic of the congo": "dem rep congo",
    "dominican republic": "dominican rep",
    "equatorial guinea": "eq guinea",
    "eswatini": "swaziland",
    "lao pdr": "laos",
    "north korea dprk": "north korea",
    "papua new guinea": "papua new guinea",
    "republic of korea rok": "south korea",
    "solomon islands": "solomon is",
    "south sudan": "s sudan",
    "united republic of tanzania zamzibar": "tanzania",
    "vietnam": "viet nam",
  };

  function normaliseName(value) {
    const clean = String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/&/g, "and")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
    return aliases[clean] || clean;
  }

  function ensureTopojson() {
    if (window.topojson) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = TOPOJSON_URL;
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  function positionContactCard() {
    const card = document.querySelector("[data-profile-contact]");
    if (!card) return;
    let marker = document.getElementById("country-contact-origin");
    if (!marker) {
      marker = document.createElement("span");
      marker.id = "country-contact-origin";
      marker.hidden = true;
      card.before(marker);
    }
    const margin = document.getElementById("quarto-margin-sidebar");
    const desktop = window.matchMedia(DESKTOP).matches;
    if (desktop && margin) {
      margin.append(card);
      card.classList.add("country-contact-card--margin");
    } else {
      marker.after(card);
      card.classList.remove("country-contact-card--margin");
    }
  }

  async function drawLocator(locator) {
    const svgElements = locator.querySelectorAll("svg");
    if (!svgElements.length || typeof d3 === "undefined") return;
    const country = normaliseName(locator.dataset.country);
    const regionCountries = new Set(
      String(locator.dataset.regionCountries || "")
        .split("|")
        .map(normaliseName)
        .filter(Boolean)
    );
    try {
      await ensureTopojson();
      const world = await d3.json(WORLD_URL);
      const features = topojson.feature(world, world.objects.countries).features;
      const width = 360;
      const height = 185;
      const regionalFeatures = features.filter((feature) =>
        regionCountries.has(normaliseName(feature.properties.name))
      );

      svgElements.forEach((svgElement) => {
        const view = svgElement.dataset.locatorView || "global";
        const fittedFeatures = view === "region" && regionalFeatures.length
          ? regionalFeatures
          : features;
        const projection = d3.geoNaturalEarth1().fitExtent(
          [[10, 10], [width - 10, height - 10]],
          { type: "FeatureCollection", features: fittedFeatures }
        );
        const path = d3.geoPath(projection);
        const svg = d3.select(svgElement)
          .attr("viewBox", `0 0 ${width} ${height}`)
          .attr("preserveAspectRatio", "xMidYMid meet");
        svg.selectAll("path")
          .data(features)
          .join("path")
          .attr("d", path)
          .attr("class", (feature) => {
            const featureName = normaliseName(feature.properties.name);
            if (featureName === country) return "is-country";
            if (view === "region" && regionCountries.has(featureName)) return "is-region";
            return "is-context";
          });
      });
    } catch (error) {
      locator.classList.add("is-unavailable");
      console.error("Unable to draw the country locator map.", error);
    }
  }

  function init() {
    const locators = document.querySelectorAll(".country-profile-locator[data-country]");
    locators.forEach(drawLocator);
    positionContactCard();
    window.addEventListener("resize", positionContactCard);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
