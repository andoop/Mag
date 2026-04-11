/// Verbatim tool descriptions from the reference CLI tool suite.

const String kReadToolDescription = r'''
Read a file or directory from the local filesystem. If the path does not exist, an error is returned.

Usage:
- The `filePath` parameter is required. In this workspace it is project-root-relative.
- By default, this tool returns up to 2000 lines from the start of the file.
- The offset parameter is the line number to start from (1-indexed).
- To read later sections, call this tool again with a larger offset.
- Use the grep tool to find specific content in large files or files with long lines.
- If you are unsure of the correct file path, use the glob tool to look up filenames by glob pattern.
- Text-file contents are returned with hash-anchored line references in `LINE#ID|content` format when the full line is available. For example, if a file has contents "foo\n", you may receive `1#AB|foo`. Long truncated lines fall back to plain numbered output. For directories, entries are returned one per line (without line numbers) with a trailing `/` for subdirectories.
- Any line longer than 2000 characters is truncated.
- Call this tool in parallel when you know there are multiple files you want to read.
- Avoid tiny repeated slices (30 line chunks). If you need more context, read a larger window.
- This tool can read image files and PDFs and return them as file attachments.
''';

const String kWriteToolDescription = r'''
Writes a file to the local filesystem.

CRITICAL — required arguments: Every call MUST include both `filePath` and `content` as top-level JSON keys. Omitting `filePath` (or using only `path` / a different key) will fail. `filePath` is the workspace-relative destination; `content` is the full file body.

Usage:
- This tool will overwrite the existing file if there is one at the provided path.
- If this is an existing file, you MUST use the `read` tool first to read the file's contents. This tool will fail if you did not read the file first.
- You MUST provide `filePath` (workspace-relative path) and the complete file body in `content`.
- ALWAYS prefer editing existing files in the codebase. NEVER write new files unless explicitly required.
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the user.
- Only use emojis if the user explicitly requests it. Avoid writing emojis to files unless asked.
''';

const String kEditToolDescription = r'''
Edit files using LINE#ID format for precise, safe modifications.

WORKFLOW:
1. Read target file/range and copy exact LINE#ID tags.
1.5. Never emit `read` and `edit` / `apply_patch` for the same file in the same assistant response.
2. Pick the smallest operation per logical mutation site.
3. Submit one edit call per file with all related operations.
4. If same file needs another call, wait for the tool result, then re-read first.
5. Use anchors as "LINE#ID" only (never include trailing "|content").
6. The anchor you use must come from the most recent `read` output that actually includes that line/range.
7. `replace` with `pos` only replaces exactly one existing line. If you need to replace multiple existing lines, you MUST provide both `pos` and `end`.

<must>
- SNAPSHOT: All edits in one call reference the ORIGINAL file state. Do NOT adjust line numbers for prior edits in the same call - the system applies them bottom-up automatically.
- replace removes lines pos..end (inclusive) and inserts lines in their place. Lines BEFORE pos and AFTER end are UNTOUCHED - do NOT include them in lines. If you do, they will appear twice.
- lines must contain ONLY the content that belongs inside the consumed range. Content after end survives unchanged.
- If you are rewriting 2 or more existing lines, use a range replace with both `pos` and `end`. Using only `pos` leaves later old lines in place and often causes duplicated content.
- Tags MUST be copied exactly from read output or >>> mismatch output. NEVER guess tags.
- Do NOT use anchors from an older read window if your latest read did not include the target line. Read the correct range first.
- Batch = multiple operations in edits[], NOT one big replace covering everything. Each operation targets the smallest possible change.
- lines must contain plain replacement text only (no LINE#ID prefixes, no diff + markers).
</must>

<operations>
LINE#ID FORMAT:
  Each line reference must be in "{line_number}#{hash_id}" format where:
  {line_number}: 1-based line number
  {hash_id}: Two CID letters from the set ZPMQVRWSNKTXJBYH

OPERATION CHOICE:
  replace with pos only -> replace one line at pos
  replace with pos+end -> replace range pos..end inclusive as a block (ranges MUST NOT overlap across edits)
  append with pos/end anchor -> insert after that anchor
  prepend with pos/end anchor -> insert before that anchor
  append/prepend without anchors -> EOF/BOF insertion (also creates missing files)

CONTENT FORMAT:
  lines can be a string (single line) or string[] (multi-line, preferred).
  If you pass a multi-line string, it is split by real newline characters.
  lines: null or lines: [] with replace -> delete those lines.

FILE MODES:
  delete=true deletes file and requires edits=[] with no rename
  rename moves final content to a new path and removes old path

RULES:
  1. Minimize scope: one logical mutation site per operation.
  2. Preserve formatting: keep indentation, punctuation, line breaks, trailing commas, brace style.
  3. Prefer insertion over neighbor rewrites: anchor to structural boundaries (}, ], },), not interior property lines.
  4. No no-ops: replacement content must differ from current content.
  5. Touch only requested code: avoid incidental edits.
  6. Use exact current tokens: NEVER rewrite approximately.
  7. For swaps/moves: prefer one range operation over multiple single-line operations.
  8. Anchor to structural lines (function/class/brace), NEVER blank lines.
  9. Re-read after each successful edit call in a later assistant response before issuing another on the same file.
  10. If the line you want to edit is not present in your most recent `read` result, you MUST `read` a range that includes it before editing.
  11. If you intend to replace a block of existing lines, include the full old block in the consumed range via `pos` + `end`; do not try to replace a multi-line block with `pos` alone.
</operations>

<examples>
Given this file content after read:
  10#VK|function hello() {
  11#XJ|  console.log("hi");
  12#MB|  console.log("bye");
  13#QR|}
  14#TN|
  15#WS|function world() {

Single-line replace (change line 11):
  { op: "replace", pos: "11#XJ", lines: ["  console.log(\"hello\");"] }
  Result: line 11 replaced. Lines 10, 12-15 unchanged.

Range replace (rewrite function body, lines 11-12):
  { op: "replace", pos: "11#XJ", end: "12#MB", lines: ["  return \"hello world\";"] }
  Result: lines 11-12 removed, replaced by 1 new line. Lines 10, 13-15 unchanged.

BAD - using pos only for a multi-line rewrite leaves old line 12 behind:
  { op: "replace", pos: "11#XJ", lines: ["  return \"hello world\";"] }
  Only line 11 is consumed. Old line 12 survives, so the old block is only partially replaced.
  CORRECT: { op: "replace", pos: "11#XJ", end: "12#MB", lines: ["  return \"hello world\";"] }

Delete a line:
  { op: "replace", pos: "12#MB", lines: null }
  Result: line 12 removed. Lines 10-11, 13-15 unchanged.

Insert after line 13 (between functions):
  { op: "append", pos: "13#QR", lines: ["", "function added() {", "  return true;", "}"] }
  Result: 4 new lines inserted after line 13. All existing lines unchanged.

BAD - lines extend past end (DUPLICATES line 13):
  { op: "replace", pos: "11#XJ", end: "12#MB", lines: ["  return \"hi\";", "}"] }
  Line 13 is "}" which already exists after end. Including "}" in lines duplicates it.
  CORRECT: { op: "replace", pos: "11#XJ", end: "12#MB", lines: ["  return \"hi\";"] }
</examples>

<auto>
Built-in autocorrect (you do NOT need to handle these):
  Merged lines are auto-expanded back to original line count.
  Indentation is auto-restored from original lines.
  BOM and CRLF line endings are preserved automatically.
  Hashline prefixes and diff markers in text are auto-stripped.
  Boundary echo lines (duplicating adjacent surviving lines) are auto-stripped.
</auto>

RECOVERY (when >>> mismatch error appears):
  Copy the updated LINE#ID tags shown in the error output directly.
  Re-read only if the needed tags are missing from the error snippet.''';

