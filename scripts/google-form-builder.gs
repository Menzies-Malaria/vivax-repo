/**
 * Build the P. vivax Policy Repository Google Form from FormTemplate.html
 *
 * Setup:
 * 1. https://script.google.com → New project
 * 2. Paste scripts/google-form-builder.gs into Code.gs
 * 3. Add HTML file named FormTemplate — paste scripts/FormTemplate.html
 * 4. Run buildVivaxPolicyForm()
 *
 * No Google Drive upload required. The markdown lives in FormTemplate.html.
 */

var SCRIPT_CONFIG = {
  /** HTML file name (no extension) that holds the markdown template. */
  htmlTemplateFile: "FormTemplate",
  /** If true, append a timestamp to the form title so reruns do not overwrite. */
  uniqueTitleOnRerun: true,
};

/**
 * Creates the form from FormTemplate.html in this Apps Script project.
 */
function buildVivaxPolicyForm() {
  var markdown = loadMarkdownFromHtmlFile_();
  return buildVivaxPolicyFormFromMarkdown(markdown);
}

/** @deprecated Use buildVivaxPolicyForm() */
function buildVivaxPolicyFormFromHtmlFile() {
  return buildVivaxPolicyForm();
}

/**
 * @return {string}
 */
function loadMarkdownFromHtmlFile_() {
  var name = SCRIPT_CONFIG.htmlTemplateFile || "FormTemplate";
  var markdown = HtmlService.createHtmlOutputFromFile(name).getContent();
  if (
    markdown.indexOf("PASTE docs/google-form-template.md HERE") >= 0 ||
    markdown.indexOf("Replace this entire file") >= 0
  ) {
    throw new Error(
      "Paste docs/google-form-template.md into the " +
        name +
        ".html file first (File → New → HTML file, name it " +
        name +
        ")."
    );
  }
  return markdown;
}

/**
 * @param {string} markdown
 * @return {GoogleAppsScript.Forms.Form}
 */
function buildVivaxPolicyFormFromMarkdown(markdown) {
  var spec = parseMarkdownTemplate_(markdown);
  return createFormFromSpec_(spec);
}

// ---------------------------------------------------------------------------
// Markdown parser
// ---------------------------------------------------------------------------

/**
 * @param {string} markdown
 * @return {{
 *   title: string,
 *   description: string,
 *   sections: Array<{
 *     title: string,
 *     description: string,
 *     questions: Array<{
 *       title: string,
 *       type: string,
 *       required: boolean,
 *       helpText: string,
 *       choices: string[]
 *     }>
 *   }>
 * }}
 */
