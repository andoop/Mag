part of '../../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 紧凑底部面板：矮把手 + 不占满屏。
Widget _compactPickerHandle(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Center(
      child: Container(
        width: 36,
        height: 3,
        decoration: BoxDecoration(
          color: context.oc.muted.withOpacity(0.28),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    ),
  );
}

InputDecoration _compactPickerSearchDecoration(
  BuildContext context, {
  required String hint,
}) {
  final oc = context.oc;
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: oc.muted),
    prefixIcon: Icon(Icons.search, size: 18, color: oc.muted),
    filled: true,
    fillColor: oc.bgDeep,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: oc.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: oc.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: oc.accent, width: 1.2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}

MapEntry<int, ProviderAuthMethod>? _preferredProviderAuthMethod(
  AppState state,
  String providerId,
) {
  final methods = state.providerAuth[providerId] ?? const <ProviderAuthMethod>[];
  for (var i = 0; i < methods.length; i++) {
    if (methods[i].isOauth) return MapEntry(i, methods[i]);
  }
  for (var i = 0; i < methods.length; i++) {
    if (methods[i].isApi) return MapEntry(i, methods[i]);
  }
  return methods.isNotEmpty ? MapEntry(0, methods.first) : null;
}

ProviderAuthPrompt? _firstProviderAuthTextPrompt(ProviderAuthMethod? method) {
  if (method == null) return null;
  for (final prompt in method.prompts) {
    if (prompt.isText) return prompt;
  }
  return null;
}

bool _providerAuthPromptVisible(
  ProviderAuthPrompt prompt,
  Map<String, String> values,
) {
  final condition = prompt.when;
  if (condition == null) return true;
  final actual = values[condition.key] ?? '';
  switch (condition.op) {
    case 'neq':
      return actual != condition.value;
    case 'eq':
    default:
      return actual == condition.value;
  }
}

