/// Configuration file parser and writer
library;

import 'dart:io';

/// Git configuration
class GitConfig {
  final Map<String, Map<String, dynamic>> _config = {};
  final String configPath;

  GitConfig(this.configPath);

  /// Load configuration from file
  static Future<GitConfig> load(String path) async {
    final config = GitConfig(path);
    final file = File(path);

    if (await file.exists()) {
      final content = await file.readAsString();
      config._parse(content);
    }

    return config;
  }

  /// Parse INI-style configuration
  void _parse(String content) {
    var currentSection = '';
    final lines = content.split('\n');

    for (var line in lines) {
      line = line.trim();

      // Skip comments and empty lines
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }

      // Section header [section] or [section "subsection"]
      if (line.startsWith('[') && line.endsWith(']')) {
        currentSection = line.substring(1, line.length - 1);
        _config[currentSection] ??= {};
        continue;
      }

      // Key-value pair
      final parts = line.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();

        if (currentSection.isNotEmpty) {
          _config[currentSection]![key] = _parseValue(value);
        }
      } else if (parts.length == 1) {
        // Boolean key without value (treated as true)
        final key = parts[0].trim();
        if (currentSection.isNotEmpty) {
          _config[currentSection]![key] = true;
        }
      }
    }
  }

  /// Parse configuration value
  dynamic _parseValue(String value) {
    // Remove quotes
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }

    // Boolean values
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == 'yes' || lower == 'on') {
      return true;
    }
    if (lower == 'false' || lower == 'no' || lower == 'off') {
      return false;
    }

    // Try parsing as integer
    final intValue = int.tryParse(value);
    if (intValue != null) {
      return intValue;
    }

    return value;
  }

  /// Get configuration value
  dynamic get(String section, String key, {dynamic defaultValue}) {
    return _config[section]?[key] ?? defaultValue;
  }

  /// Set configuration value
  void set(String section, String key, dynamic value) {
    _config[section] ??= {};
    _config[section]![key] = value;
  }

  /// Check if section exists
  bool hasSection(String section) {
    return _config.containsKey(section);
  }

  /// Get all keys in a section
  List<String> getSectionKeys(String section) {
    return _config[section]?.keys.toList() ?? [];
  }

  /// Save configuration to file
  Future<void> save() async {
    final buffer = StringBuffer();

    for (final section in _config.keys) {
      buffer.writeln('[$section]');
      for (final key in _config[section]!.keys) {
        final value = _config[section]![key];
        if (value is bool) {
          buffer.writeln('\t$key = $value');
        } else if (value is String && value.contains(' ')) {
          buffer.writeln('\t$key = "$value"');
        } else {
          buffer.writeln('\t$key = $value');
        }
      }
      buffer.writeln();
    }

    final file = File(configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(buffer.toString());
  }

  /// Create default configuration
  static GitConfig createDefault(String path) {
    final config = GitConfig(path);

    // Core settings
    config.set('core', 'repositoryformatversion', 0);
    config.set('core', 'filemode', true);
    config.set('core', 'bare', false);
    config.set('core', 'logallrefupdates', true);

    // Platform-specific settings
    if (Platform.isWindows || Platform.isMacOS) {
      config.set('core', 'ignorecase', true);
    }

    return config;
  }
}
