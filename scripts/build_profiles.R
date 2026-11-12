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
  if (!nzchar(v) || v %in% c("NA", "N/A")) default else v
}

write_utf8_lines <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(lines, con = con, sep = "\n", useBytes = TRUE)
}

source(file.path(root, "R", "data_helpers.R"))
CHAR_URL <- characteristic_data_source(
  latest_local_data(
    file.path(root, "data", "characteristics_latest_*.csv"),
    file.path(root, "data", "characteristic_data.csv")
  )
)
CASE_URL <- case_data_source(
  latest_local_data(
    file.path(root, "data", "case_management_latest_*.csv"),
    file.path(root, "data", "case_management.csv")
  )
)
char <- load_characteristic_data(CHAR_URL)
char <- repository_rows(char)
case <- load_case_data(CASE_URL, char)
change_log <- load_change_log_data(change_log_data_source(
  file.path(root, "data", "change_log.csv")
))

repository_contact_email <- "malariapolicyrepository@gmail.com"

contact_name_only <- function(value) {
  emails <- extract_contact_emails(value)
  clean <- value
  for (email in emails) clean <- str_replace_all(clean, fixed(email), "")
  clean <- clean |>
    str_replace_all("\\s*[,;]\\s*[,;]+", ", ") |>
    str_replace_all("^[,;\\s]+|[,;\\s]+$", "") |>
    str_squish()
  if (str_to_lower(clean) %in% c("pending", "n/a", "not reported")) "" else clean
}

contact_display <- function(value) {
  approved <- approved_public_contact_emails()
  entries <- str_split(value, "\\s*;\\s*")[[1]] |>
    str_trim()
  entries <- entries[nzchar(entries)]

  rendered <- vapply(entries, function(entry) {
    emails <- extract_contact_emails(entry)
    emails <- emails[tolower(emails) %in% approved]
    name <- contact_name_only(entry)

    if (length(emails)) {
      label <- if (nzchar(name)) name else emails[[1]]
      return(sprintf(
        '<a href="mailto:%s">%s</a>',
        html_escape(emails[[1]]),
        html_escape(label)
      ))
    }

    md_escape(name)
  }, character(1))

  paste(rendered[nzchar(rendered)], collapse = "<br>")
}

contact_request_link <- function(country) {
  subject <- paste("Programme contact request -", country)
  body <- paste(
    "Hello Malaria Policy Repository team,",
    "",
    paste0("I would like to request contact with the malaria programme in ", country, "."),
    "",
    "Name:",
    "Organisation:",
    "Reason for the request:",
    sep = "\n"
  )
  href <- paste0(
    "mailto:", repository_contact_email,
    "?subject=", utils::URLencode(subject, reserved = TRUE),
    "&body=", utils::URLencode(body, reserved = TRUE)
  )
  sprintf(
    paste0(
      '<div class="country-contact-request">',
      '<p>Direct contact details are not publicly available.</p>',
      '<a class="country-contact-request__link" href="%s">',
      'Request contact through the repository team',
      '</a>',
      '</div>'
    ),
    html_escape(href)
  )
}

