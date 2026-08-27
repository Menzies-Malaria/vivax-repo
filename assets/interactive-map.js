/* global d3, topojson */
(function () {
  "use strict";

  const WORLD_URL = "https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json";
  const NO_DATA = "Not reported";
  const MUTED = "#d9d5cc";
  const OUTSIDE = "#ebe7df";
  const PALETTE = [
    "#0d4f4f", "#c0521b", "#d9a36a", "#497f8c", "#8b5e83",
    "#6e8244", "#b66b55", "#49657b", "#9a7b3f", "#765b45",
  ];

  const metricLabels = {
    g6pd_guidelines: "G6PD testing in guidelines",
    g6pd_implementation: "G6PD testing implemented",
    first_line: "First-line treatment",
    program_phase: "Programme phase",
  };

  const aliases = {
    "bolivia plurinational state of": "bolivia",
    "brunei darussalam": "brunei",
    "cabo verde": "cape verde",
    "central african republic": "central african rep",
    "cote d ivoire": "ivory coast",
    "democratic republic of the congo": "dem rep congo",
    "dominican republic": "dominican rep",
    "equatorial guinea": "eq guinea",
    "eswatini": "swaziland",
    "iran islamic republic of": "iran",
    "lao pdr": "laos",
    "north korea dprk": "north korea",
    "republic of korea rok": "south korea",
    "russian federation": "russia",
    "sao tome and principe": "sao tome and principe",
    "solomon islands": "solomon is",
    "south sudan": "s sudan",
    "syrian arab republic": "syria",
    "united republic of tanzania zamzibar": "tanzania",
    "venezuela bolivarian republic of": "venezuela",
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

  function slugify(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  function display(value) {
    const clean = String(value == null ? "" : value).trim();
    return clean || NO_DATA;
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function categoryFor(row, metric) {
    return display(row[metric]);
  }

  function categoryColors(categories, metric) {
    const colors = new Map();
    if (metric === "g6pd_guidelines" || metric === "g6pd_implementation") {
      colors.set("Yes", "#0d4f4f");
      colors.set("No", "#c0521b");
      colors.set(NO_DATA, MUTED);
      return colors;
    }
    categories.forEach((category, index) => {
      colors.set(category, category === NO_DATA ? MUTED : PALETTE[index % PALETTE.length]);
    });
    return colors;
  }

  function detailItem(label, value) {
    return `<div><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(display(value))}</dd></div>`;
  }

  function init() {
    const dataElement = document.getElementById("policy-map-data");
    const svgElement = document.getElementById("policy-map");
    if (!dataElement || !svgElement || typeof d3 === "undefined" || typeof topojson === "undefined") return;

    const payload = JSON.parse(dataElement.textContent);
    const rows = payload.countries || [];
    const byCountry = new Map(rows.map((row) => [normaliseName(row.country), row]));
    const metricSelect = document.getElementById("policy-map-metric");
    const regionSelect = document.getElementById("policy-map-region");
    const resetButton = document.getElementById("policy-map-reset");
    const legend = document.getElementById("policy-map-legend");
    const details = document.getElementById("policy-map-details");
    const tooltip = document.getElementById("policy-map-tooltip");
    const status = document.getElementById("policy-map-status");

    (payload.regions || []).forEach((region) => {
      const option = document.createElement("option");
      option.value = region;
      option.textContent = region;
      regionSelect.appendChild(option);
    });

    const svg = d3.select(svgElement);
    const root = svg.append("g");
    let features = [];
    let paths;
    let selectedKey = null;

    const zoom = d3.zoom()
      .scaleExtent([1, 7])
      .on("zoom", (event) => root.attr("transform", event.transform));
    svg.call(zoom);

    function resize() {
      const width = Math.max(480, svgElement.clientWidth || 800);
      const height = Math.max(420, svgElement.clientHeight || 560);
      svg.attr("viewBox", `0 0 ${width} ${height}`);
      const projection = d3.geoNaturalEarth1().fitExtent([[12, 12], [width - 12, height - 12]], {
        type: "FeatureCollection",
        features,
      });
      const path = d3.geoPath(projection);
      if (paths) paths.attr("d", path);
    }

    function activeRows() {
      const region = regionSelect.value;
      return rows.filter((row) => !region || row.region === region);
    }

    function renderLegend(colors, counts) {
      const items = [...counts.entries()].sort((a, b) => b[1] - a[1]);
      legend.innerHTML = `<span class="policy-map-legend__title">${escapeHtml(metricLabels[metricSelect.value])}</span>` +
        items.map(([category, count]) => `
          <div class="policy-map-legend__item">
            <span class="policy-map-legend__swatch" style="background:${colors.get(category)}"></span>
            <span>${escapeHtml(category)}</span>
            <span class="policy-map-legend__count">${count}</span>
          </div>`).join("");
    }

    function updateMap() {
      if (!paths) return;
      const metric = metricSelect.value;
      const active = activeRows();
      const activeKeys = new Set(active.map((row) => normaliseName(row.country)));
      const categories = [...new Set(active.map((row) => categoryFor(row, metric)))];
      const colors = categoryColors(categories, metric);
      const counts = new Map();
      active.forEach((row) => {
        const category = categoryFor(row, metric);
        counts.set(category, (counts.get(category) || 0) + 1);
      });

      paths
        .classed("has-data", (feature) => byCountry.has(normaliseName(feature.properties.name)))
        .classed("is-selected", (feature) => normaliseName(feature.properties.name) === selectedKey)
        .attr("fill", (feature) => {
          const key = normaliseName(feature.properties.name);
          const row = byCountry.get(key);
          if (!row) return OUTSIDE;
          if (!activeKeys.has(key)) return MUTED;
          return colors.get(categoryFor(row, metric)) || MUTED;
        })
        .attr("opacity", (feature) => {
          const key = normaliseName(feature.properties.name);
          return byCountry.has(key) && !activeKeys.has(key) ? 0.35 : 1;
        });

      renderLegend(colors, counts);
    }

    function showTooltip(event, row) {
      tooltip.innerHTML = `<strong>${escapeHtml(row.country)}</strong>` +
        `${escapeHtml(metricLabels[metricSelect.value])}: ${escapeHtml(categoryFor(row, metricSelect.value))}`;
      tooltip.hidden = false;
      tooltip.style.left = `${event.clientX + 14}px`;
      tooltip.style.top = `${event.clientY + 14}px`;
    }

    function showDetails(row) {
      details.innerHTML = `
        <span class="policy-map-details__eyebrow">${escapeHtml(row.region || "Country details")}</span>
        <h2>${escapeHtml(row.country)}</h2>
        <p>${escapeHtml(display(row.who_region))}</p>
        <dl class="policy-map-detail-list">
          ${detailItem("Reporting P. vivax cases (last 5 years)", row.reporting)}
          ${detailItem("2023 case numbers", row.cases_2023)}
          ${detailItem("First-line treatment", row.first_line)}
          ${detailItem("Second-line treatment", row.second_line)}
          ${detailItem("G6PD testing in guidelines", row.g6pd_guidelines)}
          ${detailItem("G6PD testing implemented", row.g6pd_implementation)}
          ${detailItem("Type of G6PD testing", row.g6pd_type)}
          ${detailItem("Programme phase", row.program_phase)}
        </dl>
        <a class="policy-map-profile-link" href="profiles/${slugify(row.country)}.html">View country profile</a>`;
    }

    d3.json(WORLD_URL).then((world) => {
      features = topojson.feature(world, world.objects.countries).features;
      paths = root.selectAll("path")
        .data(features)
        .join("path")
        .attr("class", "policy-map-country")
        .attr("tabindex", (feature) => byCountry.has(normaliseName(feature.properties.name)) ? 0 : null)
        .attr("aria-label", (feature) => feature.properties.name)
        .on("mouseenter", (event, feature) => {
          const row = byCountry.get(normaliseName(feature.properties.name));
          if (row) showTooltip(event, row);
        })
        .on("mousemove", (event, feature) => {
          const row = byCountry.get(normaliseName(feature.properties.name));
          if (row) showTooltip(event, row);
        })
        .on("mouseleave", () => { tooltip.hidden = true; })
        .on("click", (event, feature) => {
          const key = normaliseName(feature.properties.name);
          const row = byCountry.get(key);
          if (!row) return;
          selectedKey = key;
          showDetails(row);
          updateMap();
          event.stopPropagation();
        })
        .on("keydown", (event, feature) => {
          if (event.key !== "Enter" && event.key !== " ") return;
          event.preventDefault();
          const key = normaliseName(feature.properties.name);
          const row = byCountry.get(key);
          if (!row) return;
          selectedKey = key;
          showDetails(row);
          updateMap();
        });

      resize();
      updateMap();
      status.hidden = true;
    }).catch((error) => {
      status.textContent = "The country boundary file could not be loaded. Check your internet connection and reload the page.";
      status.hidden = false;
      console.error(error);
    });

    metricSelect.addEventListener("change", updateMap);
    regionSelect.addEventListener("change", updateMap);
    resetButton.addEventListener("click", () => {
      regionSelect.value = "";
      selectedKey = null;
      tooltip.hidden = true;
      svg.transition().duration(300).call(zoom.transform, d3.zoomIdentity);
      details.innerHTML = `
        <div class="policy-map-details__empty">
          <span class="policy-map-details__eyebrow">Country details</span>
          <h2>Select a country</h2>
          <p>Choose a coloured country on the map to keep its policy summary here.</p>
        </div>`;
      updateMap();
    });

    let resizeTimer;
    window.addEventListener("resize", () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(resize, 150);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
