# Helpers for explore.qmd (loaded from setup chunk)

source("R/data_helpers.R")

region_colors <- c(
  "Africa" = "#c0521b",
  "Asia-Pacific" = "#0d4f4f",
  "Central and South America" = "#d9a36a"
)

bucket_yn <- function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x == "Yes" ~ "Yes",
    x == "No" ~ "No",
    TRUE ~ "Other / unknown"
  )
}

collapse_first_line <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- "Not reported"
  tab <- table(x)
  keep <- names(tab)[tab >= 2]
  ifelse(x %in% keep, x, "Other / unknown")
}

explore_chart_payload <- function(char) {
  countries <- char |>
    dplyr::transmute(
      key = .data$Country,
      country = .data$Country,
      region = .data$Region,
      who_region = .data$`WHO Region`,
      first_line = .data$first_line,
      first_line_raw = .data$`Pv 1st line treatment`,
      cases_2023 = suppressWarnings(as.numeric(.data$`2023 Case Numbers`)),
      g6pd_guidelines = bucket_yn(.data$`Guidelines G6PD testing  (Y/N)`),
      g6pd_implementation = bucket_yn(.data$`Implementation: G6PD testing  (Y/N)`)
    ) |>
    dplyr::mutate(cases_2023 = dplyr::coalesce(.data$cases_2023, 0))

  list(
    countries = countries,
    meta = list(
      group = "explore",
      regionColors = as.list(region_colors),
      statusLevels = c("Yes", "No", "Other / unknown"),
      regionLevels = c("Africa", "Asia-Pacific", "Central and South America"),
      firstLineLevels = countries |>
        dplyr::count(.data$first_line, sort = TRUE) |>
        dplyr::pull(.data$first_line),
      g6pdMeasures = c(
        "In national guidelines",
        "Implemented in practice"
      ),
      measureColors = as.list(c(
        "In national guidelines" = "#0d4f4f",
        "Implemented in practice" = "#c0521b"
      )),
      statusColors = as.list(c(
        "Yes" = "#0d4f4f",
        "No" = "#c0521b",
        "Other / unknown" = "#8a9494"
      ))
    )
  )
}
