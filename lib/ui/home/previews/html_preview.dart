part of '../../home_page.dart';

class _WorkspaceHtmlPreview extends StatefulWidget {
  const _WorkspaceHtmlPreview({
    required this.html,
    required this.serverUri,
  });

  final String html;
  final Uri? serverUri;

  @override
  State<_WorkspaceHtmlPreview> createState() => _WorkspaceHtmlPreviewState();
}

class _WorkspaceHtmlPreviewState extends State<_WorkspaceHtmlPreview> {
  late final WebViewController _controller;
  late final _HtmlRuntimeHost _runtime;

  @override
  void initState() {
    super.initState();
    _runtime = _HtmlRuntimeHost(
      context: context,
      serverUri: widget.serverUri,
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _HtmlRuntimeHost.channelName,
        onMessageReceived: (message) =>
            _runtime.handleMessage(_controller, message.message),
      )
      ..loadHtmlString(
        _runtime.wrapHtml(widget.html),
        baseUrl: _runtime.baseUrl,
      );
  }

  @override
  void didUpdateWidget(covariant _WorkspaceHtmlPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverUri != widget.serverUri) {
      _runtime.serverUri = widget.serverUri;
    }
    if (oldWidget.html != widget.html ||
        oldWidget.serverUri != widget.serverUri) {
      _controller.loadHtmlString(
        _runtime.wrapHtml(widget.html),
        baseUrl: _runtime.baseUrl,
      );
    }
  }

  @override
  void dispose() {
    _runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

class _HtmlRuntimeHost {
  _HtmlRuntimeHost({
    required BuildContext context,
    required this.serverUri,
  })  : _context = context,
        runtimeId = HtmlRuntimeFileStore.instance.createRuntimeId();

  static const channelName = 'MagNativeHost';

  final BuildContext _context;
  final String runtimeId;
  Uri? serverUri;
  final Set<String> _approvedCapabilities = {};

  String get baseUrl => serverUri?.toString() ?? 'about:blank';

  String wrapHtml(String html) {
    final bootstrap = _magNativeBootstrap(runtimeId);
    final lower = html.toLowerCase();
    if (lower.contains('</head>')) {
      return html.replaceFirst(RegExp('</head>', caseSensitive: false),
          '<script>$bootstrap</script></head>');
    }
    if (lower.contains('<html')) {
      return html.replaceFirstMapped(
        RegExp('<html[^>]*>', caseSensitive: false),
        (match) => '${match.group(0)}<head><script>$bootstrap</script></head>',
      );
    }
    return '<!doctype html><html><head><script>$bootstrap</script></head><body>$html</body></html>';
  }

  Future<void> handleMessage(
    WebViewController controller,
    String rawMessage,
  ) async {
    String? requestId;
    try {
      final data = jsonDecode(rawMessage);
      if (data is! Map) throw const FormatException('Invalid bridge message.');
      requestId = data['id'] as String?;
      final capabilityId = data['capabilityId'] as String? ?? '';
      final input = Map<String, dynamic>.from(data['input'] as Map? ?? {});
      if (requestId == null || requestId.isEmpty) {
        throw const FormatException('Missing bridge request id.');
      }
      final result = await _invokeCapability(capabilityId, input);
      await _resolve(controller, requestId, result);
    } catch (error) {
      if (requestId != null && requestId.isNotEmpty) {
        await _reject(controller, requestId, error.toString());
      }
    }
  }

  Future<dynamic> _invokeCapability(
    String capabilityId,
    Map<String, dynamic> input,
  ) async {
    final definition = DeviceCapabilityRegistry.instance.byId(capabilityId);
    if (definition == null) {
      throw UnsupportedError('Unsupported device capability: $capabilityId');
    }
    await _ensureApproved(definition);
    switch (capabilityId) {
      case 'files.pick':
        final files = await DeviceCapabilityBridge.pickFiles(
          accept: input['accept'] as String?,
          multiple: input['multiple'] == true,
        );
        return files.map(_registerNativeFile).toList();
      case 'media.capturePhoto':
        final file = await DeviceCapabilityBridge.capturePhoto();
        if (file == null) return null;
        return _registerNativeFile(file);
      case 'media.recordAudio':
        final file = await DeviceCapabilityBridge.recordAudio();
        if (file == null) return null;
        return _registerNativeFile(file);
      case 'media.recordVideo':
        final file = await DeviceCapabilityBridge.recordVideo();
        if (file == null) return null;
        return _registerNativeFile(file);
      default:
        throw UnsupportedError('Capability is declared but not implemented.');
    }
  }

  Future<void> _ensureApproved(DeviceCapabilityDefinition definition) async {
    if (!definition.requiresUserGesture ||
        _approvedCapabilities.contains(definition.id)) {
      return;
    }
    if (!_context.mounted) {
      throw StateError('Cannot request capability permission without context.');
    }
    final allowed = await showDialog<bool>(
          context: _context,
          builder: (dialogContext) {
            final zh = Localizations.localeOf(dialogContext)
                .languageCode
                .toLowerCase()
                .startsWith('zh');
            return AlertDialog(
              title: Text(zh ? '允许端上能力？' : 'Allow Device Capability?'),
              content: Text(
                zh
                    ? '这个 HTML 想使用 `${definition.id}`。允许后仅对当前预览生效，关闭预览会清理临时文件。'
                    : 'This HTML wants to use `${definition.id}`. Approval only applies to the current preview and temporary files are cleaned up when it closes.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(zh ? '拒绝' : 'Deny'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(zh ? '允许一次' : 'Allow Once'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!allowed) throw Exception('Permission rejected by user');
    _approvedCapabilities.add(definition.id);
  }

  Map<String, dynamic> _registerNativeFile(DeviceCapabilityFile file) {
    final registered = HtmlRuntimeFileStore.instance.registerFile(
      runtimeId: runtimeId,
      path: file.path,
      name: file.name,
      mimeType: file.mimeType,
      size: file.size,
    );
    return {
      'name': registered.name,
      'mimeType': registered.mimeType,
      'size': registered.size,
      'url': _runtimeFileUrl(registered),
    };
  }

  String _runtimeFileUrl(HtmlRuntimeFile file) {
    final base = serverUri;
    final path = '/html-runtime/${Uri.encodeComponent(file.runtimeId)}'
        '/file/${Uri.encodeComponent(file.fileId)}';
    if (base == null) return path;
    return base.replace(path: path, query: null, fragment: null).toString();
  }

  Future<void> _resolve(
    WebViewController controller,
    String requestId,
    dynamic result,
  ) {
    return controller.runJavaScript(
      'window.__magNativeResolve(${jsonEncode(requestId)}, ${jsonEncode(result)});',
    );
  }

  Future<void> _reject(
    WebViewController controller,
    String requestId,
    String message,
  ) {
    return controller.runJavaScript(
      'window.__magNativeReject(${jsonEncode(requestId)}, ${jsonEncode(message)});',
    );
  }

  void dispose() {
    HtmlRuntimeFileStore.instance.disposeRuntime(runtimeId);
  }
}

String _magNativeBootstrap(String runtimeId) {
  return '''
(function() {
  if (window.MagNative && window.MagNative.__runtimeId === ${jsonEncode(runtimeId)}) return;
  const pending = new Map();
  let nextId = 1;
  function post(capabilityId, input) {
    return new Promise(function(resolve, reject) {
      const id = String(nextId++);
      pending.set(id, { resolve, reject });
      ${_HtmlRuntimeHost.channelName}.postMessage(JSON.stringify({
        id: id,
        capabilityId: capabilityId,
        input: input || {}
      }));
    });
  }
  window.__magNativeResolve = function(id, value) {
    const item = pending.get(String(id));
    if (!item) return;
    pending.delete(String(id));
    item.resolve(value);
  };
  window.__magNativeReject = function(id, message) {
    const item = pending.get(String(id));
    if (!item) return;
    pending.delete(String(id));
    item.reject(new Error(message || 'Device capability failed'));
  };
  async function fillFileInput(input, files) {
    if (!input || !files || !files.length || typeof DataTransfer === 'undefined') {
      input && input.dispatchEvent(new CustomEvent('mag-native-files', { detail: files || [] }));
      return;
    }
    const dataTransfer = new DataTransfer();
    for (const file of files) {
      const response = await fetch(file.url);
      const blob = await response.blob();
      dataTransfer.items.add(new File([blob], file.name || 'file', {
        type: file.mimeType || blob.type || 'application/octet-stream'
      }));
    }
    input.files = dataTransfer.files;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  window.MagNative = {
    __runtimeId: ${jsonEncode(runtimeId)},
    invoke: post,
    pickFiles: function(options) { return post('files.pick', options || {}); },
    capturePhoto: function(options) { return post('media.capturePhoto', options || {}); },
    recordAudio: function(options) { return post('media.recordAudio', options || {}); },
    recordVideo: function(options) { return post('media.recordVideo', options || {}); }
  };
  document.addEventListener('click', function(event) {
    const input = event.target && event.target.closest ? event.target.closest('input[type="file"]') : null;
    if (!input || input.dataset.magNativeDisabled === 'true') return;
    event.preventDefault();
    event.stopPropagation();
    const accept = input.getAttribute('accept') || '';
    const capture = input.hasAttribute('capture');
    const multiple = input.hasAttribute('multiple');
    const lowerAccept = accept.toLowerCase();
    const captureTask = lowerAccept.indexOf('video/') >= 0
      ? window.MagNative.recordVideo({ accept: accept, capture: input.getAttribute('capture') || true })
      : lowerAccept.indexOf('audio/') >= 0
        ? window.MagNative.recordAudio({ accept: accept, capture: input.getAttribute('capture') || true })
        : window.MagNative.capturePhoto({ accept: accept, capture: input.getAttribute('capture') || true });
    const task = capture
      ? captureTask.then(function(file) { return file ? [file] : []; })
      : window.MagNative.pickFiles({ accept: accept, multiple: multiple });
    task.then(function(files) { return fillFileInput(input, files); })
      .catch(function(error) { console.error('[MagNative] input file failed', error); });
  }, true);
})();
''';
}
