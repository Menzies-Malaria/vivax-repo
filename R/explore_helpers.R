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

normalise_first_line <- function(x) {
  x <- stringr::str_squish(as.character(x))
  x[!nzchar(x) | stringr::str_to_upper(x) %in% c("NA", "N/A")] <- "Not reported"
  x
}

explore_chart_payload <- function(char, case = NULL) {
  case_columns <- names(char)[stringr::str_detect(names(char), "^20[0-9]{2} Case Numbers$")]
  case_years <- sort(as.integer(stringr::str_extract(case_columns, "^20[0-9]{2}")))

  policy_update <- stats::setNames(rep(NA_integer_, nrow(char)), char$Country)
  if (!is.null(case)) {
    case_main <- case |>
      dplyr::filter(.data$Country %in% char$Country) |>
      dplyr::distinct(.data$Country, .keep_all = TRUE)
    parsed_year <- suppressWarnings(as.integer(
      stringr::str_extract(case_main$`Last Policy Update`, "(19|20)\\d{2}")
    ))
    policy_update[case_main$Country] <- parsed_year
  }

  countries <- char |>
    dplyr::transmute(
      key = .data$Country,
      country = .data$Country,
      region = .data$Region,
      who_region = .data$`WHO Region`,
      first_line = normalise_first_line(.data$`Pv 1st line treatment`),
      first_line_raw = .data$`Pv 1st line treatment`,
      proportion_2023 = suppressWarnings(as.numeric(.data$`Proportion of P. vivax cases (2023) (%)`)),
      g6pd_guidelines = bucket_yn(.data$`Guidelines G6PD testing  (Y/N)`),
      g6pd_implementation = bucket_yn(.data$`Implementation: G6PD testing  (Y/N)`),
      policy_update_year = unname(policy_update[.data$Country])
    )

  for (year in case_years) {
    source_column <- paste(year, "Case Numbers")
    values <- stringr::str_squish(char[[source_column]])
    values[stringr::str_to_upper(values) %in% c("", "NA", "N/A")] <- NA_character_
    countries[[paste0("cases_", year)]] <- suppressWarnings(as.numeric(values))
  }

  list(
    countries = countries,
    meta = list(
      group = "explore",
      caseYears = case_years,
      latestCaseYear = if (length(case_years)) max(case_years) else NULL,
      comparisonYears = utils::tail(case_years, 2),
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
