import '../models.dart';

/// System reminder: tool arguments must match each tool's schema and descriptions.
const String kToolCallingRulesPrompt = '''
<tool-calling-rules>
1. Tool arguments MUST be valid JSON. Required string fields must be real strings, never null. Do not omit required keys.
2. CRITICAL — read before edit: You MUST call `read` on a file before using `edit` or `apply_patch` on it. If the tool returns an error, `read` the file again before retrying. Never guess file contents.
3. CRITICAL — write is for NEW files only: The `write` tool creates new files. If a file already exists, you MUST use `edit` or `apply_patch` instead. Never use `write` to update existing files.
4. CRITICAL — re-read after each edit: If you just modified a file and need to modify it again, call `read` first. Do not reuse stale content from a previous read or edit.
5. When a tool returns an error, you MUST:
   a. Read the error message carefully — it contains the exact reason and recovery steps.
   b. Follow the recovery steps described in the error. Do NOT repeat the same call with the same arguments.
   c. If the error says to `read` first, then call `read` before retrying.
   d. If the error says the file already exists, switch to `edit` or `apply_patch`.
6. Never fabricate file contents or line anchors. Always copy them from actual `read` output.
7. When using `edit` with hash-anchored LINE#ID references, copy exact anchors from `read` output. Do not guess or fabricate anchors.
</tool-calling-rules>
''';

/// 与 OpenCode `packages/opencode/src/tool/question.txt` 正文一致。
/// `custom` 由客户端默认开启，模型侧 schema 不包含该字段（同 OpenCode `Question.Info.omit({ custom: true })`）。
const String kQuestionToolDescription = r'''
Use this tool when you need to ask the user questions during execution. This allows you to:
1. Gather user preferences or requirements
2. Clarify ambiguous instructions
3. Get decisions on implementation choices as you work
4. Offer choices to the user about what direction to take.

Usage notes:
- When `custom` is enabled (default), a "Type your own answer" option is added automatically; don't include "Other" or catch-all options
- Answers are returned as arrays of labels; set `multiple: true` to allow selecting more than one
- If you recommend a specific option, make that the first option in the list and add "(Recommended)" at the end of the label
''';

/// JSON Schema for `question` parameters (`Question.Info` shape without `custom`).
JsonMap questionToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'questions': {
          'type': 'array',
          'description': 'Questions to ask',
          'items': {
            'type': 'object',
            'properties': {
              'question': {
                'type': 'string',
                'description': 'Complete question',
              },
              'header': {
                'type': 'string',
                'description': 'Very short label (max 30 chars)',
              },
              'options': {
                'type': 'array',
                'description': 'Available choices',
                'items': {
                  'type': 'object',
                  'properties': {
                    'label': {
                      'type': 'string',
                      'description': 'Display text (1-5 words, concise)',
                    },
                    'description': {
                      'type': 'string',
                      'description': 'Explanation of choice',
                    },
                  },
                  'required': ['label', 'description'],
                  'additionalProperties': false,
                },
                'minItems': 1,
              },
              'multiple': {
                'type': 'boolean',
                'description': 'Allow selecting multiple choices',
              },
            },
            'required': ['question', 'header', 'options'],
            'additionalProperties': false,
          },
          'minItems': 1,
        },
      },
      'required': ['questions'],
      'additionalProperties': false,
    };
