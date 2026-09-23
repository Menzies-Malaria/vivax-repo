#!/usr/bin/env Rscript

# Normalize freshly downloaded Google Sheet CSV exports in place. The same
# normalization functions are used by Quarto pages and the profile generator.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
root <- if (length(file_arg)) {
  normalizePath(file.path(dirname(file_arg), ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)
}

source(file.path(root, "R", "data_helpers.R"))

char_path <- file.path(root, "data", "characteristic_data.csv")
case_path <- file.path(root, "data", "case_management.csv")

char <- load_characteristic_data(char_path)
case <- load_case_data(case_path)

write_csv(char, char_path, na = "")
write_csv(case, case_path, na = "")

message(
  "Normalized downloads: ", nrow(char), " characteristic country rows and ",
  nrow(case), " case-management rows."
)
