import 'dart:convert';

/// Small shared helpers so every repository serializes lists/maps of
/// primitives to the same JSON-in-TEXT-column convention.
class JsonCodecHelpers {
  static String encodeStringList(List<String> value) => jsonEncode(value);

  static List<String> decodeStringList(String? value) {
    if (value == null || value.isEmpty) return const [];
    return (jsonDecode(value) as List).cast<String>();
  }

  static String encodeJson(Object? value) => jsonEncode(value);

  static Map<String, Object?> decodeMap(String? value) {
    if (value == null || value.isEmpty) return const {};
    return (jsonDecode(value) as Map).cast<String, Object?>();
  }

  static List<Object?> decodeList(String? value) {
    if (value == null || value.isEmpty) return const [];
    return jsonDecode(value) as List<Object?>;
  }
}
