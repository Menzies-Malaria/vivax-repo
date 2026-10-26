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

latest_local_data <- function(pattern, fallback) {
  candidates <- Sys.glob(pattern)
  if (!length(candidates)) return(fallback)
  candidates[[which.max(file.info(candidates)$mtime)]]
}

characteristic_data_source <- function(
  local_path = latest_local_data(
    "data/characteristics_latest_*.csv",
    "data/characteristic_data.csv"
  )
) {
  explicit_path <- Sys.getenv("CHAR_DATA_PATH", unset = "")
  if (nzchar(explicit_path)) {
    if (!file.exists(explicit_path)) {
      stop("CHAR_DATA_PATH does not exist: ", explicit_path, call. = FALSE)
    }
    return(explicit_path)
  }

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
  local_path = latest_local_data(
    "data/case_management_latest_*.csv",
    "data/case_management.csv"
  )
) {
  explicit_path <- Sys.getenv("CASE_DATA_PATH", unset = "")
  if (nzchar(explicit_path)) {
    if (!file.exists(explicit_path)) {
      stop("CASE_DATA_PATH does not exist: ", explicit_path, call. = FALSE)
    }
    return(explicit_path)
  }

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

load_sheet <- function(path) {
  df <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE
  )
  df[is.na(df)] <- ""
  df[] <- lapply(df, function(column) {
    iconv(as.character(column), from = "", to = "UTF-8", sub = "�")
  })
  names(df) <- trimws(names(df))
  df
}

rename_alias <- function(df, canonical, aliases) {
  if (canonical %in% names(df)) return(df)
  hit <- aliases[aliases %in% names(df)]
  if (length(hit)) names(df)[names(df) == hit[[1]]] <- canonical
  df
}

ensure_columns <- function(df, columns) {
  missing <- setdiff(columns, names(df))
  for (column in missing) df[[column]] <- ""
  df
}

normalise_characteristic_schema <- function(df) {
  aliases <- list(
    "Proportion of P. vivax cases (2023) (%)" = c(
      "Proportion of P. vivax cases (2023)"
    ),
    "Pv 1st line treatment" = c(
      "Schizontocidal - Pv 1st line treatment"
    ),
    "Pv 2nd line treatment" = c(
      "Schizontocidal Pv 2nd line treatment"
    ),
    "Implementation: G6PD testing  (Y/N)" = c(
      "Implementation: G6PD testing  (Y/N,partial)"
    )
  )
  for (canonical in names(aliases)) {
    df <- rename_alias(df, canonical, aliases[[canonical]])
  }
  proportion_col <- "Proportion of P. vivax cases (2023) (%)"
  if (proportion_col %in% names(df)) {
    raw <- stringr::str_squish(df[[proportion_col]])
    numeric <- suppressWarnings(readr::parse_number(raw))
    reported <- !is.na(numeric)
    if (any(reported) && max(numeric[reported]) <= 1) {
      scaled <- sprintf("%.1f", numeric * 100)
      scaled <- sub("\\.0$", "", scaled)
      df[[proportion_col]][reported] <- scaled[reported]
    }
  }
  ensure_columns(df, c(
    "Vivax endemicity",
    "To be included in current repository",
    "Community malaria care - details",
    "Community vivax care - details",
    "Cross-border transmission - details",
    "Mobile Migrant Populations - details"
  ))
}

normalise_case_schema <- function(df) {
  df <- rename_alias(
    df,
    "Comments",
    c("Comments [for repository country profile]")
  )
  df <- ensure_columns(df, c(
    "Comments",
    "Tafenoquine",
    "Low-dose PQ14 (0.25mg/kg)",
    "High-dose PQ14 (0.5mg/kg)",
    "Low-dose PQ7 (0.5mg/kg)",
    "High-dose PQ7 (1mg/kg)",
    "Implementation of Treatment",
    "Implementation of Treatment - details",
    "Health System Level of Treatment Implementation",
    "Health System Level of Treatment Implementation - details",
    "Year of Treatment Policy Implementation",
    "Implementatin of follow-up",
    "Year of Follow-Up Implementation"
  ))

  # Some spreadsheet-to-CSV exports replace Unicode comparison signs and
  # Windows punctuation with placeholders. Repair only the known affected
  # fields so genuine question marks elsewhere remain untouched.
  df[] <- lapply(df, function(column) {
    column |>
      stringr::str_replace_all(stringr::fixed("<96>"), "–") |>
      stringr::str_replace_all(stringr::fixed("<97>"), "—")
  })

  category_col <- "Categorization of G6PD Status Used"
  if (category_col %in% names(df)) {
    deficient <- stringr::str_detect(
      stringr::str_to_lower(df[[category_col]]),
      "deficient"
    ) & !stringr::str_detect(
      stringr::str_to_lower(df[[category_col]]),
      "intermediate"
    )
    df[[category_col]][deficient] <- stringr::str_replace_all(
      df[[category_col]][deficient],
      "\\?(?=\\s*\\d)",
      "≤"
    )
    df[[category_col]][!deficient] <- stringr::str_replace_all(
      df[[category_col]][!deficient],
      "\\?(?=\\s*\\d)",
      "≥"
    )
  }

  banding_cols <- intersect(
    c("PQ Weight-based banding", "Schizontocidal weight-based banding"),
    names(df)
  )
  for (column in banding_cols) {
    df[[column]] <- stringr::str_replace_all(
      df[[column]],
      "\\?(?=\\s*\\d)",
      "≥"
    )
  }

  df
}

