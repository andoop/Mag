/// Safe coercion for tool arguments and loosely-typed JSON (models may emit null
/// or numbers where strings are expected).
String jsonStringCoerce(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}
