#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
root <- if (length(file_arg)) {
  normalizePath(file.path(dirname(file_arg), ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)
}

venv_python <- if (.Platform$OS.type == "windows") {
  file.path(root, ".venv", "Scripts", "python.exe")
} else {
  file.path(root, ".venv", "bin", "python")
}

translation_env <- c(
  ARGOS_PACKAGES_DIR = file.path(root, ".translation-cache", "packages"),
  XDG_DATA_HOME = file.path(root, ".translation-cache", "data"),
  XDG_CONFIG_HOME = file.path(root, ".translation-cache", "config"),
  XDG_CACHE_HOME = file.path(root, ".translation-cache", "cache"),
  ARGOS_DEVICE_TYPE = "cpu"
)
do.call(Sys.setenv, as.list(translation_env))

find_base_python <- function() {
  configured <- Sys.getenv("VIVAX_PYTHON", unset = "")
  candidates <- c(
    configured,
    Sys.which("python3"),
    Sys.which("python"),
    if (.Platform$OS.type == "windows") {
      c(
        file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python311", "python.exe"),
        file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python310", "python.exe")
      )
    } else character()
  )
  candidates <- unique(candidates[nzchar(candidates)])
  candidates[file.exists(candidates)][1]
}

run_checked <- function(command, args) {
  status <- system2(command, args, stdout = "", stderr = "")
  if (!identical(status, 0L)) {
    stop("Command failed: ", command, " ", paste(args, collapse = " "), call. = FALSE)
  }
}

dir.create(file.path(root, "assets", "translations"), recursive = TRUE, showWarnings = FALSE)
extractor <- file.path(root, "scripts", "extract_static_translations.py")
extract_python <- find_base_python()
if (length(extract_python) && !is.na(extract_python)) {
  run_checked(extract_python, c(extractor, root))
}
invisible(file.copy(
  file.path(root, "translations", "en.json"),
  file.path(root, "assets", "translations", "en.json"),
  overwrite = TRUE
))

base_python <- find_base_python()
python_for_check <- if (file.exists(venv_python)) venv_python else base_python
if (length(python_for_check) == 0 || is.na(python_for_check)) {
  stop(
    "Python 3.10 or 3.11 is required for the local Argos prototype. ",
    "Install Python, or set VIVAX_PYTHON to its executable.",
    call. = FALSE
  )
}

targets <- data.frame(
  code = c("es", "fr", "pt"),
  file = c("es.json", "fr.json", "pt.json"),
  stringsAsFactors = FALSE
)

translation_args <- function(code, output_file) {
  c(
    file.path(root, "scripts", "build_translations.py"),
    "--source", file.path(root, "translations", "en.json"),
    "--output", file.path(root, "assets", "translations", output_file),
    "--to-language", code
  )
}

cache_current <- vapply(seq_len(nrow(targets)), function(i) {
  identical(system2(
    python_for_check,
    c(translation_args(targets$code[i], targets$file[i]), "--check-only"),
    stdout = "",
    stderr = ""
  ), 0L)
}, logical(1))

if (!all(cache_current) && !file.exists(venv_python)) {
  message("Creating the local translation environment in .venv ...")
  run_checked(base_python, c("-m", "venv", file.path(root, ".venv")))
}

has_argos <- file.exists(venv_python) && system2(
  venv_python,
  c("-c", shQuote("import argostranslate")),
  stdout = FALSE,
  stderr = FALSE
) == 0L

if (!all(cache_current) && !has_argos) {
  message("Installing the pinned Argos dependency into .venv ...")
  run_checked(
    venv_python,
    c("-m", "pip", "install", "--disable-pip-version-check", "-r", file.path(root, "requirements-translation.txt"))
  )
}

for (i in seq_len(nrow(targets))) {
  if (!cache_current[i]) {
    run_checked(
      venv_python,
      translation_args(targets$code[i], targets$file[i])
    )
  }
}

# Post-render runs need the refreshed dictionaries copied into the already-built site.
site_translation_dir <- file.path(root, "_site", "assets", "translations")
if (dir.exists(file.path(root, "_site"))) {
  dir.create(site_translation_dir, recursive = TRUE, showWarnings = FALSE)
  invisible(file.copy(
    c(
      file.path(root, "assets", "translations", "en.json"),
      file.path(root, "assets", "translations", "es.json"),
      file.path(root, "assets", "translations", "fr.json"),
      file.path(root, "assets", "translations", "pt.json")
    ),
    site_translation_dir,
    overwrite = TRUE
  ))
}
