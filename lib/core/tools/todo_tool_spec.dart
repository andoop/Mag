import '../models.dart';

const String kTodoWriteToolDescription = r'''
Create or update the task list for the current session.
- Use for complex multi-step work, multiple requested tasks, or when the user asks for a todo list.
- Skip for single simple tasks or purely informational answers.
- Keep items specific and actionable.
- Use statuses: `pending`, `in_progress`, `completed`, `cancelled`.
- Keep at most one item `in_progress`; mark completed items promptly.

''';

JsonMap todoWriteToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'todos': {
          'type': 'array',
          'description': 'The updated todo list',
          'items': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Brief description of the task',
              },
              'status': {
                'type': 'string',
                'description':
                    'Current status of the task: pending, in_progress, completed, cancelled',
              },
              'priority': {
                'type': 'string',
                'description': 'Priority level of the task: high, medium, low',
              },
            },
            'required': ['content', 'status', 'priority'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['todos'],
      'additionalProperties': false,
    };
