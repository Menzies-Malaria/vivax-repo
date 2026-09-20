/* global d3, crosstalk */
(function (global) {
  "use strict";

  const BG = "#f7f3ec";
  const GRID = "#e2d8bf";
  const TEXT = "#1a1f1f";
  const HEAT_LOW = "#f7f3ec";
  const HEAT_HIGH = "#0d4f4f";

  const REGION_COLORS = {
    Africa: "#c0521b",
    "Asia-Pacific": "#0d4f4f",
    "Central and South America": "#d9a36a",
    Unknown: "#8a9494",
  };

  const G6PD_MEASURE_COLORS = {
    "In national guidelines": "#0d4f4f",
    "Implemented in practice": "#c0521b",
  };

  const G6PD_STATUS_COLORS = {
    Yes: "#0d4f4f",
    No: "#c0521b",
    "Other / unknown": "#8a9494",
  };

  function colorMap(keys, colors, fallback) {
    const map = { ...fallback };
    if (Array.isArray(colors)) {
      keys.forEach((key, i) => {
        if (colors[i]) map[key] = colors[i];
      });
    } else if (colors && typeof colors === "object") {
      Object.assign(map, colors);
    }
    return map;
  }

  function formatNumber(n) {
    return d3.format(",")(n);
  }

  function ensureTooltip() {
    let tip = document.querySelector(".vivax-tooltip");
    if (!tip) {
      tip = document.createElement("div");
      tip.className = "vivax-tooltip";
      tip.setAttribute("role", "tooltip");
      document.body.appendChild(tip);
    }
    return tip;
  }

  function bindTooltip(selection, htmlFn) {
    const tip = ensureTooltip();
    selection
      .on("mouseenter", function (event, d) {
        tip.innerHTML = htmlFn(d);
        tip.classList.add("is-visible");
      })
      .on("mousemove", function (event) {
        tip.style.left = `${event.clientX + 12}px`;
        tip.style.top = `${event.clientY + 12}px`;
      })
      .on("mouseleave", function () {
        tip.classList.remove("is-visible");
      });
  }

  function clearPlot(container) {
    d3.select(container).selectAll("*").remove();
    container.style.minHeight = null;
  }

  /** @returns {number} pixel height consumed by legend */
  function drawLegendTop(svg, items, plotWidth, xOffset) {
    if (!items.length) return 0;
    const cols = Math.min(items.length, 4);
    const colW = plotWidth / cols;
    const rows = Math.ceil(items.length / cols);
    const g = svg
      .append("g")
      .attr("class", "legend legend--top")
      .attr("transform", `translate(${xOffset}, 10)`);

    items.forEach((item, i) => {
      const col = i % cols;
      const row = Math.floor(i / cols);
      const lg = g
        .append("g")
        .attr("transform", `translate(${col * colW}, ${row * 22})`);
      lg.append("rect")
        .attr("width", 12)
        .attr("height", 12)
        .attr("fill", item.color)
        .attr("stroke", "#d8cfb8")
        .attr("stroke-width", 0.5);
      lg.append("text")
        .attr("x", 16)
        .attr("y", 10)
        .attr("fill", TEXT)
        .text(item.label);
    });

    return 10 + rows * 22 + 14;
  }

  function drawColorLegendTop(svg, plotWidth, xOffset, maxN, label) {
    const g = svg
      .append("g")
      .attr("class", "legend legend--top legend--gradient")
      .attr("transform", `translate(${xOffset}, 10)`);

    const barW = Math.min(200, plotWidth * 0.45);
    const gradId = `vivax-heat-${Math.random().toString(36).slice(2, 9)}`;

    const defs = svg.append("defs");
    const grad = defs
      .append("linearGradient")
      .attr("id", gradId)
      .attr("x1", "0%")
      .attr("x2", "100%");
    grad.append("stop").attr("offset", "0%").attr("stop-color", HEAT_LOW);
    grad.append("stop").attr("offset", "100%").attr("stop-color", HEAT_HIGH);

    g.append("text")
      .attr("x", 0)
      .attr("y", 9)
      .attr("fill", TEXT)
      .attr("font-size", 11)
      .text("0");

    g.append("rect")
      .attr("x", 18)
      .attr("y", 0)
      .attr("width", barW)
      .attr("height", 12)
      .style("fill", `url(#${gradId})`)
      .attr("stroke", "#d8cfb8");

    g.append("text")
      .attr("x", 24 + barW)
      .attr("y", 9)
      .attr("fill", TEXT)
      .attr("font-size", 11)
      .text(String(maxN));

    g.append("text")
      .attr("x", barW + 52)
      .attr("y", 9)
      .attr("fill", "#4a5252")
      .attr("font-size", 11)
      .text(label || "Countries");

    return 36;
  }

  function drawCasesBar(container, rows, meta) {
    clearPlot(container);
    const regionColors = meta?.regionColors || REGION_COLORS;

    const data = rows
      .filter((d) => d.cases_2023 > 0)
      .sort((a, b) => d3.descending(a.cases_2023, b.cases_2023))
      .slice(0, 15)
      .reverse();

    if (!data.length) {
      d3.select(container)
        .append("p")
        .attr("class", "vivax-chart__empty")
        .text("No countries match the current filters with reported 2023 case data.");
      container.style.minHeight = "120px";
      return;
    }

    const width = Math.min(920, container.clientWidth || 920);
    const barH = 28;
    const innerH = data.length * barH;
    const plotW = width - 150 - 28;

    const regions = [...new Set(data.map((d) => d.region))].filter(Boolean);
    const legendItems = regions.map((r) => ({
      label: r,
      color: regionColors[r] || REGION_COLORS.Unknown,
    }));
    const legendH = Math.max(36, 10 + Math.ceil(legendItems.length / 4) * 22 + 14);

    const margin = { top: legendH + 8, right: 28, bottom: 40, left: 150 };
    const height = margin.top + innerH + margin.bottom;
    const innerW = width - margin.left - margin.right;

    container.style.minHeight = `${height + 16}px`;

    const svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr(
        "aria-label",
        "Horizontal bar chart of countries by reported P. vivax cases in 2023"
      );

    drawLegendTop(svg, legendItems, plotW, margin.left);

    const g = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const x = d3
      .scaleLinear()
      .domain([0, d3.max(data, (d) => d.cases_2023)])
      .nice()
      .range([0, innerW]);

    const y = d3
      .scaleBand()
      .domain(data.map((d) => d.country))
      .range([0, innerH])
      .padding(0.2);

    const color = d3
      .scaleOrdinal()
      .domain(Object.keys(regionColors))
      .range(Object.values(regionColors))
      .unknown(REGION_COLORS.Unknown);

    g.append("g")
      .attr("class", "grid")
      .call(d3.axisBottom(x).tickSize(innerH).tickFormat(""))
      .selectAll("line")
      .attr("stroke", GRID);

    g.append("g")
      .attr("class", "axis")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(x).ticks(6).tickFormat(formatNumber))
      .append("text")
      .attr("x", innerW / 2)
      .attr("y", 32)
      .attr("fill", TEXT)
      .attr("text-anchor", "middle")
      .text("Reported cases (2023)");

    g.append("g")
      .attr("class", "axis")
      .call(d3.axisLeft(y).tickSize(0))
      .select(".domain")
      .remove();

    const bars = g
      .selectAll(".bar")
      .data(data)
      .join("rect")
      .attr("class", "bar")
      .attr("x", 0)
      .attr("y", (d) => y(d.country))
      .attr("height", y.bandwidth())
      .attr("width", (d) => x(d.cases_2023))
      .attr("fill", (d) => color(d.region));

    bindTooltip(bars, (d) =>
      [
        `<strong>${d.country}</strong>`,
        `Region: ${d.region}`,
        `WHO region: ${d.who_region || ""}`,
        `First-line: ${d.first_line_raw || d.first_line || ""}`,
        `Cases (2023): ${formatNumber(d.cases_2023)}`,
      ].join("<br>")
    );
  }

  function drawG6pdGrouped(container, rows, meta) {
    clearPlot(container);
    const statuses = meta.statusLevels;
    const measures = meta.g6pdMeasures;
    const measureColors = colorMap(
      measures,
      meta.measureColors,
      G6PD_MEASURE_COLORS
    );
    const statusColors = colorMap(
      statuses,
      meta.statusColors,
      G6PD_STATUS_COLORS
    );

    const counts = [];
    measures.forEach((measure) => {
      statuses.forEach((status) => {
        const field =
          measure === "In national guidelines"
            ? "g6pd_guidelines"
            : "g6pd_implementation";
        counts.push({
          measure,
          status,
          n: rows.filter((r) => r[field] === status).length,
        });
      });
    });

    const width = Math.min(720, container.clientWidth || 720);
    const plotW = width - 48 - 16;
    const legendItems = measures.map((m) => ({
      label: m,
      color: measureColors[m],
    }));
    const legendH = 36;

    const margin = { top: legendH + 12, right: 16, bottom: 48, left: 48 };
    const height = 400;
    const innerW = width - margin.left - margin.right;
    const innerH = height - margin.top - margin.bottom;

    container.style.minHeight = `${height + 16}px`;

    const svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr(
        "aria-label",
        "Grouped bar chart comparing G6PD testing in guidelines versus implementation"
      );

    drawLegendTop(svg, legendItems, plotW, margin.left);

    const g = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const x0 = d3.scaleBand().domain(statuses).range([0, innerW]).padding(0.28);
    const x1 = d3
      .scaleBand()
      .domain(measures)
      .range([0, x0.bandwidth()])
      .padding(0.12);

    const y = d3
      .scaleLinear()
      .domain([0, d3.max(counts, (d) => d.n) || 1])
      .nice()
      .range([innerH, 0]);

    g.append("g")
      .attr("class", "grid")
      .call(d3.axisLeft(y).tickSize(-innerW).tickFormat(""))
      .selectAll("line")
      .attr("stroke", GRID);

    g.append("g")
      .attr("class", "axis")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(x0))
      .selectAll("text")
      .attr("fill", (d) => statusColors[d] || TEXT)
      .attr("font-weight", 600);

    g.append("g")
      .attr("class", "axis")
      .call(d3.axisLeft(y).ticks(6).tickFormat(d3.format("d")))
      .append("text")
      .attr("transform", "rotate(-90)")
      .attr("x", -innerH / 2)
      .attr("y", -40)
      .attr("fill", TEXT)
      .attr("text-anchor", "middle")
      .text("Countries");

    const groups = g
      .selectAll(".measure-group")
      .data(statuses)
      .join("g")
      .attr("transform", (d) => `translate(${x0(d)},0)`);

    const bars = groups
      .selectAll("rect")
      .data((status) =>
        measures.map((measure) => ({
          status,
          measure,
          n: counts.find((c) => c.status === status && c.measure === measure).n,
        }))
      )
      .join("rect")
      .attr("x", (d) => x1(d.measure))
      .attr("y", (d) => y(d.n))
      .attr("width", x1.bandwidth())
      .attr("height", (d) => innerH - y(d.n))
      .attr("fill", (d) => measureColors[d.measure])
      .attr("stroke", "#1a1f1f")
      .attr("stroke-width", 0.5);

    bindTooltip(bars, (d) =>
      [
        `<strong>${d.measure}</strong>`,
        `Status: ${d.status}`,
        `Countries: ${d.n}`,
      ].join("<br>")
    );
  }

  function drawTreatmentHeatmap(container, rows, meta) {
    clearPlot(container);
    const regions = meta.regionLevels;
    const treatments = meta.firstLineLevels;
    const cells = [];

    regions.forEach((region) => {
      treatments.forEach((treatment) => {
        cells.push({
          region,
          treatment,
          n: rows.filter(
            (r) => r.region === region && r.first_line === treatment
          ).length,
        });
      });
    });

    const maxN = d3.max(cells, (d) => d.n) || 1;
    const cellW = 58;
    const cellH = 48;
    const innerW = treatments.length * cellW;
    const innerH = regions.length * cellH;
    const width = 120 + innerW + 40;
    const plotW = innerW;

    const margin = { top: 52, right: 24, bottom: 110, left: 120 };
    const height = margin.top + innerH + margin.bottom;

    container.style.minHeight = `${height + 16}px`;

    const svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr(
        "aria-label",
        "Heatmap of first-line P. vivax treatment by geographic region"
      );

    drawColorLegendTop(svg, plotW, margin.left, maxN, "Countries");

    const g = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const x = d3.scaleBand().domain(treatments).range([0, innerW]).padding(0.06);
    const y = d3.scaleBand().domain(regions).range([0, innerH]).padding(0.06);

    const color = d3
      .scaleSequential()
      .domain([0, maxN])
      .interpolator(d3.interpolate(HEAT_LOW, HEAT_HIGH));

    const rects = g
      .selectAll("rect")
      .data(cells)
      .join("rect")
      .attr("x", (d) => x(d.treatment))
      .attr("y", (d) => y(d.region))
      .attr("width", x.bandwidth())
      .attr("height", y.bandwidth())
      .attr("fill", (d) => (d.n === 0 ? HEAT_LOW : color(d.n)))
      .attr("stroke", "#d8cfb8")
      .attr("stroke-width", 0.5);

    bindTooltip(rects, (d) =>
      [
        `<strong>${d.treatment}</strong>`,
        `Region: ${d.region}`,
        `Countries: ${d.n}`,
      ].join("<br>")
    );

    g.selectAll(".cell-label")
      .data(cells.filter((d) => d.n > 0))
      .join("text")
      .attr("class", (d) =>
        d.n > maxN * 0.55 ? "cell-label cell-label--light" : "cell-label"
      )
      .attr("x", (d) => x(d.treatment) + x.bandwidth() / 2)
      .attr("y", (d) => y(d.region) + y.bandwidth() / 2)
      .attr("text-anchor", "middle")
      .attr("dominant-baseline", "middle")
      .text((d) => d.n);

    g.append("g")
      .attr("class", "axis")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(x))
      .selectAll("text")
      .attr("transform", "rotate(-35)")
      .style("text-anchor", "end")
      .attr("dx", "-0.4em")
      .attr("dy", "0.35em");

    g.append("g").attr("class", "axis").call(d3.axisLeft(y));
  }

  /** Stagger milestone labels above the chart, aligned to vertical grid lines. */
  function layoutMilestoneLabels(milestones, xScale) {
    if (!milestones?.length) return [];
    const tierOffset = [-10, -28];
    const items = milestones
      .map((m) => ({ ...m, cx: xScale(m.year), halfW: m.label.length * 3.4 }))
      .sort((a, b) => a.cx - b.cx);
    const placed = [];

    for (const m of items) {
      let tier = 0;
      for (const p of placed) {
        if (
          p.tier === tier &&
          Math.abs(m.cx - p.cx) < m.halfW + p.halfW + 8
        ) {
          tier = 1;
          break;
        }
      }
      m.tier = tier;
      m.y = tierOffset[tier];
      placed.push(m);
    }
    return items;
  }

  function drawTimeline(container, points, meta) {
    clearPlot(container);
    if (!points.length) {
      d3.select(container)
        .append("p")
        .attr("class", "vivax-chart__empty")
        .text("No policy update years on file for the current selection.");
      container.style.minHeight = "120px";
      return;
    }

    const regionColors = meta?.regionColors || REGION_COLORS;
    const sorted = [...points].sort((a, b) => d3.descending(a.year, b.year));
    const countries = sorted.map((d) => d.country);

    const width = Math.min(960, container.clientWidth || 960);
    const barH = 22;
    const innerH = countries.length * barH;
    const marginLeft = Math.min(
      240,
      Math.max(130, (d3.max(countries, (c) => c.length) || 12) * 6.8)
    );
    const marginRight = 24;

    const regions = [...new Set(sorted.map((d) => d.region))].filter(Boolean);
    const legendItems = regions.map((r) => ({
      label: r,
      color: regionColors[r] || REGION_COLORS.Unknown,
    }));
    const legendH = Math.max(36, 10 + Math.ceil(legendItems.length / 4) * 22 + 14);
    const plotW = width - marginLeft - marginRight;

    const margin = {
      top: legendH + 36,
      right: marginRight,
      bottom: 44,
      left: marginLeft,
    };
    const height = margin.top + innerH + margin.bottom;
    const innerW = width - margin.left - margin.right;

    container.style.minHeight = `${height + 16}px`;

    const svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr("aria-label", "Timeline of last policy update by country");

    drawLegendTop(svg, legendItems, plotW, margin.left);

    const g = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const x = d3
      .scaleLinear()
      .domain(d3.extent(sorted, (d) => d.year))
      .nice()
      .range([0, innerW]);

    const y = d3
      .scaleBand()
      .domain(countries)
      .range([0, innerH])
      .padding(0.18);

    const color = d3
      .scaleOrdinal()
      .domain(Object.keys(regionColors))
      .range(Object.values(regionColors))
      .unknown(REGION_COLORS.Unknown);

    const milestoneLayout = layoutMilestoneLabels(meta.milestones || [], x);

    milestoneLayout.forEach((m) => {
      g.append("line")
        .attr("class", "timeline-milestone")
        .attr("x1", m.cx)
        .attr("x2", m.cx)
        .attr("y1", 0)
        .attr("y2", innerH)
        .attr("stroke", "#1a1f1f")
        .attr("stroke-dasharray", "3,3")
        .attr("stroke-opacity", 0.35);
    });

    g.append("g")
      .attr("class", "grid")
      .call(
        d3
          .axisBottom(x)
          .tickValues(d3.range(x.domain()[0], x.domain()[1] + 1, 2))
          .tickSize(innerH)
          .tickFormat("")
      )
      .selectAll("line")
      .attr("stroke", GRID);

    g.append("g")
      .attr("class", "axis")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(x).tickFormat(d3.format("d")))
      .append("text")
      .attr("x", innerW / 2)
      .attr("y", 36)
      .attr("fill", TEXT)
      .attr("text-anchor", "middle")
      .text("Year of last policy update");

    const milestoneLabels = g
      .append("g")
      .attr("class", "timeline-milestone-labels")
      .selectAll("text")
      .data(milestoneLayout)
      .join("text")
      .attr("class", "timeline-milestone-label")
      .attr("x", (d) => d.cx)
      .attr("y", (d) => d.y)
      .attr("text-anchor", "middle")
      .attr("dominant-baseline", "auto")
      .attr("fill", "#4a5252")
      .attr("font-size", 10)
      .attr("paint-order", "stroke fill")
      .attr("stroke", BG)
      .attr("stroke-width", 3)
      .text((d) => d.label);

    g.append("g")
      .attr("class", "axis axis--countries")
      .call(d3.axisLeft(y).tickSize(0))
      .selectAll("text")
      .attr("text-anchor", "end")
      .attr("x", -10);
    g.select(".axis--countries .domain").remove();

    g.selectAll("line.timeline-stem")
      .data(sorted)
      .join("line")
      .attr("class", "timeline-stem")
      .attr("x1", 0)
      .attr("x2", (d) => x(d.year))
      .attr("y1", (d) => y(d.country) + y.bandwidth() / 2)
      .attr("y2", (d) => y(d.country) + y.bandwidth() / 2)
      .attr("stroke", (d) => color(d.region))
      .attr("stroke-opacity", 0.5)
      .attr("stroke-width", 1.5);

    const dots = g
      .selectAll("circle")
      .data(sorted)
      .join("circle")
      .attr("cx", (d) => x(d.year))
      .attr("cy", (d) => y(d.country) + y.bandwidth() / 2)
      .attr("r", 8)
      .attr("fill", (d) => color(d.region))
      .attr("stroke", "#1a1f1f")
      .attr("stroke-width", 1.25);

    bindTooltip(dots, (d) =>
      [
        `<strong>${d.country}</strong>`,
        `Year: ${d.year}`,
        `Region: ${d.region}`,
        d.drug ? `Schizontocidal: ${d.drug}` : null,
        d.next ? `Next update: ${d.next}` : null,
      ]
        .filter(Boolean)
        .join("<br>")
    );
  }

  function drawCasesLine(container, payload) {
    clearPlot(container);
    const series = (payload.series || []).filter((d) => d.value != null && d.value > 0);
    if (series.length < 2) {
      d3.select(container)
        .append("p")
        .attr("class", "vivax-chart__empty")
        .text("Not enough yearly case data to plot a trend.");
      container.style.minHeight = "100px";
      return;
    }

    const width = Math.min(720, container.clientWidth || 720);
    const margin = { top: 28, right: 24, bottom: 48, left: 56 };
    const height = 280;
    const innerW = width - margin.left - margin.right;
    const innerH = height - margin.top - margin.bottom;

    container.style.minHeight = `${height + 16}px`;

    const svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr("aria-label", `Reported P. vivax cases in ${payload.country}`);

    const g = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const x = d3
      .scalePoint()
      .domain(series.map((d) => d.year))
      .range([0, innerW])
      .padding(0.5);

    const y = d3
      .scaleLinear()
      .domain([0, d3.max(series, (d) => d.value)])
      .nice()
      .range([innerH, 0]);

    g.append("g")
      .attr("class", "grid")
      .call(d3.axisLeft(y).tickSize(-innerW).tickFormat(""))
      .selectAll("line")
      .attr("stroke", GRID);

    g.append("g")
      .attr("class", "axis")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(x));

    g.append("g")
      .attr("class", "axis")
      .call(d3.axisLeft(y).ticks(5).tickFormat(formatNumber))
      .append("text")
      .attr("transform", "rotate(-90)")
      .attr("x", -innerH / 2)
      .attr("y", -42)
      .attr("fill", TEXT)
      .attr("text-anchor", "middle")
      .text("Reported cases");

    const line = d3
      .line()
      .x((d) => x(d.year))
      .y((d) => y(d.value));

    g.append("path")
      .datum(series)
      .attr("fill", "none")
      .attr("stroke", "#0d4f4f")
      .attr("stroke-width", 2.5)
      .attr("d", line);

    const pts = g
      .selectAll("circle")
      .data(series)
      .join("circle")
      .attr("cx", (d) => x(d.year))
      .attr("cy", (d) => y(d.value))
      .attr("r", 5)
      .attr("fill", "#0d4f4f")
      .attr("stroke", "#f7f3ec")
      .attr("stroke-width", 2);

    bindTooltip(
      pts,
      (d) =>
        `<strong>${payload.country}</strong><br>${d.year}: ${formatNumber(d.value)} cases`
    );
  }

  function filterRows(rows, keys) {
    if (keys == null) return rows;
    if (keys.length === 0) return [];
    const set = new Set(keys);
    return rows.filter((r) => set.has(r.key));
  }

  function initExplorePage() {
    const dataEl = document.getElementById("explore-data");
    if (!dataEl || typeof crosstalk === "undefined") return;

    const payload = JSON.parse(dataEl.textContent);
    const fh = new crosstalk.FilterHandle();
    fh.setGroup(payload.meta.group);

    function update() {
      const rows = filterRows(payload.countries, fh.filteredKeys);
      const casesEl = document.getElementById("chart-cases");
      const g6pdEl = document.getElementById("chart-g6pd");
      const heatEl = document.getElementById("chart-heatmap");
      if (casesEl) drawCasesBar(casesEl, rows, payload.meta);
      if (g6pdEl) drawG6pdGrouped(g6pdEl, rows, payload.meta);
      if (heatEl) drawTreatmentHeatmap(heatEl, rows, payload.meta);
    }

    fh.on("change", function (e) {
      if (e.sender === fh) return;
      update();
    });

    update();

    let resizeTimer;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(update, 150);
    });
  }

  function initTimelinePage() {
    const dataEl = document.getElementById("timeline-data");
    const chartEl = document.getElementById("chart-timeline");
    if (!dataEl || !chartEl) return;

    const payload = JSON.parse(dataEl.textContent);
    drawTimeline(chartEl, payload.points, payload.meta);

    let resizeTimer;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        drawTimeline(chartEl, payload.points, payload.meta);
      }, 150);
    });
  }

  function initProfileCharts() {
    document.querySelectorAll("[data-vivax-chart]").forEach(function (el) {
      const wrap = el.closest(".vivax-chart");
      if (!wrap) return;
      const dataEl = wrap.querySelector(".vivax-chart-payload");
      if (!dataEl) return;
      const payload = JSON.parse(dataEl.textContent);
      const kind = el.getAttribute("data-vivax-chart");
      if (kind === "cases-line") drawCasesLine(el, payload);
    });
  }

  function init() {
    if (typeof d3 === "undefined") return;
    initExplorePage();
    initTimelinePage();
    initProfileCharts();
  }

  global.VivaxCharts = {
    drawCasesBar,
    drawG6pdGrouped,
    drawTreatmentHeatmap,
    drawTimeline,
    drawCasesLine,
    init,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(typeof window !== "undefined" ? window : this);
