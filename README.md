# *P. vivax* Policy Repository

A Quarto-built website that serves as a live, country-level repository of *Plasmodium vivax* case management policies and their implementation status, designed for National Malaria Control Programmes (NMCPs), researchers, and partners.

The data lives in a Google Sheet. Updates flow in either directly (programme team edits the sheet) or via a Google Form embedded on the site (NMCP focal points submit changes). The site reads the sheet at build time and renders to static HTML.

## What's in this repository

```
.
├── _quarto.yml                # Quarto project config
├── theme.scss                 # SCSS theme (typography, colours)
├── assets/                    # Logo, extra CSS
├── index.qmd                  # Homepage
├── explore.qmd                # Interactive data explorer
├── countries.qmd              # Index of country profiles
├── timeline.qmd               # Policy update timeline
├── methods.qmd                # How the repository works
├── contribute.qmd             # Embedded Google Form
├── data.qmd                   # Downloads + column dictionary
├── profiles/                  # Auto-generated per-country pages (one .qmd each)
├── data/                      # CSV snapshots of the live sheet
├── scripts/
│   └── build_profiles.R       # Regenerates profiles/*.qmd from current data
└── .github/workflows/         # CI: fetches sheet → renders → publishes
```

## Quickstart (local)

```bash
# 1. Install R deps (one-time)
Rscript -e 'install.packages(c("readr", "dplyr", "stringr", "jsonlite", "crosstalk", "DT", "htmltools", "knitr"), repos = "https://cloud.r-project.org")'

# 2. Install Quarto (one-time): https://quarto.org/docs/get-started/

# 3. Build the country profile pages from the current data
Rscript scripts/build_profiles.R

# 4. Preview the site
quarto preview
```

The site will open at <http://localhost:7676>.

## How the Google Sheet is wired up

The site reads two CSVs at build time. These can come from one of two sources:

### Option A — local CSVs (default; useful for development)

The `data/` folder ships with CSV snapshots. With no environment variables set, the site reads those.

### Option B — a live Google Sheet (recommended for production)

1. Create a new Google Sheet. Add two tabs named exactly `Characteristic Data` and `Case Mgmt Data Points`. Copy the headers from `data/characteristic_data.csv` and `data/case_management.csv` into those tabs respectively, then paste the rows.
2. **File → Share → Publish to web.** Pick each tab in turn, choose **CSV** as the format, and tick **Automatically republish when changes are made**. Copy the resulting URL.
3. Set two environment variables (locally in your terminal, or as GitHub repo secrets) before building:

   ```bash
   export CHAR_DATA_URL="https://docs.google.com/spreadsheets/d/<ID>/pub?gid=<GID_1>&single=true&output=csv"
   export CASE_DATA_URL="https://docs.google.com/spreadsheets/d/<ID>/pub?gid=<GID_2>&single=true&output=csv"
   Rscript scripts/build_profiles.R
   quarto render
   ```

   On GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Name them `CHAR_DATA_URL` and `CASE_DATA_URL`. The workflow in `.github/workflows/publish.yml` picks them up automatically.

After Option B is in place, edits to the Google Sheet land on the public site the next time the workflow runs (weekly Monday at 06:00 UTC, or whenever you manually trigger it under **Actions → Publish → Run workflow**).

## How the Google Form is wired up

1. **Create a Google Form** — do **not** build it by hand. Follow **[docs/google-form-quickstart.md](docs/google-form-quickstart.md)** (copy two files into Apps Script, run once → all 42 questions appear). Question wording lives in [`docs/google-form-template.md`](docs/google-form-template.md).
2. In the form's **Responses** tab, click the green Sheets icon, and link it to your existing Google Sheet. This creates a new tab in that sheet called something like `Form Responses 1` — rename it to **`Submissions`** for clarity. Every submission appends a row.
3. In the form's editor, click **Send → embed (`< >`)**. Copy the `src` URL of the iframe it gives you (it looks like `https://docs.google.com/forms/d/e/.../viewform?embedded=true`).
4. Open `contribute.qmd` and paste that URL into the `src` attribute of the iframe, replacing the placeholder `REPLACE_WITH_YOUR_FORM_ID`. Commit and push.

Your team then reviews `Submissions` and copies validated rows over to the canonical `Characteristic Data` / `Case Mgmt Data Points` tabs.

## Editorial workflow

```
NMCP focal point ──► Google Form ──► Sheet (Submissions tab)
                                         │
                                         │  team reviews + reconciles
                                         ▼
                            Sheet (canonical tabs)
                                         │
                                         │  GitHub Actions (weekly)
                                         ▼
                                  Live website
```

## Deploying to GitHub Pages

1. Push this repo to GitHub.
2. **Settings → Pages → Source:** "GitHub Actions".
3. Add `CHAR_DATA_URL` and `CASE_DATA_URL` repo secrets (see above).
4. Push to `main` or trigger **Actions → Publish**.

The site will be served at `https://<your-org>.github.io/<repo-name>/`.

## Updating the data dictionary

`data.qmd` has a column dictionary in `R/data_helpers.R` (`column_dictionary_notes()`). When you add a new column to the Google Sheet, add a matching entry there so the description renders correctly.

## Citing

```
P. vivax Policy Repository. Updated [Month YYYY]. Available at: https://example.org/vivax-policy-repository.
```

## Licence

- **Code:** MIT
- **Data:** CC-BY-4.0
