#!/usr/bin/env Rscript

# Prepare the temporary main-branch checkout used by GitHub Actions to read
# the revised sheet schema. This does not modify the main branch itself.

suppressPackageStartupMessages({
  library(readr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript scripts/prepare_legacy_main_build.R <main-checkout>", call. = FALSE)
}

command_args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", command_args[grep("^--file=", command_args)])
prototype_root <- normalizePath(
  file.path(dirname(file_arg), ".."),
  mustWork = TRUE
)
main_root <- normalizePath(args[[1]], mustWork = TRUE)

source(file.path(prototype_root, "R", "data_helpers.R"))

char_path <- file.path(main_root, "data", "characteristic_data.csv")
case_path <- file.path(main_root, "data", "case_management.csv")
if (!file.exists(char_path) || !file.exists(case_path)) {
  stop("The main checkout is missing its downloaded CSV feeds.", call. = FALSE)
}

char <- load_characteristic_data(char_path)
case <- load_case_data(case_path, char)
write_csv(char, char_path, na = "")
write_csv(case, case_path, na = "")

# Quarto pages source this helper. Copying the compatibility version into the
# disposable checkout lets legacy pages accept both the old and revised names.
helper_target <- file.path(main_root, "R", "data_helpers.R")
if (!file.copy(
  file.path(prototype_root, "R", "data_helpers.R"),
  helper_target,
  overwrite = TRUE
)) {
  stop("Could not install the schema-compatible data helper.", call. = FALSE)
}

# The legacy profile generator validates URLs and then rereads the live feeds.
# In the disposable checkout, point it to the normalized downloads instead.
profile_script <- file.path(main_root, "scripts", "build_profiles.R")
lines <- readLines(profile_script, warn = FALSE, encoding = "UTF-8")
replacements <- c(
  'CHAR_URL <- require_sheet_url("CHAR_DATA_URL")' =
    'CHAR_URL <- file.path(root, "data", "characteristic_data.csv")',
  'CASE_URL <- require_sheet_url("CASE_DATA_URL")' =
    'CASE_URL <- file.path(root, "data", "case_management.csv")'
)

for (needle in names(replacements)) {
  hits <- which(lines == needle)
  if (length(hits) != 1L) {
    stop(
      "Expected exactly one legacy profile-generator line: ",
      needle,
      call. = FALSE
    )
  }
  lines[[hits]] <- replacements[[needle]]
}

writeLines(lines, profile_script, useBytes = TRUE)
message(
  "Prepared legacy main checkout with ", nrow(char),
  " characteristic rows and ", nrow(case), " case-management rows."
)
