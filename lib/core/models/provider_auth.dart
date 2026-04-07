part of '../models.dart';

class ProviderAuthPromptCondition {
  const ProviderAuthPromptCondition({
    required this.key,
    required this.op,
    required this.value,
  });

  final String key;
  final String op;
  final String value;

  JsonMap toJson() => {
        'key': key,
        'op': op,
        'value': value,
      };

  factory ProviderAuthPromptCondition.fromJson(JsonMap json) =>
      ProviderAuthPromptCondition(
        key: (json['key'] as String?) ?? '',
        op: (json['op'] as String?) ?? 'eq',
        value: (json['value'] as String?) ?? '',
      );
}

class ProviderAuthPromptOption {
  const ProviderAuthPromptOption({
    required this.label,
    required this.value,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;

  JsonMap toJson() => {
        'label': label,
        'value': value,
        if (hint != null) 'hint': hint,
      };

  factory ProviderAuthPromptOption.fromJson(JsonMap json) =>
      ProviderAuthPromptOption(
        label: (json['label'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
        hint: json['hint'] as String?,
      );
}

class ProviderAuthPrompt {
  const ProviderAuthPrompt({
    required this.type,
    required this.key,
    required this.message,
    this.placeholder,
    this.options = const [],
    this.when,
  });

  final String type;
  final String key;
  final String message;
  final String? placeholder;
  final List<ProviderAuthPromptOption> options;
  final ProviderAuthPromptCondition? when;

  bool get isText => type == 'text';

  JsonMap toJson() => {
        'type': type,
        'key': key,
        'message': message,
        if (placeholder != null) 'placeholder': placeholder,
        if (options.isNotEmpty) 'options': options.map((item) => item.toJson()).toList(),
        if (when != null) 'when': when!.toJson(),
      };

  factory ProviderAuthPrompt.fromJson(JsonMap json) => ProviderAuthPrompt(
        type: (json['type'] as String?) ?? 'text',
        key: (json['key'] as String?) ?? '',
        message: (json['message'] as String?) ?? '',
        placeholder: json['placeholder'] as String?,
        options: (json['options'] as List? ?? const [])
            .map(
              (item) => ProviderAuthPromptOption.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        when: json['when'] == null
            ? null
            : ProviderAuthPromptCondition.fromJson(
                Map<String, dynamic>.from(json['when'] as Map),
              ),
      );
}

class ProviderAuthMethod {
  const ProviderAuthMethod({
    required this.type,
    required this.label,
    this.prompts = const [],
  });

  final String type;
  final String label;
  final List<ProviderAuthPrompt> prompts;

  bool get isApi => type == 'api';
  bool get isOauth => type == 'oauth';

  JsonMap toJson() => {
        'type': type,
        'label': label,
        if (prompts.isNotEmpty) 'prompts': prompts.map((item) => item.toJson()).toList(),
      };

  factory ProviderAuthMethod.fromJson(JsonMap json) => ProviderAuthMethod(
        type: (json['type'] as String?) ?? 'api',
        label: (json['label'] as String?) ?? '',
        prompts: (json['prompts'] as List? ?? const [])
            .map(
              (item) => ProviderAuthPrompt.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
}

class ProviderAuthAuthorization {
  const ProviderAuthAuthorization({
    required this.url,
    required this.method,
    required this.instructions,
  });

  final String url;
  final String method;
  final String instructions;

  bool get isCode => method == 'code';
  bool get isAuto => method == 'auto';

  JsonMap toJson() => {
        'url': url,
        'method': method,
        'instructions': instructions,
      };

  factory ProviderAuthAuthorization.fromJson(JsonMap json) =>
      ProviderAuthAuthorization(
        url: (json['url'] as String?) ?? '',
        method: (json['method'] as String?) ?? 'auto',
        instructions: (json['instructions'] as String?) ?? '',
      );
}

Map<String, List<ProviderAuthMethod>> providerAuthMethodsFromJson(JsonMap json) {
  return json.map(
    (key, value) => MapEntry(
      key,
      (value as List? ?? const [])
          .map(
            (item) => ProviderAuthMethod.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    ),
  );
}

JsonMap providerAuthMethodsToJson(Map<String, List<ProviderAuthMethod>> methods) {
  return methods.map(
    (key, value) => MapEntry(
      key,
      value.map((item) => item.toJson()).toList(),
    ),
  );
}
