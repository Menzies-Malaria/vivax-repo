# Google Form template — copy-paste wording

Use this document when setting up the contribute form for the *P. vivax* Policy Repository.

**Automated setup:** copy [`scripts/google-form-builder.gs`](../scripts/google-form-builder.gs) and [`scripts/FormTemplate.html`](../scripts/FormTemplate.html) into a Google Apps Script project and run **`buildVivaxPolicyForm()`** — see [google-form-quickstart.md](google-form-quickstart.md).

**Manual setup:** create a **new Google Form**, then add each block below as a **Section** (page break) in the form editor.

The form writes to the **`Submissions`** tab of your Google Sheet. The repository team reviews submissions and manually updates the canonical tabs (`Characteristic Data`, `Case Mgmt Data Points`). See [README](../README.md) and [contribute.qmd](../contribute.qmd) for wiring and embedding.

---

## Automated build with Google Apps Script

See **[google-form-quickstart.md](google-form-quickstart.md)** for the full walkthrough. Summary:

1. [script.google.com](https://script.google.com) → **New project**
2. Paste [`scripts/google-form-builder.gs`](../scripts/google-form-builder.gs) into **Code.gs**
3. Add HTML file **`FormTemplate`**, paste [`scripts/FormTemplate.html`](../scripts/FormTemplate.html)
4. Run **`buildVivaxPolicyForm()`** — no Drive upload, no config fields to set
5. Open the form URL from **Execution log** → link responses to your Sheet → rename tab **`Submissions`**

Optional: run **`debugParseMarkdown()`** first to verify 7 sections / 42 questions without creating a form.

Set `SCRIPT_CONFIG.uniqueTitleOnRerun` to `false` if you prefer a fixed form title on reruns (each run still creates a new form).

**Container-bound script (opened from a Form):** The script creates a **new** form each run — use the URL in the execution log, not the empty form you started from.

**Q37 file upload:** Google Apps Script cannot add file-upload questions programmatically. The script creates a paragraph field for a document link instead. Add a real **File upload** question manually in the Form editor if needed.

---

## Form title

**P. vivax Policy Repository — submit a country update**

## Form description

Use this form to suggest corrections or updates to your country's *P. vivax* case management policy record in the Policy Repository.

You only need to complete **Section 1** for a useful submission. Additional sections are optional.

Submissions are reviewed by the repository team within five working days. Approved updates appear on the public site after the next site rebuild (weekly, or sooner for major changes).

If you need to share a restricted document or have a long attachment, email **vivax-repository@example.org** with subject line: `Policy update — [Country name]`.

---

## Section 1 — Your submission (required)

**Section title:** Your submission  
**Section description:** Please complete all questions in this section.

### Q1. Country

- **Type:** Dropdown
- **Required:** Yes

**Help text:**

> Select the country you are updating. If your country is not listed, choose "Other" and name it in the next question.

**Dropdown options** (one per line):

```
Afghanistan
Algeria
Angola
Argentina
Bangladesh
Belize
Benin
Bhutan
Bolivia
Botswana
Brazil
Burkina Faso
Burundi
Cabo Verde
Cambodia
Cameroon
Central African Republic
Chad
China
Colombia
Comoros
Congo
Costa Rica
Cote D'Ivoire
Democratic Republic of the Congo
Djibouti
Dominican Republic
Ecuador
El Salvador
Equatorial Guinea
Eritrea
Eswatini
Ethiopia
French Guiana
Gabon
Gambia
Ghana
Guatemala
Guinea
Guinea-Bissau
Guyana
Haiti
Honduras
India
Indonesia
Iran
Kenya
Lao PDR
Liberia
Madagascar
Malawi
Malaysia
Mali
Mauritania
Mayotte
Mexico
Mozambique
Myanmar
Namibia
Nepal
Nicaragua
Niger
Nigeria
North Korea (DPRK)
Pakistan
Panama
Papua New Guinea
Paraguay
Peru
Philippines
Republic of Korea (ROK)
Rwanda
Sao Tome and Principe
Saudi Arabia
Senegal
Sierre Leone
Solomon Islands
Somalia
South Africa
South Sudan
Sri Lanka
Sudan
Suriname
Thailand
Timor Leste
Togo
Uganda
United Republic of Tanzania (Zamzibar)
Vanuatu
Venezuela
Vietnam
Yemen
Zambia
Zimbabwe
Other (not listed)
```

### Q2. If you chose "Other (not listed)", what is the country name?

- **Type:** Short answer
- **Required:** No

**Help text:**

> Leave blank if you selected a country from the list above.

### Q3. What has changed, or what would you like to correct?

- **Type:** Paragraph
- **Required:** Yes

**Help text:**

> Describe the update in your own words. Examples: "2024 national malaria treatment guidelines adopted single-dose tafenoquine"; "G6PD testing now implemented at district hospitals"; "Case numbers for 2023 revised to X."

### Q4. Your full name

- **Type:** Short answer
- **Required:** Yes

### Q5. Your role and organisation

- **Type:** Short answer
- **Required:** Yes

**Help text:**

> Example: "National Malaria Control Programme focal point, Ministry of Health"

### Q6. Email address for follow-up (optional)

- **Type:** Short answer
- **Required:** No

**Help text:**

> We may contact you to clarify your submission. Leave blank if you prefer not to be contacted.

### Q7. Source of this information

- **Type:** Multiple choice
- **Required:** Yes

**Options:**

```
National treatment guideline (published)
Draft or in-review national guideline
NMCP programme records / internal policy
WHO or partner meeting / correspondence
Published study or grey literature
Other
```

### Q8. If you selected "Other", please describe the source

- **Type:** Short answer
- **Required:** No

---

## Section 2 — Treatment policy (optional)

**Section title:** Treatment policy  
**Section description:** Complete this section only if you are updating treatment recommendations. Skip if not relevant.

### Q9. First-line treatment for uncomplicated *P. vivax* malaria

- **Type:** Short answer
- **Required:** No

**Help text:**

> Example: CQ, AL, DHA-PPQ, chloroquine + primaquine, etc.

### Q10. Second-line treatment

- **Type:** Short answer
- **Required:** No

### Q11. Rationale for ACT use (if ACT is first- or second-line)

- **Type:** Paragraph
- **Required:** No

### Q12. May the information in this section be shown on the public website?

- **Type:** Multiple choice
- **Required:** Yes (if this section is completed)

**Options:**

```
Yes — public (visible on the public repository website)
No — restricted (visible only to malaria programmes, partners, and researchers)
```

---

## Section 3 — G6PD testing (optional)

**Section title:** G6PD testing  
**Section description:** Complete this section only if you are updating G6PD testing policy or implementation.

### Q13. Is G6PD testing included in current national guidelines?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes
No
Not specified in guidelines
Not sure
```

### Q14. Is G6PD testing implemented in practice?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes — fully implemented
Partially implemented
No — not implemented
Pilot only
Not sure
```

### Q15. Type of G6PD test used (if any)

- **Type:** Short answer
- **Required:** No

**Help text:**

> Example: qualitative RDT, quantitative spectrophotometry, SNP/PCR, etc.

### Q16. Year G6PD testing implementation began (if known)

- **Type:** Short answer
- **Required:** No

### Q17. Health system level where G6PD testing is performed

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Example: referral hospitals only; district hospitals and above; community level.

### Q18. May the information in this section be shown on the public website?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes — public
No — restricted
```

---

## Section 4 — Primaquine and radical cure (optional)

**Section title:** Primaquine / radical cure regimens  
**Section description:** Complete if you are updating primaquine (PQ), tafenoquine (TQ), or other radical cure recommendations — especially by G6PD status.

### Q19. Overall policy on primaquine (PQ) for *P. vivax* radical cure

- **Type:** Paragraph
- **Required:** No

### Q20. PQ regimen when G6PD status is normal

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Include dose, duration, and total dose if known. Example: "PQ 0.25 mg/kg/day for 14 days"

### Q21. PQ regimen when G6PD deficient (mild/moderate)

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Example: "PQ 0.75 mg/kg weekly for 8 weeks" or "No PQ"

### Q22. PQ regimen when G6PD severely deficient

- **Type:** Paragraph
- **Required:** No

### Q23. Policy when G6PD status is not known / testing not available

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Example: risk-benefit assessment, treat without PQ, refer for testing, etc.

### Q24. Additional safety recommendations (e.g. supervision, counselling)

- **Type:** Paragraph
- **Required:** No

### Q25. May the information in this section be shown on the public website?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes — public
No — restricted
```

---

## Section 5 — Implementation and follow-up (optional)

**Section title:** Implementation and follow-up  
**Section description:** Complete if you are updating whether policies are implemented in practice, or how follow-up is conducted.

### Q26. Is radical cure treatment implemented as per national policy?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes — fully implemented
Partially implemented
No — not implemented
Not sure
```

### Q27. Year treatment implementation began (if known)

- **Type:** Short answer
- **Required:** No

### Q28. Type of treatment follow-up (by whom, how often, where)

- **Type:** Paragraph
- **Required:** No

### Q29. Is treatment follow-up implemented?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes
Partially
No
Not specified
```

### Q30. May the information in this section be shown on the public website?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes — public
No — restricted
```

---

## Section 6 — Guidelines, case data, and plans (optional)

**Section title:** Guidelines, case data, and forward plans  
**Section description:** Complete if you are updating guideline dates, links, case numbers, or planned policy changes.

### Q31. Year of last formal policy / guideline update

- **Type:** Short answer
- **Required:** No

**Help text:**

> Example: 2024

### Q32. Link to national malaria treatment guidelines (URL)

- **Type:** Short answer
- **Required:** No

### Q33. Link to National Strategic Plan (URL)

- **Type:** Short answer
- **Required:** No

### Q34. Is a policy update planned?

- **Type:** Short answer
- **Required:** No

**Help text:**

> Example: "Yes, 2026" or "Under review, date unknown"

### Q35. Treatments or policy changes under active consideration

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Example: single-dose tafenoquine, low-dose 7-day primaquine, expanded G6PD testing.

### Q36. Reported *P. vivax* case numbers (if updating burden data)

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Provide any years you know. Example: "2023: 12; 2022: 33" or "P. vivax share of malaria cases in 2023: 80%"

### Q37. Upload a guideline or policy document (optional)

- **Type:** File upload
- **Required:** No

**Help text:**

> PDF preferred. Large files may be easier to send by email.

### Q38. May the information in this section be shown on the public website?

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Yes — public
No — restricted
```

---

## Section 7 — Programme context and final notes (optional)

**Section title:** Programme context and anything else  
**Section description:** Optional background that helps us place your update in context.

### Q39. National malaria programme phase

- **Type:** Multiple choice
- **Required:** No

**Options:**

```
Burden reduction
Pre-elimination
Elimination
Eliminated
Not sure
```

### Q40. Named programme contact (if updating contact information)

- **Type:** Short answer
- **Required:** No

**Help text:**

> Example: "Dr [Name], National Malaria Control Programme"

### Q41. Any other notes for the repository team

- **Type:** Paragraph
- **Required:** No

**Help text:**

> Include anything we should know when reviewing this submission — conflicts between published guidelines and practice, subnational variation, translation issues, etc.

### Q42. I confirm that the information I have provided is accurate to the best of my knowledge

- **Type:** Multiple choice
- **Required:** Yes

**Options:**

```
Yes
```

---

## After you build the form

1. **Responses → Link to Sheets** — connect to your repository Google Sheet.
2. Rename the responses tab **`Submissions`**.
3. **Settings** — consider turning on "Collect email addresses" if you want automatic respondent email capture (in addition to Q6).
4. **Send → Embed (`<>`)** — copy the iframe `src` URL into `contribute.qmd`, replacing `REPLACE_WITH_YOUR_FORM_ID`.

---

## Reconciling submissions into canonical tabs

When reviewing `Submissions`, map answers roughly as follows:

| Form questions | Canonical sheet |
|---|---|
| Q9–Q11, Q39–Q40 | `Characteristic Data` |
| Q13–Q17, Q26–Q30 | Both tabs (G6PD / implementation) |
| Q19–Q24 | `Case Mgmt Data Points` (and G6PD sub-rows as `Country - G6PD Normal`, etc.) |
| Q31–Q35, Q37 | `Case Mgmt Data Points` |
| Q36 | `Characteristic Data` (case number columns) |
| Answers marked **restricted** | `Restricted` tab — not the public canonical tabs |
