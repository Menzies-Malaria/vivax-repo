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

case_data_source <- function(
  local_path = "data/case_management.csv"
) {
  if (nzchar(Sys.getenv("CASE_DATA_URL", unset = ""))) {
    return(require_sheet_url("CASE_DATA_URL"))
  }

  if (file.exists(local_path)) {
    return(local_path)
  }

  stop(
    "CASE_DATA_URL is not set and local case-management data was not found at ",
    local_path, ".",
    call. = FALSE
  )
}

normalise_input_frame <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  df[] <- lapply(df, function(column) {
    column <- as.character(column)
    column[is.na(column)] <- ""
    column
  })
  names(df) <- trimws(names(df))
  df
}

load_sheet <- function(path) {
  df <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE
  )
  normalise_input_frame(df)
}

format_repository_number <- function(x) {
  out <- format(round(x, 6), trim = TRUE, scientific = FALSE)
  out <- stringr::str_replace(out, "(\\.[0-9]*?)0+$", "\\1")
  stringr::str_remove(out, "\\.$")
}

required_columns <- function(df, columns, dataset) {
  missing <- setdiff(columns, names(df))
  if (length(missing)) {
    stop(
      dataset, " is missing required columns: ", paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(df)
}

normalise_characteristic_data <- function(df) {
  df <- normalise_input_frame(df)

  revised_prop <- "Proportion of P. vivax cases (2023)"
  canonical_prop <- "Proportion of P. vivax cases (2023) (%)"

  if (revised_prop %in% names(df) && canonical_prop %in% names(df)) {
    stop("Characteristic Data contains both versions of the 2023 proportion column.", call. = FALSE)
  }
  if (revised_prop %in% names(df)) {
    names(df)[names(df) == revised_prop] <- canonical_prop
  }

  required_columns(
    df,
    c(
      "Country", "Region", "WHO Region", "Reporting vivax cases (<5 years)",
      "2023 Case Numbers", "Pv 1st line treatment", "Pv 2nd line treatment",
      "Guidelines G6PD testing  (Y/N)",
      "Implementation: G6PD testing  (Y/N)", "Type of G6PD testing",
      "Program Phase", canonical_prop
    ),
    "Characteristic Data"
  )

  df <- df |>
    dplyr::mutate(Country = stringr::str_squish(.data$Country)) |>
    dplyr::filter(nzchar(.data$Country))

  if (anyDuplicated(df$Country)) {
    duplicates <- unique(df$Country[duplicated(df$Country)])
    stop(
      "Characteristic Data contains duplicate country keys: ",
      paste(duplicates, collapse = ", "),
      call. = FALSE
    )
  }

  raw_prop <- stringr::str_squish(df[[canonical_prop]])
  has_percent_sign <- stringr::str_detect(raw_prop, "%")
  numeric_prop <- suppressWarnings(readr::parse_number(raw_prop, na = c("", "NA", "N/A")))
  invalid <- nzchar(raw_prop) & !stringr::str_to_upper(raw_prop) %in% c("NA", "N/A") & is.na(numeric_prop)
  if (any(invalid)) stop("The 2023 proportion column contains non-numeric values.", call. = FALSE)

  fraction <- !is.na(numeric_prop) & !has_percent_sign & numeric_prop >= 0 & numeric_prop <= 1
  numeric_prop[fraction] <- numeric_prop[fraction] * 100
  if (any(numeric_prop < 0 | numeric_prop > 100, na.rm = TRUE)) {
    stop("The normalized 2023 proportion column contains values outside 0-100.", call. = FALSE)
  }
  df[[canonical_prop]] <- ifelse(
    is.na(numeric_prop), "", format_repository_number(numeric_prop)
  )

  case_columns <- names(df)[stringr::str_detect(names(df), "^20[0-9]{2} Case Numbers$")]
  for (column in case_columns) {
    values <- stringr::str_squish(df[[column]])
    values[stringr::str_to_upper(values) %in% c("NA", "N/A")] <- ""
    invalid <- nzchar(values) & is.na(suppressWarnings(as.numeric(values)))
    if (any(invalid)) stop("Non-numeric case count found in `", column, "`.", call. = FALSE)
    df[[column]] <- values
  }

  # Email is excluded unless publication has been explicitly enabled in the build.
  if ("Email" %in% names(df) && Sys.getenv("INCLUDE_PUBLIC_EMAIL", unset = "0") != "1") {
    df$Email <- NULL
  }

  df
}

normalise_country_key <- function(x) {
  x |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[^a-z0-9]+", " ") |>
    stringr::str_squish()
}

match_repository_country <- function(value, countries) {
  value_key <- normalise_country_key(value)
  country_keys <- normalise_country_key(countries)
  exact <- which(country_keys == value_key)
  if (length(exact) == 1) return(countries[[exact]])

  aliases <- c(
    "png" = "Papua New Guinea",
    "papua new guinea png" = "Papua New Guinea",
    "rok" = "Republic of Korea (ROK)"
  )
  if (value_key %in% names(aliases) && unname(aliases[[value_key]]) %in% countries) {
    return(unname(aliases[[value_key]]))
  }

  distances <- as.numeric(utils::adist(value_key, country_keys, ignore.case = TRUE))
  best <- which(distances == min(distances))
  relative <- distances[best] / pmax(nchar(value_key), nchar(country_keys[best]), 1)
  if (length(best) == 1 && relative <= 0.12) return(countries[[best]])
  NA_character_
}

standardise_case_country <- function(value, countries) {
  value <- stringr::str_squish(value)
  direct <- match_repository_country(value, countries)
  if (!is.na(direct)) return(direct)

  aliases <- tibble::tibble(
    alias = c(countries, "PNG", "Papua New Guinea (PNG)", "ROK"),
    country = c(countries, "Papua New Guinea", "Papua New Guinea", "Republic of Korea (ROK)")
  ) |>
    dplyr::filter(.data$country %in% countries) |>
    dplyr::distinct(.data$alias, .keep_all = TRUE) |>
    dplyr::arrange(dplyr::desc(nchar(.data$alias)))

  for (i in seq_len(nrow(aliases))) {
    alias <- aliases$alias[[i]]
    if (stringr::str_starts(
      stringr::str_to_lower(value),
      stringr::fixed(stringr::str_to_lower(alias))
    )) {
      remainder <- stringr::str_sub(value, nchar(alias) + 1L)
      category <- stringr::str_match(remainder, "^\\s*-\\s*(.+)$")[1, 2]
      if (!is.na(category)) {
        return(paste(aliases$country[[i]], stringr::str_squish(category), sep = " - "))
      }
    }
  }

  parts <- stringr::str_match(value, "^(.+?)\\s+-\\s+(.+)$")
  if (!is.na(parts[1, 2])) {
    parent <- match_repository_country(parts[1, 2], countries)
    if (!is.na(parent)) return(paste(parent, stringr::str_squish(parts[1, 3]), sep = " - "))
  }
  NA_character_
}

normalise_case_data <- function(df, char) {
  df <- normalise_input_frame(df)

  required_columns(
    df,
    c(
      "Country", "Region", "WHO Region", "Last Policy Update",
      "Schizontocidal Drug", "Policy on G6PD Testing",
      "Implementation of G6PD Testing", "Policy on PQ",
      "Implementation of Treatment", "Next policy update (Y/N, Year)",
      "Treatments Under Consideration"
    ),
    "Case Mgmt Data Points"
  )

  countries <- char$Country
  raw_keys <- stringr::str_squish(df$Country)
  footnote <- stringr::str_detect(raw_keys, "^\\*+N/?A\\s*=")
  candidates <- nzchar(raw_keys) & !footnote
  standardized <- rep(NA_character_, length(raw_keys))
  standardized[candidates] <- vapply(
    raw_keys[candidates], standardise_case_country, character(1), countries = countries
  )

  excluded <- sum(!candidates | is.na(standardized))
  if (excluded) {
    warning(excluded, " non-country or unmatched case-management rows were excluded.", call. = FALSE)
  }
  df <- df[!is.na(standardized), , drop = FALSE]
  df$Country <- standardized[!is.na(standardized)]

  duplicates <- duplicated(df$Country)
  if (any(duplicates)) {
    warning(sum(duplicates), " duplicate case-management keys were excluded after retaining the first record.", call. = FALSE)
    df <- df[!duplicates, , drop = FALSE]
  }

  parent_country <- function(value) {
    if (value %in% countries) return(value)
    hits <- countries[stringr::str_starts(value, stringr::fixed(paste0(countries, " - ")))]
    if (length(hits)) hits[[which.max(nchar(hits))]] else ""
  }
  parents <- vapply(df$Country, parent_country, character(1))
  region <- stats::setNames(char$Region, char$Country)
  who_region <- stats::setNames(char$`WHO Region`, char$Country)
  df$Region <- unname(region[parents])
  df$`WHO Region` <- unname(who_region[parents])

  missing_main <- setdiff(countries, df$Country[!stringr::str_detect(df$Country, stringr::fixed(" - "))])
  if (length(missing_main)) {
    warning(
      "Case Mgmt Data Points has no country-level record for: ",
      paste(missing_main, collapse = ", "),
      call. = FALSE
    )
  }
  df
}

load_characteristic_data <- function(path = characteristic_data_source()) {
  normalise_characteristic_data(load_sheet(path))
}

load_case_data <- function(path = case_data_source(), char = NULL) {
  if (is.null(char)) char <- load_characteristic_data()
  normalise_case_data(load_sheet(path), char)
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
