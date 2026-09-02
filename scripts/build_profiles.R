#!/usr/bin/env Rscript
# Generates one .qmd file per country in `profiles/` from the live data.
# Run before `quarto render` (see README), or:
#   Rscript scripts/build_profiles.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
root <- if (length(file_arg)) {
  normalizePath(file.path(dirname(file_arg), ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)
}

data_source <- function(name, local_path) {
  url <- Sys.getenv(name, unset = "")
  if (nzchar(url)) {
    if (!grepl("^https?://", url)) {
      stop(name, " must be an https URL to the Google Sheet CSV export.", call. = FALSE)
    }
    return(url)
  }

  if (file.exists(local_path)) return(local_path)

  stop(
    name, " is not set and the local fallback was not found at ", local_path, ".",
    call. = FALSE
  )
}

CHAR_URL <- data_source(
  "CHAR_DATA_URL",
  file.path(root, "data", "characteristic_data.csv")
)
CASE_URL <- data_source(
  "CASE_DATA_URL",
  file.path(root, "data", "case_management.csv")
)

load_sheet <- function(path) {
  df <- read_csv(path, show_col_types = FALSE, na = character()) |>
    mutate(across(everything(), as.character))
  df[is.na(df)] <- ""
  names(df) <- str_trim(names(df))
  df
}

slug <- function(s) {
  s |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", "-") |>
    str_remove("^-+|-+$")
}

md_escape <- function(s) {
  if (length(s) == 0) return("")
  s <- as.character(s[[1]])
  if (grepl("^\\d+\\.0$", s)) s <- sub("\\.0$", "", s)
  s |>
    str_replace_all("\\|", "\\\\|") |>
    str_replace_all("\n", " ") |>
    str_trim()
}

kv_table <- function(rows) {
  lines <- c("| | |", "|---|---|")
  for (i in seq_len(nrow(rows))) {
    label <- rows$label[i]
    value <- str_trim(rows$value[i])
    if (!nzchar(value)) value <- "_Not reported_"
    lines <- c(lines, sprintf("| **%s** | %s |", label, md_escape(value)))
  }
  paste(lines, collapse = "\n")
}

row_val <- function(row, col, default = "") {
  if (!col %in% names(row)) return(default)
  v <- str_trim(as.character(row[[col]]))
  if (!nzchar(v) || toupper(v) == "NA") default else v
}

char <- load_sheet(CHAR_URL)
case <- load_sheet(CASE_URL)

out_dir <- file.path(root, "profiles")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

old_profiles <- list.files(out_dir, pattern = "\\.qmd$", full.names = TRUE)
if (length(old_profiles)) invisible(file.remove(old_profiles))

case_main <- case |> filter(!str_detect(Country, " - "))
case_sub <- case |> filter(str_detect(Country, " - "))

sub_rows_for <- function(country) {
  prefix <- paste0(country, " -")
  case_sub |> filter(str_starts(Country, prefix))
}

n_written <- 0L

for (i in seq_len(nrow(char))) {
  row <- char[i, , drop = FALSE]
  country <- str_trim(row$Country)
  if (!nzchar(country)) next

  s <- slug(country)
  cm <- case_main |> filter(str_trim(Country) == country)
  cm_row <- if (nrow(cm) > 0) cm[1, , drop = FALSE] else NULL

  yr_cols <- names(char)[str_detect(names(char), "Case Numbers")]
  yr_data <- setNames(
    as.list(vapply(yr_cols, function(c) row[[c]], character(1))),
    str_trim(str_remove(yr_cols, " Case Numbers"))
  )

  parts <- c(
    "---",
    sprintf('title: "%s"', country),
    sprintf(
      'subtitle: "%s · %s"',
      row_val(row, "WHO Region"),
      row_val(row, "Region")
    ),
    "page-layout: article",
    "toc: true",
    "---",
    "",
    "[← Back to all countries](../countries.qmd)",
    "",
    "## Snapshot",
    "",
    kv_table(tibble::tibble(
      label = c(
        "Region", "WHO Region", "Reporting *P. vivax* cases (last 5 yrs)",
        "Programme phase", "Economic status", "First-line treatment",
        "Second-line treatment", "Rationale for ACT use",
        "G6PD testing in guidelines", "G6PD testing implemented",
        "Type of G6PD testing", "Community malaria care", "Community vivax care",
        "Follow-up of radical cure", "Cross-border transmission",
        "Mobile / migrant populations", "High-risk populations", "Programme contact"
      ),
      value = c(
        row_val(row, "Region"),
        row_val(row, "WHO Region"),
        row_val(row, "Reporting vivax cases (<5 years)"),
        row_val(row, "Program Phase"),
        row_val(row, "Economic status"),
        row_val(row, "Pv 1st line treatment"),
        row_val(row, "Pv 2nd line treatment"),
        row_val(row, "Rationale for ACT use"),
        row_val(row, "Guidelines G6PD testing  (Y/N)"),
        row_val(row, "Implementation: G6PD testing  (Y/N)"),
        row_val(row, "Type of G6PD testing"),
        row_val(row, "Community malaria care"),
        row_val(row, "Community vivax care"),
        row_val(row, "Follow-up of radical cure"),
        row_val(row, "Cross-border transmission"),
        row_val(row, "Mobile Migrant Populations"),
        row_val(row, "Type of high risk populations"),
        row_val(row, "Contact")
      )
    )),
    ""
  )

  has_cases <- any(vapply(yr_data, function(v) {
    x <- str_trim(as.character(v))
    nzchar(x) && !toupper(x) %in% c("NA", "NAN")
  }, logical(1)))

  if (has_cases) {
    parts <- c(parts, "## Reported case numbers", "")

    yr_keys <- names(yr_data)
    yr_nums <- suppressWarnings(as.integer(str_extract(yr_keys, "\\d{4}")))
    yr_keys <- yr_keys[order(yr_nums, decreasing = TRUE, na.last = TRUE)]

    case_rows <- lapply(yr_keys, function(yr) {
      v <- yr_data[[yr]]
      num <- suppressWarnings(as.numeric(v))
      display <- if (!is.na(num) && is.finite(num)) {
        format(as.integer(num), big.mark = ",", scientific = FALSE, trim = TRUE)
      } else if (nzchar(str_trim(as.character(v)))) {
        as.character(v)
      } else {
        "_Not reported_"
      }
      tibble::tibble(label = yr, value = display)
    })
    case_tbl <- dplyr::bind_rows(case_rows)

    prop <- row_val(row, "Proportion of P. vivax cases (2023) (%)")
    if (nzchar(prop)) {
      case_tbl <- dplyr::bind_rows(
        case_tbl,
        tibble::tibble(
          label = "*P. vivax* share of malaria cases (2023)",
          value = paste0(prop, "%")
        )
      )
    }

    parts <- c(parts, kv_table(case_tbl), "")

    series <- list()
    for (yr in yr_keys[order(yr_nums, na.last = TRUE)]) {
      v <- yr_data[[yr]]
      num <- suppressWarnings(as.numeric(v))
      yr_label <- str_extract(yr, "\\d{4}")
      if (!is.na(num) && is.finite(num) && num > 0 && !is.na(yr_label)) {
        series[[length(series) + 1]] <- list(
          year = yr_label,
          value = as.integer(num)
        )
      }
    }

    if (length(series) >= 2) {
      chart_payload <- toJSON(
        list(country = country, series = series),
        auto_unbox = TRUE,
        pretty = FALSE,
        null = "null"
      )
      parts <- c(
        parts,
        "## Case trend",
        "",
        '<div class="vivax-chart">',
        '<div class="vivax-chart__plot vivax-chart__plot--cases-line" data-vivax-chart="cases-line"></div>',
        sprintf(
          '<script type="application/json" class="vivax-chart-payload">%s</script>',
          chart_payload
        ),
        "</div>",
        ""
      )
    }
  }

  if (!is.null(cm_row)) {
    parts <- c(
      parts,
      "## Case-management policy detail",
      "",
      kv_table(tibble::tibble(
        label = c(
          "Last policy update", "Schizontocidal drug", "G6PD testing policy",
          "G6PD implementation", "Year of G6PD implementation",
          "Health system level (G6PD)", "Policy on PQ (overall)",
          "Additional safety recommendations", "Treatment implementation",
          "Year of treatment implementation", "Type of treatment follow-up",
          "Implementation of follow-up", "Anti-malarials approved by NRA",
          "Next policy update", "Treatments under consideration",
          "Treatment guidelines (URL)", "National Strategic Plan (URL)"
        ),
        value = c(
          row_val(cm_row, "Last Policy Update"),
          row_val(cm_row, "Schizontocidal Drug"),
          row_val(cm_row, "Policy on G6PD Testing"),
          row_val(cm_row, "Implementation of G6PD Testing"),
          row_val(cm_row, "Year of G6PD Implementation"),
          row_val(cm_row, "Health System Level of G6PD Implementation"),
          row_val(cm_row, "Policy on PQ"),
          row_val(cm_row, "Additional Safey Recommendations"),
          row_val(cm_row, "Implementation of Treatment"),
          row_val(cm_row, "Year of Treatment Implementation"),
          row_val(cm_row, "Type of treatment follow-up (by whom, how often, where)"),
          row_val(cm_row, "Implementatin of follow-up"),
          row_val(cm_row, "Anti-malarials approved by NRAs"),
          row_val(cm_row, "Next policy update (Y/N, Year)"),
          row_val(cm_row, "Treatments Under Consideration"),
          row_val(cm_row, "Treatment Guidelines"),
          row_val(cm_row, "National Strategic Plan")
        )
      )),
      ""
    )
  }

  subs <- sub_rows_for(country)
  if (nrow(subs) > 0) {
    parts <- c(
      parts,
      "## Primaquine regimens by G6PD status",
      "",
      "| G6PD status | Policy on PQ | Additional safety |",
      "|---|---|---|"
    )
    for (j in seq_len(nrow(subs))) {
      sr <- subs[j, , drop = FALSE]
      label <- str_split(sr$Country, " - ", n = 2)[[1]][2]
      pq <- row_val(sr, "Policy on PQ", "_Not specified_")
      safe <- row_val(sr, "Additional Safey Recommendations")
      parts <- c(
        parts,
        sprintf(
          "| **%s** | %s | %s |",
          md_escape(label),
          md_escape(pq),
          md_escape(safe)
        )
      )
    }
    parts <- c(parts, "")
  }

  if (!is.null(cm_row)) {
    comments <- row_val(cm_row, "Comments")
    if (nzchar(comments)) {
      parts <- c(parts, "## Notes", "", comments, "")
    }
  }

  parts <- c(
    parts,
    "---",
    "",
    "_Data on this page is read from the live Google Sheet at build time. To submit a correction or update, please use the [contribute form](../contribute.qmd)._",
    ""
  )

  writeLines(parts, file.path(out_dir, paste0(s, ".qmd")), useBytes = TRUE)
  n_written <- n_written + 1L
}

writeLines(
  c("page-layout: article", "toc: true", "toc-depth: 3", ""),
  file.path(out_dir, "_metadata.yml"),
  useBytes = TRUE
)

cat(sprintf("Wrote %d country profile pages.\n", n_written))
