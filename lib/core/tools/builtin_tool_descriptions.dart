/// Verbatim tool descriptions from the reference CLI tool suite.

const String kReadToolDescription = r'''
Read a file or directory from the local filesystem. If the path does not exist, an error is returned.

Usage:
- The filePath parameter should be an absolute path.
- By default, this tool returns up to 2000 lines from the start of the file.
- The offset parameter is the line number to start from (1-indexed).
- To read later sections, call this tool again with a larger offset.
- Use the grep tool to find specific content in large files or files with long lines.
- If you are unsure of the correct file path, use the glob tool to look up filenames by glob pattern.
- Contents are returned with each line prefixed by its line number as `<line>: <content>`. For example, if a file has contents "foo\n", you will receive "1: foo\n". For directories, entries are returned one per line (without line numbers) with a trailing `/` for subdirectories.
- Any line longer than 2000 characters is truncated.
- Call this tool in parallel when you know there are multiple files you want to read.
- Avoid tiny repeated slices (30 line chunks). If you need more context, read a larger window.
- This tool can read image files and PDFs and return them as file attachments.
''';

const String kWriteToolDescription = r'''
Writes a file to the local filesystem.

Usage:
- This tool will overwrite the existing file if there is one at the provided path.
- If this is an existing file, you MUST use the Read tool first to read the file's contents. This tool will fail if you did not read the file first.
- This tool also checks whether the file changed after your last read. If it did, read the file again before writing.
- ALWAYS prefer editing existing files in the codebase. NEVER write new files unless explicitly required.
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
- Only use emojis if the user explicitly requests it. Avoid writing emojis to files unless asked.
''';

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

- Before writing a patch for an existing file, first call `read` so you have the exact current contents.
- Context lines in each update hunk should uniquely identify the target location. Prefer including at least 3 lines of unchanged context before/after a change when possible.
- Match whitespace carefully. Tabs, spaces, trailing whitespace, and nearby unchanged lines help the tool find the correct location.
- Use `@@ optional context` lines to disambiguate repeated code blocks (for example a function name, class name, or nearby unique line).
- `*** End of File` can be used inside an update hunk when the chunk should match the end of the file.
- If a patch fails to apply, call `read` again and regenerate the patch from the latest file contents with more surrounding context.
- You must include a header with your intended action (Add/Delete/Update)
- You must prefix new lines with `+` even when creating a new file
''';

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

In this workspace, paths are relative to the project root (not host absolute paths). Use forward slashes. For `read`, use `path` or `filePath` (either is accepted). You may write the root as `.`, `./`, or an empty path where allowed; segments like `./lib/main.dart` work. `..` is resolved lexically; paths that would escape above the workspace root are rejected.''';

/// Client-specific: fetch returns plain text; format/timeout options are not exposed.
const String kMobileWebFetchSuffix = '''

This client fetches the response as plain text; `format` and `timeout` parameters are not available.''';