function parseMarkdownTemplate_(markdown) {
  markdown = markdown.replace(/\r\n/g, "\n");
  var lines = markdown.split("\n");

  var title = "";
  var description = "";
  var sections = [];
  var currentSection = null;
  var currentQuestion = null;
  var mode = ""; // '', 'form-description', 'section-description', 'help', 'options'
  var optionsLabel = "";

  function flushQuestion() {
    if (currentSection && currentQuestion && currentQuestion.title) {
      currentSection.questions.push(currentQuestion);
    }
    currentQuestion = null;
    mode = "";
    optionsLabel = "";
  }

  function flushSection() {
    flushQuestion();
    if (currentSection && currentSection.title) {
      sections.push(currentSection);
    }
    currentSection = null;
    mode = "";
  }

  function startQuestion(rawTitle) {
    flushQuestion();
    currentQuestion = {
      title: stripMarkdown_(rawTitle),
      type: "Short answer",
      required: false,
      helpText: "",
      choices: [],
    };
    mode = "";
    optionsLabel = "";
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var trimmed = line.trim();

    // Stop before postamble sections
    if (/^## After you build the form/.test(trimmed)) {
      break;
    }
    if (/^## Reconciling submissions/.test(trimmed)) {
      break;
    }

    // Form title
    if (trimmed === "## Form title") {
      flushSection();
      for (var t = i + 1; t < lines.length; t++) {
        var tline = lines[t].trim();
        if (!tline || tline === "---") continue;
        if (tline.indexOf("##") === 0) break;
        var bold = tline.match(/^\*\*(.+)\*\*$/);
        if (bold) {
          title = stripMarkdown_(bold[1]);
          break;
        }
      }
      continue;
    }

    // Form description
    if (trimmed === "## Form description") {
      flushSection();
      mode = "form-description";
      description = "";
      continue;
    }

    // Section header
    var sectionMatch = trimmed.match(/^## Section \d+/);
    if (sectionMatch) {
      flushSection();
      currentSection = { title: "", description: "", questions: [] };
      mode = "";
      continue;
    }

    // Section title / description metadata
    if (currentSection && !currentQuestion) {
      var secTitle = trimmed.match(/^\*\*Section title:\*\*\s*(.+)$/);
      if (secTitle) {
        currentSection.title = stripMarkdown_(secTitle[1].replace(/\s{2,}$/, ""));
        continue;
      }
      var secDesc = trimmed.match(/^\*\*Section description:\*\*\s*(.+)$/);
      if (secDesc) {
        currentSection.description = stripMarkdown_(secDesc[1].replace(/\s{2,}$/, ""));
        mode = "";
        continue;
      }
    }

    // Question header
    var qMatch = trimmed.match(/^### Q\d+\.\s+(.+)$/);
    if (qMatch) {
      if (!currentSection) {
        currentSection = { title: "Questions", description: "", questions: [] };
      }
      startQuestion(qMatch[1]);
      continue;
    }

    // Question metadata bullets
    if (currentQuestion) {
      var typeMatch = trimmed.match(/^- \*\*Type:\*\*\s*(.+)$/);
      if (typeMatch) {
        currentQuestion.type = typeMatch[1].trim();
        continue;
      }
      var reqMatch = trimmed.match(/^- \*\*Required:\*\*\s*(.+)$/);
      if (reqMatch) {
        currentQuestion.required = /^yes/i.test(reqMatch[1].trim());
        continue;
      }
    }

    // Help text block
    if (trimmed === "**Help text:**") {
      mode = "help";
      if (currentQuestion) currentQuestion.helpText = "";
      continue;
    }

    // Options / dropdown label
    if (
      currentQuestion &&
      (/^\*\*Options:\*\*/.test(trimmed) ||
        /^\*\*Dropdown options\*\*/.test(trimmed))
    ) {
      mode = "options-pending";
      optionsLabel = trimmed;
      continue;
    }

    // Fenced code block for options
    if (mode === "options-pending" && trimmed === "```") {
      mode = "options";
      continue;
    }
    if (mode === "options") {
      if (trimmed === "```") {
        mode = "";
        optionsLabel = "";
        continue;
      }
      if (currentQuestion && trimmed) {
        currentQuestion.choices.push(trimmed);
      }
      continue;
    }

    if (mode === "help") {
      if (trimmed.indexOf(">") === 0) {
        var helpLine = stripMarkdown_(trimmed.replace(/^>\s?/, ""));
        if (currentQuestion) {
          currentQuestion.helpText += (currentQuestion.helpText ? " " : "") + helpLine;
        }
        continue;
      }
      if (trimmed === "" || trimmed.indexOf("**") === 0 || trimmed.indexOf("- **") === 0) {
        mode = "";
      } else {
        continue;
      }
    }

    // Form description paragraphs
    if (mode === "form-description") {
      if (trimmed === "---" || trimmed.indexOf("## Section") === 0) {
        mode = "";
        continue;
      }
      if (trimmed) {
        description += (description ? "\n\n" : "") + stripMarkdown_(trimmed);
      }
      continue;
    }
  }

  flushSection();

  if (!title) {
    throw new Error("Could not parse form title from markdown.");
  }
  if (!sections.length) {
    throw new Error("Could not parse any form sections from markdown.");
  }

  return { title: title, description: description, sections: sections };
}

/**
 * @param {string} text
 * @return {string}
 */
function stripMarkdown_(text) {
  return text
    .replace(/\*\*(.+?)\*\*/g, "$1")
    .replace(/\*(.+?)\*/g, "$1")
    .replace(/`(.+?)`/g, "$1")
    .replace(/\s{2,}$/, "")
    .trim();
}

// ---------------------------------------------------------------------------
// Form builder
// ---------------------------------------------------------------------------

/**
 * @param {{
 *   title: string,
 *   description: string,
 *   sections: Array
 * }} spec
 * @return {GoogleAppsScript.Forms.Form}
 */
function createFormFromSpec_(spec) {
  var formTitle = spec.title;
  if (SCRIPT_CONFIG.uniqueTitleOnRerun) {
    formTitle += " (" + Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd HH:mm") + ")";
  }

  var form = FormApp.create(formTitle);
  form.setDescription(spec.description);
  form.setCollectEmail(false);
  form.setAllowResponseEdits(false);
  form.setPublishingSummary(false);

  spec.sections.forEach(function (section, sectionIndex) {
    if (sectionIndex > 0) {
      var page = form.addPageBreakItem();
      page.setTitle(section.title || "Continued");
      if (section.description) {
        page.setHelpText(section.description);
      }
    }

    section.questions.forEach(function (question) {
      addQuestionToForm_(form, question);
    });
  });

  Logger.log("Created form: %s", form.getPublishedUrl());
  Logger.log("Edit URL: %s", form.getEditUrl());
  return form;
}

/**
 * @param {GoogleAppsScript.Forms.Form} form
 * @param {{
 *   title: string,
 *   type: string,
 *   required: boolean,
 *   helpText: string,
 *   choices: string[]
 * }} question
 */
function addQuestionToForm_(form, question) {
  var typeKey = question.type.toLowerCase();
  var item;

  if (typeKey.indexOf("dropdown") >= 0 || typeKey.indexOf("list") >= 0) {
    item = form.addListItem();
    item.setTitle(question.title);
    if (question.helpText) {
      item.setHelpText(question.helpText);
    }
    if (question.choices.length) {
      item.setChoices(
        question.choices.map(function (choice) {
          return item.createChoice(choice);
        })
      );
    }
    item.setRequired(question.required);
    return;
  }

  if (typeKey.indexOf("multiple choice") >= 0) {
    item = form.addMultipleChoiceItem();
    item.setTitle(question.title);
    if (question.helpText) {
      item.setHelpText(question.helpText);
    }
    if (question.choices.length) {
      item.setChoices(
        question.choices.map(function (choice) {
          return item.createChoice(choice);
        })
      );
    }
    item.setRequired(question.required);
    return;
  }

  if (typeKey.indexOf("paragraph") >= 0) {
    item = form.addParagraphTextItem();
  } else if (typeKey.indexOf("file upload") >= 0) {
    item = addFileUploadOrFallback_(form, question);
    return;
  } else {
    item = form.addTextItem();
  }

  item.setTitle(question.title);
  if (question.helpText) {
    item.setHelpText(question.helpText);
  }
  item.setRequired(question.required);
}

/**
 * Google Apps Script cannot create file-upload questions programmatically
 * (FormApp has no addFileUploadItem). Fall back to a URL / email instruction.
 *
 * @param {GoogleAppsScript.Forms.Form} form
 * @param {{
 *   title: string,
 *   required: boolean,
 *   helpText: string
 * }} question
 * @return {GoogleAppsScript.Forms.Item}
 */
function addFileUploadOrFallback_(form, question) {
  var help = question.helpText || "";
  var note =
    "File upload fields cannot be added via Apps Script. " +
    "Paste a link to your document below, or email it to vivax-repository@example.org " +
    "with subject line: Policy update — [Country name].";
  if (help) {
    help = help + "\n\n" + note;
  } else {
    help = note;
  }

  var item = form.addParagraphTextItem();
  item.setTitle(question.title + " (link or note — add file upload manually in Form editor if needed)");
  item.setHelpText(help);
  item.setRequired(false);
  return item;
}

// ---------------------------------------------------------------------------
// Optional: dry-run parser in the execution log (no form created)
// ---------------------------------------------------------------------------

function debugParseMarkdown() {
  debugParseMarkdown_(loadMarkdownFromHtmlFile_());
}

/** @deprecated Use debugParseMarkdown() */
function debugParseMarkdownFromHtmlFile() {
  debugParseMarkdown();
}

/**
 * @param {string} markdown
 */
function debugParseMarkdown_(markdown) {
  var spec = parseMarkdownTemplate_(markdown);
  Logger.log("Title: %s", spec.title);
  Logger.log("Description length: %s chars", spec.description.length);
  Logger.log("Sections: %s", spec.sections.length);
  spec.sections.forEach(function (section, i) {
    Logger.log(
      "  [%s] %s — %s questions",
      i + 1,
      section.title,
      section.questions.length
    );
  });
}