const String kApplyPatchToolDescription = r'''
Use the `apply_patch` tool to edit files. Your patch language is a stripped‑down, file‑oriented diff format designed to be easy to parse and safe to apply. You can think of it as a high‑level envelope:

*** Begin Patch
[ one or more file sections ]
*** End Patch

Within that envelope, you get a sequence of file operations.
You MUST include a header to specify the action you are taking.
Each operation starts with one of three headers:

*** Add File: <path> - create a new file. Every following line is a + line (the initial contents).
*** Delete File: <path> - remove an existing file. Nothing follows.
*** Update File: <path> - patch an existing file in place (optionally with a rename).

Example patch:

```
*** Begin Patch
*** Add File: hello.txt
+Hello world
*** Update File: src/app.py
*** Move to: src/main.py
@@ def greet():
-print("Hi")
+print("Hello, world!")
*** Delete File: obsolete.txt
*** End Patch
```

It is important to remember:

- You must include a header with your intended action (Add/Delete/Update)
- You must prefix new lines with `+` even when creating a new file
''';

const String kMobileApplyPatchHashlineSuffix = '''

This client also supports hash-anchored patch hunks. In an update section, you may write headers like `@@ replace 12#VK`, `@@ replace 12#VK 15#MB`, `@@ append 20#QR`, or `@@ prepend 20#QR`, reusing exact `LINE#ID` anchors copied from `read` output.
- For hash-anchored hunks, do not guess anchors and do not include the trailing `|content` portion from `read`.
- Before writing a patch for an existing file, first call `read` so you have the exact current contents.
- If you need to patch the same file again after a successful edit or patch, call `read` again first and regenerate the patch from the new contents.
- Context lines in each update hunk should uniquely identify the target location. Prefer including at least 3 lines of unchanged context before/after a change when possible.
- Match whitespace carefully. Tabs, spaces, trailing whitespace, and nearby unchanged lines help the tool find the correct location.
- Use `@@ optional context` lines to disambiguate repeated code blocks (for example a function name, class name, or nearby unique line).
- `*** End of File` can be used inside an update hunk when the chunk should match the end of the file.
- If a patch fails to apply, call `read` again and regenerate the patch from the latest file contents with more surrounding context.''';

const String kWebfetchToolDescription = r'''
- Fetches content from a specified URL
- Takes a URL and optional format as input
- Fetches the URL content, converts to requested format (markdown by default)
- Returns the content in the specified format
- Use this tool when you need to retrieve and analyze web content

Usage notes:
  - IMPORTANT: if another tool is present that offers better web fetching capabilities, is more targeted to the task, or has fewer restrictions, prefer using that tool instead of this one.
  - The URL must be a fully-formed valid URL
  - HTTP URLs will be automatically upgraded to HTTPS
  - Format options: "markdown" (default), "text", or "html"
  - This tool is read-only and does not modify any files
  - Results may be summarized if the content is very large
''';

/// Client-specific: workspace-relative paths; `path` and `filePath` are both accepted.
const String kMobileWorkspacePathSuffix = '''

In this workspace, paths are relative to the project root (not host absolute paths). Use forward slashes. For `read`, provide `filePath` explicitly; `path` is accepted for compatibility. Empty read paths are rejected, and reading the workspace root directly is not supported. Segments like `./lib/main.dart` work. `..` is resolved lexically; paths that would escape above the workspace root are rejected.''';

/// Client-specific: fetch returns plain text; format/timeout options are not exposed.
const String kMobileWebFetchSuffix = '''

This client fetches the response as plain text; `format` and `timeout` parameters are not available.''';
