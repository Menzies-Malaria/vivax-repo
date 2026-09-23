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

html_escape <- function(s) {
  s |>
    str_replace_all("&", "&amp;") |>
    str_replace_all("<", "&lt;") |>
    str_replace_all(">", "&gt;") |>
    str_replace_all('"', "&quot;") |>
    str_replace_all("'", "&#39;")
}

url_links <- function(value) {
  urls <- str_split(value, "\\s*;\\s*|\\s+(?=https?://)")[[1]] |>
    str_trim()
  urls <- urls[nzchar(urls)]

  valid <- str_detect(urls, "^https?://[^\\s<>\\\"']+$")
  if (!length(urls) || !all(valid)) return(md_escape(value))

  links <- vapply(urls, function(url) {
    safe_url <- html_escape(url)
    sprintf(
      '<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>',
      safe_url,
      safe_url
    )
  }, character(1))

  paste(links, collapse = "<br>")
}

kv_table <- function(rows) {
  lines <- c("| | |", "|---|---|")
  url_labels <- c("Treatment guidelines (URL)", "National Strategic Plan (URL)")
  for (i in seq_len(nrow(rows))) {
    label <- rows$label[i]
    value <- str_trim(rows$value[i])
    if (!nzchar(value)) {
      rendered_value <- "_Not reported_"
    } else if (label %in% url_labels) {
      rendered_value <- url_links(value)
    } else {
      rendered_value <- md_escape(value)
    }
    lines <- c(lines, sprintf("| **%s** | %s |", label, rendered_value))
  }
  paste(lines, collapse = "\n")
}

row_val <- function(row, col, default = "") {
  if (!col %in% names(row)) return(default)
  v <- str_trim(as.character(row[[col]]))
  if (!nzchar(v) || toupper(v) == "NA") default else v
}

write_utf8_lines <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(lines, con = con, sep = "\n", useBytes = TRUE)
}

source(file.path(root, "R", "data_helpers.R"))
CHAR_URL <- characteristic_data_source(
  file.path(root, "data", "characteristic_data.csv")
)
CASE_URL <- case_data_source(
  file.path(root, "data", "case_management.csv")
)
char <- load_characteristic_data(CHAR_URL)
case <- load_case_data(CASE_URL)

include_public_email <- tolower(Sys.getenv("INCLUDE_PUBLIC_EMAIL", unset = "0")) %in%
  c("1", "true", "yes", "on")

email_links <- function(value) {
  emails <- str_split(value, "\\s*[;,]\\s*")[[1]] |>
    str_trim()
  emails <- emails[nzchar(emails)]
  valid <- str_detect(
    emails,
    "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
  )
  if (!length(emails) || !all(valid)) return(md_escape(value))

  links <- vapply(emails, function(email) {
    safe <- html_escape(email)
    sprintf('<a href="mailto:%s">%s</a>', safe, safe)
  }, character(1))

  paste(links, collapse = "<br>")
}

profile_table <- function(title, rows) {
  c(
    "::: {.country-profile-card}",
    paste0("### ", title),
    "",
    kv_table(rows),
    ":::",
    ""
  )
}

normalise_match <- function(value) {
  value <- str_to_lower(str_squish(as.character(value)))
  value[value %in% c("", "na", "n/a", "unknown", "not reported")] <- NA_character_
  value
}

similarity_fields <- tibble::tribble(
  ~column, ~label, ~weight, ~substantive,
  "Region", "region", 0.5, FALSE,
  "WHO Region", "WHO region", 0.5, FALSE,
  "Program Phase", "programme phase", 2, TRUE,
  "Pv 1st line treatment", "first-line treatment", 2, TRUE,
  "Guidelines G6PD testing  (Y/N)", "G6PD policy", 2, TRUE,
  "Implementation: G6PD testing  (Y/N)", "G6PD implementation", 2, TRUE,
  "Community vivax care", "community vivax care", 1, TRUE,
  "Follow-up of radical cure", "radical-cure follow-up", 1, TRUE,
  "Cross-border transmission", "cross-border setting", 1, TRUE,
  "Mobile Migrant Populations", "mobile/migrant-population setting", 1, TRUE
)

