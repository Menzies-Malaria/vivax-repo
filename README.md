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
├── scripts/
│   ├── build_profiles.R       # Regenerates profiles/*.qmd from current data
│   ├── fetch-sheet-data.sh    # Downloads sheet CSVs at build time (gitignored data/)
│   └── package-gated-site.sh  # Post-render: moves site behind login portal
├── login_portal/                # Static login page (copied to _site/ root on deploy)
└── .github/workflows/         # CI: fetches sheet → renders → publishes
```

## Quickstart (local)

Production builds prefer the two live Google Sheet URLs. When those variables
are not set, local builds fall back to `data/characteristic_data.csv` and
`data/case_management.csv`.

```bash
# 1. Install R deps (one-time)
Rscript -e 'install.packages(c("readr", "dplyr", "stringr", "jsonlite", "crosstalk", "DT", "htmltools", "knitr", "rmarkdown"), repos = "https://cloud.r-project.org")'

# 2. Install Quarto and Python 3.10/3.11 (one-time)
#    https://quarto.org/docs/get-started/
#    https://www.python.org/downloads/

# 3a. Local CSV workflow: place the two CSV files under data/
#     data/characteristic_data.csv
#     data/case_management.csv

# 3b. Optional live-Sheet workflow: export URLs and fetch CSVs
export CHAR_DATA_URL="https://docs.google.com/spreadsheets/d/<ID>/pub?gid=<GID_1>&single=true&output=csv"
export CASE_DATA_URL="https://docs.google.com/spreadsheets/d/<ID>/pub?gid=<GID_2>&single=true&output=csv"
bash scripts/fetch-sheet-data.sh

# 4. Build the country profile pages from the live sheet
Rscript scripts/build_profiles.R

# 5. Preview the site
quarto preview
```

On the first preview after the approved translation dictionary changes, the
pre-render hook creates an ignored `.venv`, installs the pinned Argos release,
and downloads the English-to-Spanish, English-to-French, and
English-to-Portuguese models into `.translation-cache/`. Later
previews reuse the cached translation and work offline. The site will open at
<http://localhost:7676>. Local preview is **ungated** for authoring convenience.

## Local translation prototype

The prototype extracts eligible static text from the seven rendered top-level
website pages and records it in `translations/en.json`. It excludes country
profiles, tables, plots, R/HTML-widget output, code, hyperlinks, URLs, email
addresses, and the embedded contribution form. Before translation, the builder
validates this generated local allowlist and reports its exact string and
character count.

```text
rendered top-level HTML
        -> scripts/extract_static_translations.py
        -> translations/en.json
        -> scripts/prepare_translations.R
        -> local Argos English-to-Spanish/French/Portuguese models
        -> assets/translations/es.json, fr.json, pt.json
        -> English / Español / Français / Português selector in the Quarto navigation
```

Each generated language dictionary is marked `machine draft - human review
required`. They are cached and committed separately from the ignored Python
environment and model files. To regenerate after changing eligible site text:

```bash
Rscript scripts/prepare_translations.R
```

No cloud translation API, registration, subscription, or API key is used.

### Previewing the gated site locally

To test the login portal layout locally:

```bash
quarto render
RESTRICTED_PORTAL_USER=youruser RESTRICTED_PORTAL_PASS=yourpass bash scripts/package-gated-site.sh
python3 -m http.server 8080 --directory _site
```

Open <http://localhost:8080>, log in with the credentials you set, and confirm you reach the site. The address bar will show `/vivax-repo/` once inside (URL masking).

## How the Google Sheet is wired up

The site reads two tabs from a shared Google Sheet at build time via publish-to-web CSV URLs.

1. Create a Google Sheet with two tabs named exactly `Characteristic Data` and `Case Mgmt Data Points`.
2. **File → Share → Publish to web.** Pick each tab in turn, choose **CSV** as the format, and tick **Automatically republish when changes are made**. Copy the resulting URL for each tab.
3. Set two environment variables before building:

   ```bash
   export CHAR_DATA_URL="https://docs.google.com/spreadsheets/d/<ID>/pub?gid=<GID_1>&single=true&output=csv"
   export CASE_DATA_URL="https://docs.google.com/spreadsheets/d/<ID>/pub?gid=<GID_2>&single=true&output=csv"
   bash scripts/fetch-sheet-data.sh
   Rscript scripts/build_profiles.R
   quarto render
   ```

   On GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Name them `CHAR_DATA_URL` and `CASE_DATA_URL`. The workflow in `.github/workflows/publish.yml` picks them up automatically.

Edits to the Google Sheet land on the live site the next time the workflow runs (weekly Monday at 06:00 UTC, or whenever you manually trigger it under **Actions → Publish → Run workflow**).

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

## Partner login portal

The deployed site is gated behind a static login portal. Visitors land on a login page; correct credentials redirect them to the full site via obfuscated URL paths derived from SHA1 hashes of the username and password.

This is **security through obscurity** — suitable for partner gating, not for critically sensitive information. Anyone who knows or guesses the hashed URL can access pages directly. Use a **private repository** so source files are not publicly accessible.

### Required GitHub secrets

In **Settings → Secrets and variables → Actions**, add:

| Secret | Purpose |
|--------|---------|
| `RESTRICTED_PORTAL_USER` | Partner username |
| `RESTRICTED_PORTAL_PASS` | Partner password |
| `CHAR_DATA_URL` | Google Sheet CSV URL (Characteristic Data tab) |
| `CASE_DATA_URL` | Google Sheet CSV URL (Case Mgmt Data Points tab) |

CI computes SHA1 hashes from the portal credentials and packages the rendered site under `a{userHash}/a{passHash}/`. Credentials are never stored in the repository.

## Deploying to GitHub Pages

1. Push this repo to GitHub.
2. **Settings → Pages → Source:** "GitHub Actions".
3. Add `CHAR_DATA_URL`, `CASE_DATA_URL`, `RESTRICTED_PORTAL_USER`, and `RESTRICTED_PORTAL_PASS` repo secrets (see above).
4. Push to `main` or trigger **Actions → Publish**.

The site will be served at `https://menzies-malaria.github.io/vivax-repo/`. The root URL shows the login portal; authenticated users reach the full repository content after logging in.

## Updating the data dictionary

`data.qmd` has a column dictionary in `R/data_helpers.R` (`column_dictionary_notes()`). When you add a new column to the Google Sheet, add a matching entry there so the description renders correctly.

## Citing

```
P. vivax Policy Repository. Updated [Month YYYY]. Available at: https://menzies-malaria.github.io/vivax-repo/.
```

## Licence

- **Code:** MIT
- **Data:** CC-BY-4.0
