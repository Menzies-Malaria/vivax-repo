# Shared data-loading helpers for Quarto pages

require_sheet_url <- function(name) {
  url <- Sys.getenv(name, unset = "")
  if (!nzchar(url)) {
    stop(
      name, " is not set. Export publish-to-web CSV URLs from the Google Sheet (see README).",
      call. = FALSE
    )
  }
  if (!grepl("^https?://", url)) {
    stop(name, " must be an https URL to the Google Sheet CSV export.", call. = FALSE)
  }
  url
}

characteristic_data_source <- function(
  local_path = "data/characteristic_data.csv"
) {
  if (nzchar(Sys.getenv("CHAR_DATA_URL", unset = ""))) {
    return(require_sheet_url("CHAR_DATA_URL"))
  }

  if (file.exists(local_path)) {
    return(local_path)
  }

  stop(
    "CHAR_DATA_URL is not set and local characteristic data was not found at ",
    local_path, ".",
    call. = FALSE
  )
}

load_sheet <- function(path) {
  df <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE
  )
  df[is.na(df)] <- ""
  names(df) <- trimws(names(df))
  df
}

load_characteristic_data <- function(path = characteristic_data_source()) {
  load_sheet(path)
}

load_case_data <- function(path = require_sheet_url("CASE_DATA_URL")) {
  load_sheet(path)
}

headline_stats <- function(char, case) {
  case_main <- case |>
    dplyr::filter(!stringr::str_detect(.data$Country, " - "))

  list(
    n_countries = dplyr::n_distinct(char$Country),
    n_reporting = sum(stringr::str_starts(
      trimws(char$`Reporting vivax cases (<5 years)`),
      "Yes"
    )),
    n_implementing = sum(trimws(char$`Implementation: G6PD testing  (Y/N)`) == "Yes"),
    n_with_policy = sum(nzchar(trimws(case_main$`Last Policy Update`)))
  )
}

column_dictionary_notes <- function() {
  c(
    "Country" = "Country or territory name.",
    "Region" = "Project-defined region: Africa, Asia-Pacific, or Central and South America.",
    "WHO Region" = "WHO region: African, Americas, Eastern Mediterranean, South-East Asia, Western Pacific.",
    "Reporting vivax cases (<5 years)" = "Whether the country has reported any P. vivax cases in the last five years.",
    "2023 Case Numbers" = "Reported P. vivax cases in 2023.",
    "2022 Case Numbers" = "Reported P. vivax cases in 2022.",
    "2021 Case Numbers" = "Reported P. vivax cases in 2021.",
    "2020 Case Numbers" = "Reported P. vivax cases in 2020.",
    "2019 Case Numbers" = "Reported P. vivax cases in 2019.",
    "2018 Case Numbers" = "Reported P. vivax cases in 2018.",
    "Proportion of P. vivax cases (2023) (%)" = "P. vivax as a percentage of all reported malaria cases in 2023.",
    "Type of malaria diagnostic (e.g., RDT, lab result, serology)" = "Diagnostics used routinely for malaria case detection.",
    "Pv 1st line treatment" = "Recommended first-line treatment for uncomplicated P. vivax malaria.",
    "Rationale for ACT use" = "Where an ACT is used first-line, the stated rationale.",
    "Pv 2nd line treatment" = "Recommended second-line treatment.",
    "G6PD deficiency prevalence" = "Estimated prevalence of G6PD deficiency, where reported.",
    "Projects/Research determining G6PDd prevalence" = "Active or recent projects measuring G6PD prevalence.",
    "Guidelines G6PD testing  (Y/N)" = "Whether G6PD testing is included in current national guidelines.",
    "Implementation: G6PD testing  (Y/N)" = "Whether G6PD testing is implemented in practice.",
    "Type of G6PD testing" = "Test format (qualitative, quantitative, SNP/ELISA, etc.).",
    "Community malaria care" = "Existence of community-level case management.",
    "Community vivax care" = "Existence of community-level vivax-specific care (including radical cure).",
    "Follow-up of radical cure" = "Whether follow-up after radical cure is part of policy/practice.",
    "Community follow-up of radical cure" = "Whether follow-up extends to the community level.",
    "Program Phase" = "Stage of the national malaria programme: burden reduction, pre-elimination, elimination, eliminated.",
    "Sub-national program phases (Y/N)" = "Whether the country has different programme phases in different subnational areas.",
    "Details of subnational program phases" = "Free text describing subnational stratification.",
    "Cross-border transmission" = "Whether cross-border transmission is a feature.",
    "Mobile Migrant Populations" = "Whether mobile or migrant populations are a significant feature.",
    "Type of high risk populations" = "Description of the populations at greatest risk.",
    "Economic status" = "World Bank economic classification at time of recording.",
    "Contact" = "Programme focal point or other point of contact."
  )
}

column_dictionary_table <- function(char) {
  notes <- column_dictionary_notes()
  tibble::tibble(
    Column = sprintf("`%s`", names(char)),
    Description = vapply(names(char), function(col) {
      clean <- trimws(col)
      if (clean %in% names(notes)) notes[[clean]] else "\u2014"
    }, character(1), USE.NAMES = FALSE)
  )
}