similarity_index <- as.data.frame(
  setNames(
    lapply(similarity_fields$column, function(col) normalise_match(char[[col]])),
    similarity_fields$column
  ),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

similar_countries <- function(current_row, all_rows, n = 3L) {
  current_country <- as.character(current_row$Country[[1]])
  current_index <- match(current_country, all_rows$Country)
  candidate_indices <- which(all_rows$Country != current_country)
  if (is.na(current_index) || !length(candidate_indices)) return(tibble::tibble())

  current_values <- as.character(similarity_index[current_index, , drop = TRUE])
  candidate_values <- as.matrix(similarity_index[candidate_indices, , drop = FALSE])
  current_matrix <- matrix(
    current_values,
    nrow = length(candidate_indices),
    ncol = length(current_values),
    byrow = TRUE
  )
  weight_matrix <- matrix(
    similarity_fields$weight,
    nrow = length(candidate_indices),
    ncol = nrow(similarity_fields),
    byrow = TRUE
  )
  substantive_matrix <- matrix(
    similarity_fields$substantive,
    nrow = length(candidate_indices),
    ncol = nrow(similarity_fields),
    byrow = TRUE
  )
  comparable <- !is.na(current_matrix) & !is.na(candidate_values)
  matches <- comparable & current_matrix == candidate_values
  comparable_weight <- rowSums(comparable * weight_matrix)
  matched_weight <- rowSums(matches * weight_matrix)

  scored <- tibble::tibble(
    country = all_rows$Country[candidate_indices],
    similarity = ifelse(comparable_weight > 0, matched_weight / comparable_weight, 0),
    comparable_weight = comparable_weight,
    substantive_matches = rowSums(matches & substantive_matrix),
    reasons = vapply(seq_len(nrow(matches)), function(i) {
      paste(similarity_fields$label[matches[i, ]], collapse = ", ")
    }, character(1))
  ) |>
    filter(
      .data$comparable_weight >= 6,
      .data$substantive_matches >= 3,
      .data$similarity >= 0.5,
      nzchar(.data$reasons)
    ) |>
    arrange(desc(.data$similarity), desc(.data$substantive_matches), .data$country) |>
    slice_head(n = n)

  scored
}

similar_country_cards <- function(current_row, all_rows) {
  matches <- similar_countries(current_row, all_rows)
  if (!nrow(matches)) return(character())

  cards <- vapply(seq_len(nrow(matches)), function(i) {
    country <- matches$country[i]
    sprintf(
      paste0(
        '<a class="similar-country-card" href="%s.html">',
        '<span class="name">%s</span>',
        '<span class="meta">Shared: %s</span>',
        "</a>"
      ),
      slug(country),
      html_escape(country),
      html_escape(matches$reasons[i])
    )
  }, character(1))

  c(
    "## Countries with similar reported characteristics",
    "",
    "These deterministic suggestions require agreement on at least three substantive reported characteristics and at least half of the comparable weighted fields. Missing values never count as matches. They are comparison aids, not formal epidemiological peer groups.",
    "",
    '<div class="similar-country-grid">',
    cards,
    "</div>",
    ""
  )
}

out_dir <- file.path(root, "profiles")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

old_profiles <- list.files(out_dir, pattern = "\\.qmd$", full.names = TRUE)
if (length(old_profiles)) invisible(file.remove(old_profiles))

case_main <- case |> filter(!str_detect(Country, " - "))
case_sub <- case |> filter(str_detect(Country, " - "))

sub_rows_for <- function(country) {
  prefix <- paste0(country, " -")
  case_sub |> filter(str_starts(Country, fixed(prefix)))
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
    "::: {.country-profile-spread}",
    profile_table("Country context", tibble::tibble(
      label = c(
        "Region", "WHO Region", "Reporting *P. vivax* cases (last 5 yrs)",
        "Programme phase", "Economic status", "Cross-border transmission",
        "Mobile / migrant populations", "High-risk populations"
      ),
      value = c(
        row_val(row, "Region"),
        row_val(row, "WHO Region"),
        row_val(row, "Reporting vivax cases (<5 years)"),
        row_val(row, "Program Phase"),
        row_val(row, "Economic status"),
        row_val(row, "Cross-border transmission"),
        row_val(row, "Mobile Migrant Populations"),
        row_val(row, "Type of high risk populations")
      )
    )),
    profile_table("Treatment and care", tibble::tibble(
      label = c(
        "First-line treatment", "Second-line treatment", "Rationale for ACT use",
        "G6PD testing in guidelines", "G6PD testing implemented",
        "Type of G6PD testing", "Community malaria care", "Community vivax care",
        "Follow-up of radical cure", "Community follow-up of radical cure"
      ),
      value = c(
        row_val(row, "Pv 1st line treatment"),
        row_val(row, "Pv 2nd line treatment"),
        row_val(row, "Rationale for ACT use"),
        row_val(row, "Guidelines G6PD testing  (Y/N)"),
        row_val(row, "Implementation: G6PD testing  (Y/N)"),
        row_val(row, "Type of G6PD testing"),
        row_val(row, "Community malaria care"),
        row_val(row, "Community vivax care"),
        row_val(row, "Follow-up of radical cure"),
        row_val(row, "Community follow-up of radical cure")
      )
    )),
    ":::",
    ""
  )

  contact_name <- row_val(row, "Contact")
  contact_email <- if (include_public_email) row_val(row, "Email") else ""
  if (nzchar(contact_name) || nzchar(contact_email)) {
    contact_rows <- tibble::tibble(
      label = "Programme contact",
      value = contact_name
    )
    if (nzchar(contact_email)) {
      contact_rows <- bind_rows(
        contact_rows,
        tibble::tibble(label = "Approved contact email", value = contact_email)
      )
    }
    contact_table <- kv_table(contact_rows)
    if (nzchar(contact_email)) {
      contact_table <- str_replace(
        contact_table,
        fixed(md_escape(contact_email)),
        email_links(contact_email)
      )
    }
    parts <- c(
      parts,
      "::: {.country-contact-card}",
      "### Programme contact",
      "",
      contact_table,
      ":::",
      ""
    )
  }

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
      num <- suppressWarnings(readr::parse_number(as.character(v)))
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
      num <- suppressWarnings(readr::parse_number(as.character(v)))
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
    policy_rows <- tibble::tibble(
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
    )
    comments <- row_val(cm_row, "Comments")

    parts <- c(
      parts,
      "## Case-management policy detail",
      "",
      kv_table(policy_rows),
      ""
    )
    if (nzchar(comments)) {
      comments_html <- html_escape(comments) |>
        str_replace_all("\\r\\n?|\\n", "<br>")
      parts <- c(
        parts,
        "### Country-specific policy context",
        "",
        sprintf('<div class="country-policy-context">%s</div>', comments_html),
        ""
      )
    }
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

  parts <- c(parts, similar_country_cards(row, char))

  parts <- c(
    parts,
    "---",
    "",
    "_Data on this page is read from the live Google Sheet at build time. To submit a correction or update, please use the [contribute form](../contribute.qmd)._",
    ""
  )

  write_utf8_lines(parts, file.path(out_dir, paste0(s, ".qmd")))
  n_written <- n_written + 1L
}

write_utf8_lines(
  c("page-layout: article", "toc: true", ""),
  file.path(out_dir, "_metadata.yml")
)

cat(sprintf("Wrote %d country profile pages.\n", n_written))
