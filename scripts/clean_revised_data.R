#!/usr/bin/env Rscript

# Convert the reviewed Excel workbooks into deployment-ready CSV files.
# Source workbooks and the current live-feed snapshots are never overwritten.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(readxl)
  library(stringr)
})

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
root <- if (length(file_arg)) {
  normalizePath(file.path(dirname(file_arg), ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)
}

data_dir <- file.path(root, "data")
char_source <- file.path(data_dir, "characteristic data revised.xlsx")
case_source <- file.path(data_dir, "case management revised.xlsx")
char_output <- file.path(data_dir, "characteristic_data_cleaned.csv")
char_orphan_output <- file.path(data_dir, "characteristic_data_orphans.csv")
case_output <- file.path(data_dir, "case_management_cleaned.csv")
orphan_output <- file.path(data_dir, "case_management_orphans.csv")
report_output <- file.path(data_dir, "data_cleaning_review.md")

for (path in c(char_source, case_source)) {
  if (!file.exists(path)) stop("Required source workbook not found: ", path, call. = FALSE)
}

as_text <- function(df) {
  df <- mutate(df, across(everything(), ~ ifelse(is.na(.x), "", as.character(.x))))
  names(df) <- str_trim(names(df))
  df
}

trim_outer <- function(df) {
  mutate(df, across(everything(), str_trim))
}

is_blank_row <- function(df) {
  rowSums(as.data.frame(lapply(df, nzchar))) == 0
}

normalise_key <- function(x) {
  x |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", " ") |>
    str_squish()
}

format_number <- function(x) {
  out <- format(round(x, 6), trim = TRUE, scientific = FALSE)
  out <- str_replace(out, "(\\.[0-9]*?)0+$", "\\1")
  str_remove(out, "\\.$")
}

char_raw <- read_excel(char_source, sheet = "Characteristic Data") |>
  as_text() |>
  trim_outer()

char_blank_rows <- sum(is_blank_row(char_raw))
char_keyless_rows <- sum(!nzchar(char_raw$Country) & !is_blank_row(char_raw))

char_orphans <- char_raw |>
  filter(!nzchar(.data$Country), !is_blank_row(char_raw)) |>
  mutate(`Review reason` = "No country identifier supplied; formatting row", .before = 1)

char <- char_raw |>
  filter(nzchar(.data$Country))

if (anyDuplicated(char$Country)) {
  stop("Characteristic Data contains duplicate country names.", call. = FALSE)
}

new_prop <- "Proportion of P. vivax cases (2023)"
canonical_prop <- "Proportion of P. vivax cases (2023) (%)"
if (new_prop %in% names(char) && canonical_prop %in% names(char)) {
  stop("Both old and revised proportion columns are present; retain only one.", call. = FALSE)
}
if (new_prop %in% names(char)) names(char)[names(char) == new_prop] <- canonical_prop

if (canonical_prop %in% names(char)) {
  raw_prop <- char[[canonical_prop]]
  numeric_prop <- suppressWarnings(as.numeric(raw_prop))
  invalid_prop <- nzchar(raw_prop) & is.na(numeric_prop)
  if (any(invalid_prop)) {
    stop("The proportion column contains non-numeric values.", call. = FALSE)
  }
  fraction <- !is.na(numeric_prop) & numeric_prop >= 0 & numeric_prop <= 1
  numeric_prop[fraction] <- numeric_prop[fraction] * 100
  if (any(numeric_prop < 0 | numeric_prop > 100, na.rm = TRUE)) {
    stop("The normalized proportion column contains a value outside 0-100.", call. = FALSE)
  }
  char[[canonical_prop]] <- ifelse(is.na(numeric_prop), "", format_number(numeric_prop))
}

# Case-number fields must be numeric or blank. Spreadsheet "NA" markers are
# normalized to blank so readr does not emit type-inference warnings in builds.
case_number_columns <- names(char)[str_detect(names(char), "^20[0-9]{2} Case Numbers$")]
for (column in case_number_columns) {
  values <- char[[column]]
  values[str_to_upper(values) %in% c("NA", "N/A")] <- ""
  invalid <- nzchar(values) & is.na(suppressWarnings(as.numeric(values)))
  if (any(invalid)) {
    stop("Non-numeric case count found in `", column, "`.", call. = FALSE)
  }
  char[[column]] <- values
}

case_raw <- read_excel(case_source, sheet = "Case Mgmt Data Points") |>
  as_text() |>
  trim_outer()

case_fully_blank <- is_blank_row(case_raw)
case_keyless <- !nzchar(case_raw$Country) & !case_fully_blank
case_footnote <- str_detect(case_raw$Country, "^\\*+N/?A\\s*=")

orphans <- bind_rows(
  case_raw[case_keyless, , drop = FALSE] |>
    mutate(`Review reason` = "No country identifier supplied", .before = 1),
  case_raw[case_footnote, , drop = FALSE] |>
    mutate(`Review reason` = "Spreadsheet footnote, not a country record", .before = 1)
)

case <- case_raw |>
  filter(!case_fully_blank, !case_keyless, !case_footnote)

country_names <- char$Country
country_norm <- normalise_key(country_names)

# Abbreviations occurring in the reviewed workbook. All targets deliberately use
# the exact Characteristic Data spelling because it is the repository's country key.
aliases <- c(
  "PNG" = "Papua New Guinea",
  "Papua New Guinea (PNG)" = "Papua New Guinea",
  "ROK" = "Republic of Korea (ROK)"
)

match_country <- function(value) {
  value_norm <- normalise_key(value)
  exact <- which(country_norm == value_norm)
  if (length(exact) == 1) return(country_names[[exact]])

  alias_match <- aliases[normalise_key(names(aliases)) == value_norm]
  if (length(alias_match) == 1 && unname(alias_match) %in% country_names) {
    return(unname(alias_match))
  }

  distances <- as.numeric(adist(value_norm, country_norm, ignore.case = TRUE))
  best <- which(distances == min(distances))
  relative <- distances[best] / pmax(nchar(value_norm), nchar(country_norm[best]), 1)
  if (length(best) == 1 && relative <= 0.12) return(country_names[[best]])
  NA_character_
}

alias_table <- tibble(
  alias = c(country_names, names(aliases)),
  country = c(country_names, unname(aliases))
) |>
  distinct(.data$alias, .keep_all = TRUE) |>
  arrange(desc(nchar(.data$alias)))

standardise_case_key <- function(value) {
  value <- str_squish(value)

  # Exact/fuzzy country-level record.
  direct <- match_country(value)
  if (!is.na(direct)) return(direct)

  # Country-category record, allowing inconsistent spaces around the separator.
  for (i in seq_len(nrow(alias_table))) {
    alias <- alias_table$alias[[i]]
    if (str_starts(str_to_lower(value), fixed(str_to_lower(alias)))) {
      remainder <- str_sub(value, nchar(alias) + 1L)
      category <- str_match(remainder, "^\\s*-\\s*(.+)$")[1, 2]
      if (!is.na(category)) {
        return(paste(alias_table$country[[i]], str_squish(category), sep = " - "))
      }
    }
  }

  # Final fallback for an unrecognised prefix followed by the conventional separator.
  parts <- str_match(value, "^(.+?)\\s+-\\s+(.+)$")
  if (!is.na(parts[1, 2])) {
    parent <- match_country(parts[1, 2])
    if (!is.na(parent)) return(paste(parent, str_squish(parts[1, 3]), sep = " - "))
  }

  NA_character_
}

original_case_keys <- case$Country
standard_case_keys <- vapply(original_case_keys, standardise_case_key, character(1))
unmatched <- is.na(standard_case_keys)
if (any(unmatched)) {
  orphans <- bind_rows(
    orphans,
    case[unmatched, , drop = FALSE] |>
      mutate(`Review reason` = "Country identifier could not be matched", .before = 1)
  )
  case <- case[!unmatched, , drop = FALSE]
  original_case_keys <- original_case_keys[!unmatched]
  standard_case_keys <- standard_case_keys[!unmatched]
}
case$Country <- standard_case_keys

key_mappings <- tibble(original = original_case_keys, cleaned = standard_case_keys) |>
  filter(.data$original != .data$cleaned) |>
  distinct()

# Country metadata is governed by Characteristic Data, including its exact spelling.
country_from_key <- function(value) {
  hits <- country_names[str_starts(value, fixed(paste0(country_names, " - ")))]
  if (value %in% country_names) return(value)
  if (length(hits)) return(hits[[which.max(nchar(hits))]])
  ""
}
case_parent <- vapply(case$Country, country_from_key, character(1))
region_lookup <- setNames(char$Region, char$Country)
who_lookup <- setNames(char$`WHO Region`, char$Country)
case$Region <- unname(region_lookup[case_parent])
case$`WHO Region` <- unname(who_lookup[case_parent])

# Preserve the first reviewed record in production and isolate later conflicts.
duplicate_key <- duplicated(case$Country)
if (any(duplicate_key)) {
  orphans <- bind_rows(
    orphans,
    case[duplicate_key, , drop = FALSE] |>
      mutate(`Review reason` = "Duplicate country/category key; conflicting record requires review", .before = 1)
  )
  case <- case[!duplicate_key, , drop = FALSE]
}

main_keys <- case$Country[!str_detect(case$Country, fixed(" - "))]
missing_main <- setdiff(country_names, main_keys)
unexpected_main <- setdiff(main_keys, country_names)
if (length(missing_main) || length(unexpected_main)) {
  stop(
    "Cleaned case data failed country coverage validation. Missing: ",
    paste(missing_main, collapse = ", "), "; unexpected: ",
    paste(unexpected_main, collapse = ", "),
    call. = FALSE
  )
}
if (anyDuplicated(case$Country) || any(!nzchar(case$Country))) {
  stop("Cleaned case-management keys are not unique and complete.", call. = FALSE)
}

write_csv(char, char_output, na = "")
write_csv(char_orphans, char_orphan_output, na = "")
write_csv(case, case_output, na = "")
write_csv(orphans, orphan_output, na = "")

mapping_lines <- if (nrow(key_mappings)) {
  paste0("- `", key_mappings$original, "` -> `", key_mappings$cleaned, "`")
} else {
  "- None"
}

report <- c(
  "# Revised-data cleaning review",
  "",
  "This report contains structural information only. Contact and email values are not reproduced.",
  "",
  "## Characteristic Data",
  "",
  paste0("- Source rows: ", nrow(char_raw)),
  paste0("- Deployment rows: ", nrow(char)),
  paste0("- Completely blank rows removed: ", char_blank_rows),
  paste0("- Non-country formatting rows removed: ", char_keyless_rows),
  paste0("- Non-country rows isolated for review: ", nrow(char_orphans)),
  paste0("- Deployment columns: ", ncol(char)),
  paste0("- Percentage header normalized to `", canonical_prop, "`."),
  "- Excel fractional percentages were converted to values on the 0-100 scale expected by the website.",
  "",
  "## Case Mgmt Data Points",
  "",
  paste0("- Source rows: ", nrow(case_raw)),
  paste0("- Deployment rows: ", nrow(case)),
  paste0("- Completely blank rows removed: ", sum(case_fully_blank)),
  paste0("- Rows isolated for review: ", nrow(orphans)),
  paste0("- Country-level records: ", sum(!str_detect(case$Country, fixed(" - ")))),
  paste0("- Country/category records: ", sum(str_detect(case$Country, fixed(" - ")))),
  "- Country metadata was standardized from Characteristic Data.",
  "",
  "## Country-key corrections",
  "",
  mapping_lines,
  "",
  "## Outputs",
  "",
  "- `characteristic_data_cleaned.csv`",
  "- `characteristic_data_orphans.csv`",
  "- `case_management_cleaned.csv`",
  "- `case_management_orphans.csv`"
)
writeLines(report, report_output, useBytes = TRUE)

message("Wrote ", nrow(char), " cleaned characteristic rows to ", char_output)
message("Isolated ", nrow(char_orphans), " characteristic review rows in ", char_orphan_output)
message("Wrote ", nrow(case), " cleaned case-management rows to ", case_output)
message("Isolated ", nrow(orphans), " review rows in ", orphan_output)
message("Wrote structural review to ", report_output)
