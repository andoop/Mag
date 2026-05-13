import 'dart:io';
import 'dart:math';

import 'models.dart';

class DeviceCapabilityRegistry {
  DeviceCapabilityRegistry._();

  static final DeviceCapabilityRegistry instance = DeviceCapabilityRegistry._();

  static const JsonMap _fileResourceSchema = {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'mimeType': {'type': 'string'},
      'size': {'type': 'integer'},
      'url': {'type': 'string'},
    },
    'required': ['name', 'mimeType', 'size', 'url'],
  };

  final List<DeviceCapabilityDefinition> _definitions = const [
    DeviceCapabilityDefinition(
      id: 'files.pick',
      version: 1,
      category: DeviceCapabilityCategory.files,
      descriptionForAi:
          'Let user pick one or more local files on the device. Returns runtime-scoped temporary file URLs; no raw filesystem path is exposed.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'accept': {
            'type': 'string',
            'description': 'Comma-separated MIME types or extensions.'
          },
          'multiple': {'type': 'boolean'},
        },
      },
      outputSchema: {
        'type': 'array',
        'items': _fileResourceSchema,
      },
      webAliases: ['MagNative.pickFiles', 'input[type=file]'],
    ),
    DeviceCapabilityDefinition(
      id: 'media.capturePhoto',
      version: 1,
      category: DeviceCapabilityCategory.media,
      descriptionForAi:
          'Open the device camera for a user-triggered photo capture. Returns a runtime-scoped temporary image URL.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'quality': {
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
          },
        },
      },
      outputSchema: _fileResourceSchema,
      webAliases: ['MagNative.capturePhoto', 'input[type=file][capture]'],
    ),
    DeviceCapabilityDefinition(
      id: 'files.save',
      version: 1,
      category: DeviceCapabilityCategory.files,
      descriptionForAi:
          'Save app-generated content to a user-selected destination. Planned capability; not enabled in the HTML runtime yet.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'mimeType': {'type': 'string'},
          'contentBase64': {'type': 'string'},
        },
      },
      outputSchema: {
        'type': 'object',
        'properties': {
          'ok': {'type': 'boolean'},
        },
      },
      webAliases: ['MagNative.saveFile'],
    ),
    DeviceCapabilityDefinition(
      id: 'share.openSheet',
      version: 1,
      category: DeviceCapabilityCategory.share,
      descriptionForAi:
          'Open the platform share sheet for user-approved text or file sharing. Planned capability.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'url': {'type': 'string'},
        },
      },
      outputSchema: {
        'type': 'object',
        'properties': {
          'ok': {'type': 'boolean'},
        },
      },
      webAliases: ['MagNative.share'],
    ),
  ];

  List<DeviceCapabilityDefinition> available({String? platform}) {
    final target = platform ?? _currentPlatform;
    return _definitions
        .where((item) => item.platforms.contains(target))
        .toList(growable: false);
  }

  DeviceCapabilityDefinition? byId(String id, {String? platform}) {
    for (final item in available(platform: platform)) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<ToolDefinitionModel> directAiTools({String? platform}) {
    return available(platform: platform)
        .where((item) => item.directAiTool)
        .map((item) => item.toToolModel())
        .toList(growable: false);
  }

  List<String> promptCatalog({bool zh = false, String? platform}) {
    return available(platform: platform).map((item) {
      final gate = item.requiresUserGesture
          ? (zh
              ? '需要用户手势和一次性授权'
              : 'requires user gesture and one-time approval')
          : (zh ? '无需额外授权' : 'no extra approval');
      final summary = _promptSummary(item, zh: zh);
      final example = _promptExample(item, zh: zh);
      return zh
          ? '- `${item.id}` v${item.version}: $summary（$gate）。$example'
          : '- `${item.id}` v${item.version}: $summary ($gate). $example';
    }).toList(growable: false);
  }

  String _promptSummary(DeviceCapabilityDefinition item, {required bool zh}) {
    switch (item.id) {
      case 'files.pick':
        return zh
            ? '选择本地文件并返回临时可访问 URL。网页里不要直接调用能力 ID，要用 `window.MagNative.pickFiles(...)`。'
            : 'Pick local files and return temporary runtime URLs. In web pages, do not call the capability ID directly; use `window.MagNative.pickFiles(...)`.';
      case 'media.capturePhoto':
        return zh
            ? '调用设备相机拍照并返回临时图片 URL。网页里不要直接调用 `media.capturePhoto()`，要用 `window.MagNative.capturePhoto()`。'
            : 'Open the device camera and return a temporary image URL. In web pages, do not call `media.capturePhoto()` directly; use `window.MagNative.capturePhoto()`.';
      case 'files.save':
        return zh
            ? '把生成的内容保存到用户选择的位置；当前 HTML 运行时尚未启用。'
            : 'Save generated content to a user-selected destination; not enabled in the HTML runtime yet.';
      case 'share.openSheet':
        return zh
            ? '打开系统分享面板分享文本或文件；当前 HTML 运行时尚未启用。'
            : 'Open the system share sheet for text or files; not enabled in the HTML runtime yet.';
      default:
        return item.descriptionForAi;
    }
  }

  String _promptExample(DeviceCapabilityDefinition item, {required bool zh}) {
    switch (item.id) {
      case 'files.pick':
        return zh
            ? '示例：`const files = await window.MagNative.pickFiles({ multiple: true, accept: "image/*" })`。'
            : 'Example: `const files = await window.MagNative.pickFiles({ multiple: true, accept: "image/*" })`.';
      case 'media.capturePhoto':
        return zh
            ? '示例：`const photo = await window.MagNative.capturePhoto()`，或使用 `<input type="file" accept="image/*" capture>`。'
            : 'Example: `const photo = await window.MagNative.capturePhoto()`, or use `<input type="file" accept="image/*" capture>`.';
      default:
        return zh ? '示例：按暴露的 Web API 调用。' : 'Example: use the exposed web API.';
    }
  }

  String get _currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

class HtmlRuntimeFile {
  const HtmlRuntimeFile({
    required this.runtimeId,
    required this.fileId,
    required this.name,
    required this.mimeType,
    required this.path,
    required this.size,
    required this.createdAt,
    required this.expiresAt,
  });

  final String runtimeId;
  final String fileId;
  final String name;
  final String mimeType;
  final String path;
  final int size;
  final int createdAt;
  final int expiresAt;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}

class HtmlRuntimeFileStore {
  HtmlRuntimeFileStore._();

  static final HtmlRuntimeFileStore instance = HtmlRuntimeFileStore._();
  static const int _ttlMs = 30 * 60 * 1000;

  final _random = Random.secure();
  final Map<String, Map<String, HtmlRuntimeFile>> _files = {};

  String createRuntimeId() => 'html-${_randomToken()}';

  HtmlRuntimeFile registerFile({
    required String runtimeId,
    required String path,
    required String name,
    required String mimeType,
    int? size,
  }) {
    purgeExpired();
    final file = File(path);
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = HtmlRuntimeFile(
      runtimeId: runtimeId,
      fileId: _randomToken(),
      name: name,
      mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      path: path,
      size: size ?? (file.existsSync() ? file.lengthSync() : 0),
      createdAt: now,
      expiresAt: now + _ttlMs,
    );
    (_files[runtimeId] ??= <String, HtmlRuntimeFile>{})[item.fileId] = item;
    return item;
  }

  HtmlRuntimeFile? getFile(String runtimeId, String fileId) {
    final file = _files[runtimeId]?[fileId];
    if (file == null) return null;
    if (file.isExpired || !File(file.path).existsSync()) {
      _files[runtimeId]?.remove(fileId);
      return null;
    }
    return file;
  }

  void disposeRuntime(String runtimeId) {
    final files = _files.remove(runtimeId);
    if (files == null) return;
    for (final file in files.values) {
      try {
        File(file.path).deleteSync();
      } catch (_) {}
    }
  }

  void purgeExpired() {
    final empty = <String>[];
    for (final entry in _files.entries) {
      final expired = <String>[];
      for (final file in entry.value.values) {
        if (file.isExpired) {
          expired.add(file.fileId);
          try {
            File(file.path).deleteSync();
          } catch (_) {}
        }
      }
      for (final fileId in expired) {
        entry.value.remove(fileId);
      }
      if (entry.value.isEmpty) empty.add(entry.key);
    }
    for (final runtimeId in empty) {
      _files.remove(runtimeId);
    }
  }

  String _randomToken() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = List<int>.generate(12, (_) => _random.nextInt(36))
        .map((value) => value.toRadixString(36))
        .join();
    return '$timestamp-$suffix';
  }
}
