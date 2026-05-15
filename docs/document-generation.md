# Document Generation

Mag can generate Office files directly inside a mobile workspace. The agent sends structured content to an on-device renderer; Mag writes the result to the workspace and returns it as an attachment.

<p align="center">
  <img src="assets/office-generation.jpg" alt="Office document generation in Mag" width="260" />
</p>

## Supported Formats

| Format | Tool | Use For |
|--------|------|---------|
| DOCX | `create_document` | Reports, proposals, memos, specs, and text-heavy documents. |
| XLSX | `create_spreadsheet` | Trackers, plans, tables, lightweight workbooks, and formula sheets. |
| PPTX | `create_presentation` | Slide decks, pitch decks, summaries, and structured presentations. |

## Behavior

- Output paths are workspace-relative.
- Existing files are not overwritten unless `overwrite: true` is passed.
- Each tool requests write permission.
- The generated file is attached to the conversation.
- The agent should provide structured content, not base64, raw XML, or binary Office payloads.

## DOCX: `create_document`

Supported blocks:

- `heading`
- `paragraph`
- `list`
- `table`

```json
{
  "filePath": "outputs/report.docx",
  "title": "Project Report",
  "blocks": [
    { "type": "heading", "level": 1, "text": "Summary" },
    { "type": "paragraph", "text": "Generated on device by Mag." },
    { "type": "table", "rows": [["Area", "Status"], ["Docs", "Ready"]] }
  ]
}
```

## XLSX: `create_spreadsheet`

Each workbook contains one or more sheets. Each sheet contains rows.

```json
{
  "filePath": "outputs/tasks.xlsx",
  "sheets": [
    {
      "name": "Tasks",
      "rows": [
        ["Task", "Owner", "Status"],
        ["Write docs", "Mag", "Done"]
      ]
    }
  ]
}
```

## PPTX: `create_presentation`

Supported slide layouts:

- `title`
- `bullets`
- `table`

```json
{
  "filePath": "outputs/demo.pptx",
  "title": "Mag Demo",
  "slides": [
    { "layout": "title", "title": "Mag", "subtitle": "Mobile AI coding agent" },
    { "layout": "bullets", "title": "Highlights", "bullets": ["Workspace", "Git", "Office generation"] }
  ]
}
```

## Boundaries

Generated documents currently use simple, predictable templates. This is intentional: the tools are designed to create useful mobile artifacts reliably, not to replace a full desktop Office editor.

---

# 文档生成

Mag 可以在移动端工作区内生成 Office 文件。Agent 提供结构化内容，Mag 在端上渲染并保存到工作区，然后把结果作为附件返回。

支持：

- DOCX：报告、方案、备忘录、需求说明。
- XLSX：计划表、跟踪表、轻量工作簿。
- PPTX：演示文稿、pitch deck、总结汇报。

生成文件默认不覆盖已有文件；需要覆盖时必须显式传入 `overwrite: true`。