positive_policy_flag <- function(value) {
  stringr::str_to_lower(stringr::str_squish(as.character(value))) %in%
    c("yes", "pilot")
}

radical_cure_policy_label <- function(value) {
  policy <- stringr::str_to_lower(stringr::str_squish(as.character(value)))
  missing <- !nzchar(policy) | policy %in% c("na", "n/a", "unknown", "not reported")
  has_pq <- stringr::str_detect(policy, "primaquine|\\bpq\\b")
  has_tq <- stringr::str_detect(policy, "tafenoquine|\\btq\\b")
  day_7 <- stringr::str_detect(policy, "7\\s*[- ]?days?|over\\s+7")
  day_14 <- stringr::str_detect(policy, "14\\s*[- ]?days?|over\\s+14")
  dose_025 <- stringr::str_detect(policy, "0\\s*\\.\\s*25\\s*mg\\s*/\\s*kg")
  dose_05 <- stringr::str_detect(policy, "0\\s*\\.\\s*5\\s*mg\\s*/\\s*kg")
  dose_1 <- stringr::str_detect(policy, "(?:^|[^0-9])1(?:\\.0)?\\s*mg\\s*/\\s*kg")
  low_dose <- stringr::str_detect(policy, "low[- ]dose")
  high_dose <- stringr::str_detect(policy, "high[- ]dose")

  dplyr::case_when(
    missing ~ "Not reported",
    stringr::str_detect(policy, "no primaquine|primaquine.*not|not recommend") ~ "No primaquine",
    has_tq & has_pq ~ "Primaquine or tafenoquine",
    has_tq ~ "Tafenoquine",
    stringr::str_detect(policy, "weekly|8\\s*weeks?") ~ "Weekly primaquine for 8 weeks",
    day_7 & day_14 ~ "7- or 14-day primaquine (dose not specified)",
    day_7 & (high_dose | dose_1) ~ "High-dose 7-day primaquine",
    day_7 & (low_dose | dose_05) ~ "Low-dose 7-day primaquine",
    day_14 & (high_dose | dose_05) ~ "High-dose 14-day primaquine",
    day_14 & (low_dose | dose_025) ~ "Low-dose 14-day primaquine",
    day_7 ~ "7-day primaquine (dose not specified)",
    day_14 ~ "14-day primaquine (dose not specified)",
    has_pq ~ "Other primaquine regimen",
    TRUE ~ "Other policy"
  )
}

radical_cure_regimen_tags <- function(row) {
  value <- function(column) {
    if (!column %in% names(row)) return("")
    as.character(row[[column]][[1]])
  }
  policy <- value("Policy on PQ")
  label <- radical_cure_policy_label(policy)
  tags <- character()

  if (positive_policy_flag(value("Tafenoquine")) ||
      stringr::str_detect(stringr::str_to_lower(policy), "tafenoquine|\\btq\\b")) {
    tags <- c(tags, "Tafenoquine")
  }
  if (identical(label, "Weekly primaquine for 8 weeks") ||
      positive_policy_flag(value("8-week PQ"))) {
    tags <- c(tags, "Weekly primaquine for 8 weeks")
  }

  duration_label <- label %in% c(
    "High-dose 7-day primaquine",
    "Low-dose 7-day primaquine",
    "High-dose 14-day primaquine",
    "Low-dose 14-day primaquine",
    "7-day primaquine (dose not specified)",
    "14-day primaquine (dose not specified)",
    "7- or 14-day primaquine (dose not specified)"
  )
  if (duration_label) {
    tags <- c(tags, label)
  } else {
    if (positive_policy_flag(value("Low-dose PQ7 (0.5mg/kg)"))) {
      tags <- c(tags, "Low-dose 7-day primaquine")
    }
    if (positive_policy_flag(value("High-dose PQ7 (1mg/kg)"))) {
      tags <- c(tags, "High-dose 7-day primaquine")
    }
    if (positive_policy_flag(value("Low-dose PQ14 (0.25mg/kg)"))) {
      tags <- c(tags, "Low-dose 14-day primaquine")
    }
    if (positive_policy_flag(value("High-dose PQ14 (0.5mg/kg)"))) {
      tags <- c(tags, "High-dose 14-day primaquine")
    }
  }

  unique(tags)
}

