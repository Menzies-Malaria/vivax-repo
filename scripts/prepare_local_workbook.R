#!/usr/bin/env Rscript

# Extract the two review sheets into local CSV inputs. The generated files stay
# under data/ (which is gitignored); deployment continues to use the two Google
# Sheet CSV feeds through CHAR_DATA_URL and CASE_DATA_URL.

suppressPackageStartupMessages({
  library(readr)
  library(readxl)
  library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)
workbook <- if (length(args)) args[[1]] else file.path(
  "data",
  "Vivax Policy and Implementation Data - latest per 28-10-2026.xlsx"
)

if (!file.exists(workbook)) {
  stop("Workbook not found: ", workbook, call. = FALSE)
}

required_sheets <- c("Characteristic Data", "Case Mgmt Data Points")
missing_sheets <- setdiff(required_sheets, excel_sheets(workbook))
if (length(missing_sheets)) {
  stop(
    "Workbook is missing sheet(s): ",
    paste(missing_sheets, collapse = ", "),
    call. = FALSE
  )
}

read_text_sheet <- function(sheet) {
  data <- read_excel(
    workbook,
    sheet = sheet,
    col_types = "text",
    .name_repair = "unique"
  )
  names(data) <- str_trim(names(data))
  data[is.na(data)] <- ""
  data
}

characteristic <- read_text_sheet("Characteristic Data")
case_management <- read_text_sheet("Case Mgmt Data Points")

required_characteristic <- c("Country", "Contact")
required_case <- c(
  "Country",
  "Comments [for repository country profile]",
  "Other Comments"
)

for (column in required_characteristic) {
  if (!column %in% names(characteristic)) {
    stop("Characteristic Data is missing `", column, "`.", call. = FALSE)
  }
}
for (column in required_case) {
  if (!column %in% names(case_management)) {
    stop("Case Mgmt Data Points is missing `", column, "`.", call. = FALSE)
  }
}

date_match <- str_match(basename(workbook), "(\\d{1,2}-\\d{1,2}-\\d{4})")[, 2]
date_label <- if (is.na(date_match)) format(Sys.Date(), "%d-%m-%Y") else date_match
data_dir <- dirname(workbook)
characteristic_path <- file.path(
  data_dir,
  paste0("characteristics_latest_", date_label, ".csv")
)
case_path <- file.path(
  data_dir,
  paste0("case_management_latest_", date_label, ".csv")
)

write_csv(characteristic, characteristic_path, na = "")
write_csv(case_management, case_path, na = "")

cat("Prepared local workbook inputs:\n")
cat("- ", characteristic_path, " (", nrow(characteristic), " rows)\n", sep = "")
cat("- ", case_path, " (", nrow(case_management), " rows)\n", sep = "")