radical_cure_summary <- function(rows) {
  if (is.null(rows) || !nrow(rows)) return("")
  labels <- unique(unlist(lapply(seq_len(nrow(rows)), function(i) {
    radical_cure_regimen_tags(rows[i, , drop = FALSE])
  })))
  if (!length(labels)) {
    reported <- unique(rows$`Policy on PQ`[
      nzchar(str_squish(rows$`Policy on PQ`)) &
        !str_to_lower(str_squish(rows$`Policy on PQ`)) %in% c("n/a", "not specified")
    ])
    if (length(reported)) return(paste(reported, collapse = "; "))
    return("")
  }
  paste(unique(labels), collapse = "; ")
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

reported_profile_value <- function(value) {
  value <- str_trim(as.character(value))
  nzchar(value) & !str_to_upper(str_squish(value)) %in% c(
    "NA", "N/A", "UNKNOWN", "NOT REPORTED", "NOT SPECIFIED"
  )
}

profile_note_rows <- function(labels, values) {
  rows <- tibble::tibble(
    label = as.character(labels),
    value = str_trim(as.character(values))
  )
  rows[reported_profile_value(rows$value), , drop = FALSE]
}

profile_note_item <- function(label, value) {
  value <- html_escape(value) |>
    str_replace_all("\\r\\n?|\\n", "<br>")
  c(
    '<div class="country-note-item">',
    sprintf('<h4>%s</h4>', html_escape(label)),
    sprintf('<p>%s</p>', value),
    "</div>"
  )
}

profile_note_group <- function(title, rows, collapsible = TRUE) {
  if (!nrow(rows)) return(character())
  items <- unlist(lapply(seq_len(nrow(rows)), function(i) {
    profile_note_item(rows$label[[i]], rows$value[[i]])
  }), use.names = FALSE)
  note_label <- if (nrow(rows) == 1L) "1 note" else paste(nrow(rows), "notes")

  if (!collapsible) {
    return(c(
      '<section class="country-note-group country-note-group--visible">',
      sprintf('<h3>%s</h3>', html_escape(title)),
      '<div class="country-note-group__body">',
      items,
      "</div>",
      "</section>"
    ))
  }

  c(
    '<details class="country-note-group">',
    "<summary>",
    sprintf('<span>%s</span>', html_escape(title)),
    sprintf('<small>%s</small>', note_label),
    "</summary>",
    '<div class="country-note-group__body">',
    items,
    "</div>",
    "</details>"
  )
}

detailed_country_context <- function(row) {
  groups <- list(
    list(
      title = "Programme and transmission context",
      rows = profile_note_rows(
        c(
          "Subnational programme context",
          "Cross-border context",
          "Mobile and migrant population context",
          "High-risk populations"
        ),
        c(
          row_val(row, "Details of subnational program phases"),
          row_val(row, "Cross-border transmission - details"),
          row_val(row, "Mobile Migrant Populations - details"),
          row_val(row, "Type of high risk populations")
        )
      )
    ),
    list(
      title = "Diagnosis and G6PD context",
      rows = profile_note_rows(
        c(
          "Diagnostic approach",
          "G6PD deficiency prevalence",
          "G6PD prevalence research"
        ),
        c(
          row_val(row, "Type of malaria diagnostic (e.g., RDT, lab result, serology)"),
          row_val(row, "G6PD deficiency prevalence"),
          row_val(row, "Projects/Research determining G6PDd prevalence")
        )
      )
    ),
    list(
      title = "Treatment and community-care context",
      rows = profile_note_rows(
        c(
          "Rationale for ACT use",
          "Community malaria-care context",
          "Community vivax-care context"
        ),
        c(
          row_val(row, "Rationale for ACT use"),
          row_val(row, "Community malaria care - details"),
          row_val(row, "Community vivax care - details")
        )
      )
    )
  )

  groups <- groups[vapply(groups, function(group) nrow(group$rows) > 0, logical(1))]
  if (!length(groups)) return(character())

  all_rows <- bind_rows(lapply(groups, `[[`, "rows"))
  show_directly <- nrow(all_rows) <= 2L && sum(nchar(all_rows$value)) <= 500L
  rendered <- unlist(lapply(groups, function(group) {
    profile_note_group(group$title, group$rows, collapsible = !show_directly)
  }), use.names = FALSE)

  c(
    "## Detailed country context",
    "",
    "Country-specific information that adds context to the summary indicators above.",
    "",
    '<div class="country-note-groups">',
    rendered,
    "</div>",
    ""
  )
}

case_note_rows <- function(rows, columns, labels) {
  if (is.null(rows) || !nrow(rows)) return(tibble::tibble(label = character(), value = character()))
  output <- list()

  for (field_index in seq_along(columns)) {
    column <- columns[[field_index]]
    if (!column %in% names(rows)) next
    values <- str_trim(as.character(rows[[column]]))
    keep <- reported_profile_value(values)
    if (!any(keep)) next

    pairs <- tibble::tibble(
      category = vapply(seq_len(nrow(rows)), function(i) {
        g6pd_category_label(rows[i, , drop = FALSE])
      }, character(1)),
      value = values,
      reported = keep
    ) |>
      filter(.data$reported) |>
      select(-"reported") |>
      distinct(.data$category, .data$value)

    distinct_values <- unique(pairs$value)
    for (value in distinct_values) {
      categories <- unique(pairs$category[pairs$value == value])
      entry_label <- labels[[field_index]]
      if (length(distinct_values) > 1L) {
        entry_label <- paste0(entry_label, " — ", paste(categories, collapse = ", "))
      }
      output[[length(output) + 1L]] <- tibble::tibble(
        label = entry_label,
        value = value
      )
    }
  }

  if (!length(output)) return(tibble::tibble(label = character(), value = character()))
  bind_rows(output) |> distinct(.data$label, .data$value)
}

dosing_and_special_populations <- function(rows) {
  dosing <- case_note_rows(
    rows,
    c(
      "Dosage chart PQ vs total dose (adult)",
      "PQ Weight-based banding",
      "Schizontocidal weight-based banding"
    ),
    c(
      "Adult primaquine dosage",
      "Primaquine weight-based banding",
      "Schizontocidal weight-based banding"
    )
  )
  pregnancy <- case_note_rows(
    rows,
    c(
      "Pregnant - treatment 1st trimester",
      "Pregnant - treatment 2-3rd trimester",
      "Pregnant - CQ Prophylaxis (Y/N)",
      "Pregnant PQ recommedation"
    ),
    c(
      "Treatment in the first trimester",
      "Treatment in the second and third trimesters",
      "Chloroquine prophylaxis",
      "Primaquine recommendation"
    )
  )
  if (!nrow(dosing) && !nrow(pregnancy)) return(character())

  groups <- c(
    if (nrow(dosing)) profile_note_group("Dosing and weight banding", dosing, TRUE),
    if (nrow(pregnancy)) profile_note_group("Pregnancy and treatment policy", pregnancy, TRUE)
  )

  c(
    "### Dosing and special populations",
    "",
    "Reported dosing structures and treatment recommendations for specific populations.",
    "",
    '<div class="country-note-groups country-note-groups--case-management">',
    groups,
    "</div>",
    ""
  )
}

profile_prose_notes <- function(title, values) {
  values <- str_trim(as.character(values))
  values <- unique(values[reported_profile_value(values)])
  if (!length(values)) return(character())
  rows <- tibble::tibble(
    label = if (length(values) == 1L) "Policy note" else paste("Policy note", seq_along(values)),
    value = values
  )
  profile_note_group(title, rows, collapsible = TRUE)
}

g6pd_category_label <- function(row) {
  label <- row_val(row, "Categorization of G6PD Status Used")
  if (!nzchar(label)) {
    pieces <- str_split(row_val(row, "Country"), " - ", n = 2)[[1]]
    if (length(pieces) > 1) label <- pieces[[2]]
  }
  if (nzchar(label)) label else "Overall policy"
}

primaquine_treatment_table <- function(rows) {
  if (nrow(rows) == 0) return(character())

  body <- vapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    sprintf(
      "| **%s** | %s | %s | %s | %s | %s | %s | %s |",
      md_escape(g6pd_category_label(row)),
      md_escape(row_val(row, "Policy on PQ", "_Not specified_")),
      md_escape(row_val(row, "Implementation of Treatment", "_Not reported_")),
      md_escape(row_val(row, "Implementation of Treatment - details", "_Not reported_")),
      md_escape(row_val(row, "Health System Level of Treatment Implementation", "_Not reported_")),
      md_escape(row_val(row, "Health System Level of Treatment Implementation - details", "_Not reported_")),
      md_escape(row_val(row, "Year of Treatment Policy Implementation", "_Not reported_")),
      md_escape(row_val(row, "Additional Safey Recommendations", "_Not reported_"))
    )
  }, character(1))

  c(
    "::: {.country-policy-matrix}",
    "### Radical-cure treatment by G6PD status",
    "",
    "| G6PD category | Radical-cure treatment policy | Treatment implementation | Implementation details | Health-system level | Health-system details | Implementation year | Additional safety recommendations |",
    "|---|---|---|---|---|---|---|---|",
    body,
    ":::",
    ""
  )
}