normalise_country_key <- function(value) {
  value |>
    as.character() |>
    stringr::str_squish() |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[^a-z0-9]+", " ") |>
    stringr::str_squish()
}

standardise_case_countries <- function(case, characteristic) {
  country_names <- characteristic$Country
  country_keys <- normalise_country_key(country_names)
  aliases <- c(
    "PNG" = "Papua New Guinea",
    "Papua New Guinea (PNG)" = "Papua New Guinea",
    "ROK" = "Republic of Korea (ROK)",
    "United Republic of Tanzania (Zanzibar)" = "United Republic of Tanzania (Zamzibar)"
  )
  lookup <- data.frame(
    alias = c(country_names, names(aliases)),
    country = c(country_names, unname(aliases)),
    stringsAsFactors = FALSE
  )
  lookup <- lookup[order(nchar(lookup$alias), decreasing = TRUE), , drop = FALSE]

  match_country <- function(value) {
    key <- normalise_country_key(value)
    exact <- which(country_keys == key)
    if (length(exact) == 1L) return(country_names[[exact]])
    alias <- lookup$country[normalise_country_key(lookup$alias) == key]
    if (length(alias)) return(alias[[1]])
    NA_character_
  }

  standardise_one <- function(value) {
    value <- stringr::str_squish(value)
    direct <- match_country(value)
    if (!is.na(direct)) return(direct)
    for (i in seq_len(nrow(lookup))) {
      alias <- lookup$alias[[i]]
      if (stringr::str_starts(
        stringr::str_to_lower(value),
        stringr::fixed(stringr::str_to_lower(alias))
      )) {
        remainder <- stringr::str_sub(value, nchar(alias) + 1L)
        category <- stringr::str_match(remainder, "^\\s*-\\s*(.+)$")[1, 2]
        if (!is.na(category)) {
          return(paste(lookup$country[[i]], stringr::str_squish(category), sep = " - "))
        }
      }
    }
    value
  }

  case$Country <- vapply(case$Country, standardise_one, character(1))
  case
}

load_characteristic_data <- function(path = characteristic_data_source()) {
  load_sheet(path) |>
    normalise_characteristic_schema()
}

load_case_data <- function(path = case_data_source(), characteristic = NULL) {
  case <- load_sheet(path) |>
    normalise_case_schema()
  if (!is.null(characteristic)) {
    case <- standardise_case_countries(case, characteristic)
  }
  case
}

repository_rows <- function(char, include_historical = TRUE) {
  scope <- stringr::str_to_lower(stringr::str_squish(
    char$`To be included in current repository`
  ))
  if (any(scope == "yes")) {
    char <- char[scope == "yes", , drop = FALSE]
  } else if (!include_historical) {
    endemicity <- stringr::str_to_lower(stringr::str_squish(char$`Vivax endemicity`))
    char <- char[endemicity == "yes", , drop = FALSE]
  }
  char
}

headline_stats <- function(char, case) {
  case_main <- case |>
    dplyr::filter(
      !stringr::str_detect(.data$Country, " - "),
      .data$Country %in% char$Country
    )

  list(
    n_countries = dplyr::n_distinct(char$Country),
    n_current_or_previous_endemic = sum(
      stringr::str_to_lower(stringr::str_squish(char$`Vivax endemicity`)) %in%
        c("yes", "previously")
    ),
    n_implementing = sum(trimws(char$`Implementation: G6PD testing  (Y/N)`) == "Yes"),
    n_with_policy = sum(nzchar(trimws(case_main$`Last Policy Update`)))
  )
}

column_dictionary_notes <- function() {
  c(
    "Country" = "Country or territory name.",
    "Region" = "Project-defined region: Africa, Asia-Pacific, or Central and South America.",
    "WHO Region" = "WHO region: African, Americas, Eastern Mediterranean, South-East Asia, Western Pacific.",
    "Vivax endemicity" = "Whether P. vivax malaria is currently endemic, previously endemic, or not endemic.",
    "To be included in current repository" = "Whether the country is currently within the repository's agreed scope.",
    "Reporting vivax cases (<5 years)" = "Whether the country has reported any vivax cases in the last five years.",
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
    "Contact" = "Programme focal point or other point of contact.",
    "Email" = "Approved public email address for the programme contact. Display is controlled separately from the data feed."
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
