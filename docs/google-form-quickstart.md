# Build the Google Form in 5 minutes (no manual questions)

You do **not** need to type or paste each question into Google Forms. One script run creates all **42 questions** in **7 sections** automatically.

## What you need

- A Google account
- Two files from this repo (already prepared):
  - [`scripts/google-form-builder.gs`](../scripts/google-form-builder.gs)
  - [`scripts/FormTemplate.html`](../scripts/FormTemplate.html) — markdown is **already inside**, nothing to paste

## Steps

1. Open **[script.google.com](https://script.google.com)** → **New project** (standalone project — you do not need an empty Form open).

2. **Code.gs** — delete the default code. Open `google-form-builder.gs` from this repo, copy all, paste into Code.gs.

3. **FormTemplate.html** — in Apps Script: **+** (Files) → **HTML** → name it **`FormTemplate`** (exact spelling). Open `FormTemplate.html` from this repo, copy all, paste into the new HTML file.

4. At the top of Code.gs, select **`buildVivaxPolicyForm`** → click **Run**.
   - First time: click **Review permissions** → choose your account → **Advanced** → **Go to … (unsafe)** → **Allow**.

5. **View → Execution log** — copy the **published form URL**. Open it.  
   - In the form: **Responses** → **Link to Sheets** → pick your repository sheet → rename the new tab **`Submissions`**.

Done. The form has every question, dropdown options, and section breaks.

## Optional checks

| Run this function | What it does |
|---|---|
| `debugParseMarkdown` | Confirms parsing (7 sections, 42 questions) without creating a form |
| `buildVivaxPolicyForm` | Creates the form |

## Troubleshooting

**`addFileUploadItem is not a function`**  
Update `google-form-builder.gs` to the latest version from this repo. Q37 becomes a “paste a link” field instead of file upload (Google does not allow file-upload fields via script). Add a real file-upload question manually in the Form editor if you want one.

**Opened Apps Script from an empty Form?**  
That still works, but the script creates a **new** form each run — use the URL in the execution log, not the empty form you started from.

**Want to change questions later?**  
Edit `docs/google-form-template.md`, then copy the updated file into `FormTemplate.html` in Apps Script (or re-copy from repo after we sync it), and run the build function again.

## After the form exists

1. Embed the form URL in [`contribute.qmd`](../contribute.qmd) (replace `REPLACE_WITH_YOUR_FORM_ID`).
2. Optionally add a manual **File upload** question for Q37 in the Form editor.