primaquine_followup_table <- function(rows) {
  if (nrow(rows) == 0) return(character())

  body <- vapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    sprintf(
      "| **%s** | %s | %s | %s |",
      md_escape(g6pd_category_label(row)),
      md_escape(row_val(row, "Type of treatment follow-up (by whom, how often, where)", "_Not reported_")),
      md_escape(row_val(row, "Implementatin of follow-up", "_Not reported_")),
      md_escape(row_val(row, "Year of Follow-Up Implementation", "_Not reported_"))
    )
  }, character(1))

  c(
    "::: {.country-policy-matrix}",
    "### Radical-cure follow-up by G6PD status",
    "",
    "| G6PD category | Follow-up approach | Follow-up implementation | Follow-up implementation year |",
    "|---|---|---|---|",
    body,
    ":::",
    ""
  )
}

combined_treatment_followup_table <- function(rows) {
  if (nrow(rows) == 0) return(character())

  body <- vapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    sprintf(
      "| **%s** | %s | %s | %s | %s | %s | %s | %s |",
      md_escape(g6pd_category_label(row)),
      md_escape(row_val(row, "Policy on PQ", "_Not specified_")),
      md_escape(row_val(row, "Implementation of Treatment", "_Not reported_")),
      md_escape(row_val(row, "Implementation of Treatment - details", "_Not reported_")),
      md_escape(row_val(row, "Year of Treatment Policy Implementation", "_Not reported_")),
      md_escape(row_val(row, "Type of treatment follow-up (by whom, how often, where)", "_Not reported_")),
      md_escape(row_val(row, "Implementatin of follow-up", "_Not reported_")),
      md_escape(row_val(row, "Year of Follow-Up Implementation", "_Not reported_"))
    )
  }, character(1))

  c(
    "::: {.country-policy-matrix .country-policy-matrix--new}",
    '<div class="country-feature-new">NEW</div>',
    "### Combined treatment and follow-up by G6PD status",
    "",
    "| G6PD category | Radical-cure treatment policy | Treatment implementation | Treatment implementation details | Treatment implementation year | Follow-up approach | Follow-up implementation | Follow-up implementation year |",
    "|---|---|---|---|---|---|---|---|",
    body,
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

missing_similarity_fields <- setdiff(similarity_fields$column, names(char))
if (length(missing_similarity_fields)) {
  message(
    "Country similarity matching will ignore missing characteristic column(s): ",
    paste(missing_similarity_fields, collapse = ", ")
  )
}

similarity_index <- as.data.frame(
  setNames(
    lapply(similarity_fields$column, function(col) {
      values <- if (col %in% names(char)) char[[col]] else rep(NA_character_, nrow(char))
      normalise_match(values)
    }),
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

parse_change_date <- function(value) {
  value <- str_squish(as.character(value))
  formats <- c("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d %B %Y", "%d %b %Y")
  parsed <- rep(as.Date(NA), length(value))
  for (format in formats) {
    missing <- is.na(parsed) & nzchar(value)
    parsed[missing] <- as.Date(value[missing], format = format)
  }
  parsed
}

change_date_key <- function(value) {
  as.numeric(parse_change_date(value))
}

change_year_label <- function(value) {
  parsed <- parse_change_date(value)
  ifelse(is.na(parsed), "Date unavailable", format(parsed, "%Y"))
}

change_log_section <- function(country, all_changes) {
  country_key <- normalise_country_key(country)
  changes <- all_changes[
    normalise_country_key(all_changes$Country) == country_key,
    ,
    drop = FALSE
  ]

  intro <- "Approved updates published for this country."

  if (!nrow(changes)) {
    return(c(
      "## Version history",
      "",
      intro,
      "",
      '<div class="country-change-log country-change-log--empty">',
      "No published changes have been recorded for this country yet.",
      "</div>",
      ""
    ))
  }

  timeline_dates <- ifelse(
    nzchar(str_squish(changes$`Published date`)),
    changes$`Published date`,
    changes$`Effective date`
  )
  date_key <- change_date_key(timeline_dates)
  changes <- changes[order(-date_key, na.last = TRUE), , drop = FALSE]
  timeline_dates <- timeline_dates[order(-date_key, na.last = TRUE)]
  year_labels <- change_year_label(timeline_dates)

  entry_for <- function(i) {
    change <- changes[i, , drop = FALSE]
    published <- row_val(change, "Published date")
    summary <- row_val(change, "Public summary", "Repository record updated")
    effective <- row_val(change, "Effective date")
    display_date <- if (nzchar(published)) {
      published
    } else if (nzchar(effective)) {
      effective
    } else {
      "Date unavailable"
    }
    fields <- row_val(change, "Fields changed")
    source_type <- row_val(change, "Source type")
    source_url <- row_val(change, "Public source link")
    change_id <- row_val(change, "Change ID")

    meta <- character()
    if (nzchar(effective)) {
      meta <- c(meta, sprintf(
        '<div><dt>Effective date</dt><dd>%s</dd></div>',
        html_escape(effective)
      ))
    }
    if (nzchar(published)) {
      meta <- c(meta, sprintf(
        '<div><dt>Published date</dt><dd>%s</dd></div>',
        html_escape(published)
      ))
    }
    if (nzchar(source_type)) {
      meta <- c(meta, sprintf(
        '<div><dt>Source</dt><dd>%s</dd></div>',
        html_escape(source_type)
      ))
    }
    if (nzchar(change_id)) {
      meta <- c(meta, sprintf(
        '<div><dt>Change ID</dt><dd>%s</dd></div>',
        html_escape(change_id)
      ))
    }

    field_tags <- character()
    if (nzchar(fields)) {
      field_values <- str_split(fields, "\\s*[;,|]\\s*")[[1]] |>
        str_trim()
      field_values <- field_values[nzchar(field_values)]
      field_tags <- c(
        '<div class="country-change-log__fields" aria-label="Fields changed">',
        vapply(field_values, function(field) {
          sprintf('<span>%s</span>', html_escape(field))
        }, character(1)),
        "</div>"
      )
    }

    source_link <- character()
    if (nzchar(source_url) && str_detect(source_url, "^https?://[^\\s<>\\\"']+$")) {
      source_link <- sprintf(
        paste0(
          '<a class="country-change-log__source" href="%s" ',
          'target="_blank" rel="noopener noreferrer">View public source</a>'
        ),
        html_escape(source_url)
      )
    }

    c(
      '<article class="country-change-log__entry">',
      '<div class="country-change-log__marker" aria-hidden="true"></div>',
      '<details class="country-change-log__content">',
      '<summary class="country-change-log__summary">',
      '<div class="country-change-log__summary-main">',
      sprintf('<div class="country-change-log__date">%s</div>', html_escape(display_date)),
      sprintf('<h4>%s</h4>', html_escape(summary)),
      field_tags,
      "</div>",
      '<span class="country-change-log__toggle" aria-hidden="true"></span>',
      "</summary>",
      '<div class="country-change-log__details">',
      if (length(meta)) c('<dl class="country-change-log__meta">', meta, '</dl>') else character(),
      source_link,
      "</div>",
      "</details>",
      "</article>"
    )
  }

  years <- unique(year_labels)
  year_groups <- unlist(lapply(years, function(year) {
    indices <- which(year_labels == year)
    entries <- unlist(lapply(indices, entry_for), use.names = FALSE)
    c(
      '<section class="country-change-log__year">',
      sprintf(
        '<div class="country-change-log__year-label" role="heading" aria-level="3">%s</div>',
        html_escape(year)
      ),
      '<div class="country-change-log__entries">',
      entries,
      "</div>",
      "</section>"
    )
  }), use.names = FALSE)

  c(
    "## Version history",
    "",
    intro,
    "",
    '<div class="country-change-log">',
    year_groups,
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
  subs <- sub_rows_for(country)
  radical_summary <- radical_cure_summary(bind_rows(cm_row, subs))
  regimen_rows <- if (nrow(subs)) subs else cm_row
  g6pd_treatment_table <- if (!is.null(regimen_rows)) {
    primaquine_treatment_table(regimen_rows)
  } else character()
  g6pd_followup_table <- if (!is.null(regimen_rows)) {
    primaquine_followup_table(regimen_rows)
  } else character()
  combined_policy_table <- if (!is.null(regimen_rows)) {
    combined_treatment_followup_table(regimen_rows)
  } else character()
  profile_region <- row_val(row, "Region")
  region_countries <- char$Country[
    str_trim(as.character(char$Region)) == profile_region
  ] |>
    as.character() |>
    str_trim()
  region_countries <- region_countries[nzchar(region_countries)]

  yr_cols <- names(char)[str_detect(names(char), "Case Numbers")]
  yr_data <- setNames(
    as.list(vapply(yr_cols, function(c) row[[c]], character(1))),
    str_trim(str_remove(yr_cols, " Case Numbers"))
  )

  locator_block <- sprintf(
    paste0(
      '<div class="country-profile-locator" data-country="%s" data-region="%s" data-region-countries="%s">',
      '<div class="country-profile-locator__heading">Location</div>',
      '<div class="country-profile-locator__maps">',
      '<div class="country-profile-locator__map"><span>Global context</span><svg data-locator-view="global" role="img" aria-label="World map showing %s"></svg></div>',
      '<div class="country-profile-locator__map"><span>Regional context</span><svg data-locator-view="region" role="img" aria-label="%s regional map showing %s"></svg></div>',
      '</div>',
      '<p>The selected country is highlighted in orange; other repository countries in the same region are shown in teal.</p>',
      '</div>'
    ),
    html_escape(country),
    html_escape(profile_region),
    html_escape(paste(region_countries, collapse = "|")),
    html_escape(country),
    html_escape(profile_region),
    html_escape(country)
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
    "[← Back](../index.qmd){.profile-back-link .profile-map-return data-profile-map-return=true hidden=true}",
    "",
    "[Go to all countries](../countries.qmd){.profile-back-link .profile-all-countries-link}",
    "",
    "## Snapshot",
    "",
    profile_table("Country context", tibble::tibble(
      label = c(
        "Region", "WHO Region", "*P. vivax* endemicity",
        "Programme phase", "Subnational programme phases",
        "Cross-border transmission", "Mobile / migrant populations",
        "Economic status"
      ),
      value = c(
        row_val(row, "Region"),
        row_val(row, "WHO Region"),
        row_val(row, "Vivax endemicity"),
        row_val(row, "Program Phase"),
        row_val(row, "Sub-national program phases (Y/N)"),
        row_val(row, "Cross-border transmission"),
        row_val(row, "Mobile Migrant Populations"),
        row_val(row, "Economic status")
      )
    )),
    locator_block,
    "",
    profile_table("Treatment and care", tibble::tibble(
      label = c(
        "First-line schizontocidal treatment", "Second-line schizontocidal treatment",
        "Radical-cure regimen", "G6PD testing in guidelines", "G6PD testing implemented",
        "Type of G6PD testing", "Community malaria care",
        "Community vivax care",
        "Follow-up of radical cure", "Community follow-up of radical cure"
      ),
      value = c(
        row_val(row, "Pv 1st line treatment"),
        row_val(row, "Pv 2nd line treatment"),
        radical_summary,
        row_val(row, "Guidelines G6PD testing  (Y/N)"),
        row_val(row, "Implementation: G6PD testing  (Y/N)"),
        row_val(row, "Type of G6PD testing"),
        row_val(row, "Community malaria care"),
        row_val(row, "Community vivax care"),
        row_val(row, "Follow-up of radical cure"),
        row_val(row, "Community follow-up of radical cure")
      )
    )),
    detailed_country_context(row),
    ""
  )

  contact_raw <- row_val(row, "Contact")
  contact_name <- contact_name_only(contact_raw)
  contact_candidates <- extract_contact_emails(contact_raw)
  contact_candidates <- contact_candidates[
    tolower(contact_candidates) %in% approved_public_contact_emails()
  ]
  has_approved_contact_email <- length(contact_candidates) > 0
  rendered_contact <- contact_display(contact_raw)
  if (nzchar(rendered_contact)) {
    contact_rows <- tibble::tibble(
      label = "Programme contact",
      value = rendered_contact
    )
    contact_table <- kv_table(contact_rows)
    request_contact <- if (nzchar(contact_name) && !has_approved_contact_email) {
      contact_request_link(country)
    } else character()
    parts <- c(
      parts,
      "::: {.country-contact-card data-profile-contact=true}",
      "### Programme contact",
      "",
      contact_table,
      request_contact,
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
        "Last policy update", "Schizontocidal drug",
        "G6PD testing policy", "G6PD testing policy — details",
        "G6PD implementation", "G6PD implementation — details",
        "Year of G6PD implementation", "Health system level (G6PD)",
        "Health system level (G6PD) — details", "Policy on PQ (overall)",
        "Next policy update", "Treatments under consideration",
        "Treatment guidelines (URL)", "National Strategic Plan (URL)"
      ),
      value = c(
        row_val(cm_row, "Last Policy Update"),
        row_val(cm_row, "Schizontocidal Drug"),
        row_val(cm_row, "Policy on G6PD Testing"),
        row_val(cm_row, "Policy on G6PD Testing - details"),
        row_val(cm_row, "Implementation of G6PD Testing"),
        row_val(cm_row, "Implementation of G6PD Testing - details"),
        row_val(cm_row, "Year of G6PD Implementation"),
        row_val(cm_row, "Health System Level of G6PD Implementation"),
        row_val(cm_row, "Health System Level of G6PD Implementation - details"),
        row_val(cm_row, "Policy on PQ"),
        row_val(cm_row, "Next policy update (Y/N, Year)"),
        row_val(cm_row, "Treatments Under Consideration"),
        row_val(cm_row, "Treatment Guidelines"),
        row_val(cm_row, "National Strategic Plan")
      )
    )
    comment_rows <- bind_rows(cm_row, subs)
    profile_comments <- unique(str_trim(as.character(comment_rows$Comments)))
    profile_comments <- profile_comments[
      nzchar(profile_comments) & !toupper(profile_comments) %in% c("NA", "N/A")
    ]
    other_comments <- unique(str_trim(as.character(comment_rows$`Other Comments`)))
    other_comments <- other_comments[
      nzchar(other_comments) & !toupper(other_comments) %in% c("NA", "N/A")
    ]

    policy_blocks <- if (length(g6pd_treatment_table)) {
      pq_index <- match("Policy on PQ (overall)", policy_rows$label)
      c(
        kv_table(policy_rows[seq_len(pq_index), , drop = FALSE]),
        "",
        combined_policy_table,
        g6pd_treatment_table,
        g6pd_followup_table,
        kv_table(policy_rows[seq.int(pq_index + 1L, nrow(policy_rows)), , drop = FALSE]),
        ""
      )
    } else {
      c(kv_table(policy_rows), "")
    }

    parts <- c(
      parts,
      "## Case-management policy detail",
      "",
      policy_blocks,
      dosing_and_special_populations(bind_rows(cm_row, subs))
    )
    if (length(profile_comments)) {
      parts <- c(
        parts,
        '<div class="country-note-groups country-note-groups--case-management">',
        profile_prose_notes("Country-specific policy context", profile_comments),
        "</div>",
        ""
      )
    }
    if (length(other_comments)) {
      parts <- c(
        parts,
        '<div class="country-note-groups country-note-groups--case-management">',
        profile_prose_notes("Additional policy notes", other_comments),
        "</div>",
        ""
      )
    }
  } else if (length(g6pd_treatment_table)) {
    parts <- c(
      parts,
      "## Case-management policy detail",
      "",
      combined_policy_table,
      g6pd_treatment_table,
      g6pd_followup_table,
      dosing_and_special_populations(subs)
    )
  }

  parts <- c(parts, similar_country_cards(row, char))
  parts <- c(parts, change_log_section(country, change_log))

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
