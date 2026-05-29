import '../models.dart';

/// System reminder: tool arguments must match each tool's schema and descriptions.
const String kToolCallingRulesPrompt = '''
<tool-calling-rules>
1. Tool arguments must be valid JSON and match the schema exactly.
2. Required string fields must be non-null strings. Do not omit required keys.
3. Read tool errors carefully and change strategy; do not repeat the same failing call.
4. Do not invent file contents or unavailable tools.
</tool-calling-rules>
''';

/// 与 OpenCode `packages/opencode/src/tool/question.txt` 正文一致。
/// `custom` 由客户端默认开启，模型侧 schema 不包含该字段（同 OpenCode `Question.Info.omit({ custom: true })`）。
const String kQuestionToolDescription = r'''
Ask the user for clarification or a decision.
- Keep questions short and choices mutually exclusive.
- Do not add "Other"; the UI adds a custom answer automatically.
- Put the recommended option first and suffix its label with "(Recommended)".
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
