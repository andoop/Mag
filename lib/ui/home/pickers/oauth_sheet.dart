part of '../../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

class _ProviderOAuthSheet extends StatefulWidget {
  const _ProviderOAuthSheet({
    required this.controller,
    required this.preset,
    required this.methodIndex,
    required this.method,
    this.envSummary,
  });

  final AppController controller;
  final _ProviderPreset preset;
  final int methodIndex;
  final ProviderAuthMethod method;
  final String? envSummary;

  @override
  State<_ProviderOAuthSheet> createState() => _ProviderOAuthSheetState();
}

class _ProviderOAuthSheetState extends State<_ProviderOAuthSheet> {
  late final Map<String, TextEditingController> _textControllers = {
    for (final prompt in widget.method.prompts)
      if (prompt.isText) prompt.key: TextEditingController(),
  };
  late final Map<String, String> _values = {
    for (final prompt in widget.method.prompts)
      if (!prompt.isText)
        prompt.key: prompt.options.isNotEmpty ? prompt.options.first.value : '',
  };
  final TextEditingController _codeController = TextEditingController();

  ProviderAuthAuthorization? _authorization;
  WebViewController? _webViewController;
  bool _authorizing = false;
  bool _completing = false;

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _codeController.dispose();
    super.dispose();
  }

  Map<String, String> _promptValues() {
    final result = <String, String>{..._values};
    for (final entry in _textControllers.entries) {
      result[entry.key] = entry.value.text.trim();
    }
    return result;
  }

  void _captureCodeFromUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return;
    try {
      final uri = Uri.parse(rawUrl);
      final code = uri.queryParameters['code'] ?? '';
      if (code.isEmpty || code == _codeController.text.trim()) return;
      setState(() {
        _codeController.text = code;
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _startAuthorize() async {
    setState(() {
      _authorizing = true;
    });
    try {
      final authorization = await widget.controller.authorizeProviderOAuth(
        widget.preset.id,
        method: widget.methodIndex,
        inputs: _promptValues(),
      );
      if (!mounted) return;
      if (authorization == null || authorization.url.trim().isEmpty) {
        _showInfo(
          context,
          l(
            context,
            '当前 provider 还没有可用的 OAuth 授权入口。',
            'OAuth authorize is not available for this provider yet.',
          ),
        );
        return;
      }
      final webView = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              _captureCodeFromUrl(request.url);
              return NavigationDecision.navigate;
            },
            onPageStarted: _captureCodeFromUrl,
            onPageFinished: _captureCodeFromUrl,
          ),
        )
        ..loadRequest(Uri.parse(authorization.url));
      setState(() {
        _authorization = authorization;
        _webViewController = webView;
      });
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _authorizing = false;
        });
      }
    }
  }

  Future<void> _completeAuthorize() async {
    final authorization = _authorization;
    if (authorization == null) return;
    final code = _codeController.text.trim();
    if (authorization.isCode && code.isEmpty) {
      _showInfo(
        context,
        l(context, '请先完成授权并填写 code', 'Complete auth and enter the code first'),
      );
      return;
    }
    setState(() {
      _completing = true;
    });
    try {
      await widget.controller.callbackProviderOAuth(
        widget.preset.id,
        method: widget.methodIndex,
        code: authorization.isCode ? code : null,
      );
      if (!mounted) return;
      _showInfo(
        context,
        l(context, 'OAuth 连接已完成', 'OAuth connection completed'),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _completing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final promptValues = _promptValues();
    final visiblePrompts = widget.method.prompts
        .where((prompt) => _providerAuthPromptVisible(prompt, promptValues))
        .toList();
    final heightFactor = _authorization == null ? 0.58 : 0.88;
    return FractionallySizedBox(
      heightFactor: heightFactor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: oc.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: oc.border),
            boxShadow: [
              BoxShadow(
                color: oc.shadow,
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _compactPickerHandle(context),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l(context, '通过 OAuth 连接 ${widget.preset.name}',
                            'Connect ${widget.preset.name} with OAuth'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: oc.text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if ((widget.preset.note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      widget.preset.note!,
                      style: TextStyle(fontSize: 12.5, color: oc.muted),
                    ),
                  ),
                if ((widget.envSummary ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l(
                        context,
                        '环境变量：${widget.envSummary}',
                        'Environment: ${widget.envSummary}',
                      ),
                      style: TextStyle(fontSize: 12, color: oc.muted),
                    ),
                  ),
                if (_authorization == null) ...[
                  for (final prompt in visiblePrompts) ...[
                    if (prompt.isText) ...[
                      TextField(
                        controller: _textControllers[prompt.key],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: prompt.message,
                          hintText: prompt.placeholder,
                        ),
                      ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        value: _values[prompt.key],
                        decoration: InputDecoration(labelText: prompt.message),
                        items: prompt.options
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option.value,
                                child: Text(option.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _values[prompt.key] = value ?? '';
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  Text(
                    l(
                      context,
                      '会在内置浏览器中打开授权页，完成后再回到这里提交回调。',
                      'The auth page will open in the built-in browser, then come back here to complete the callback.',
                    ),
                    style: TextStyle(fontSize: 12, color: oc.muted),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _authorizing ? null : _startAuthorize,
                    icon: _authorizing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_browser_rounded),
                    label: Text(l(context, '开始授权', 'Start authorization')),
                  ),
                ] else ...[
                  if (_authorization!.instructions.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _authorization!.instructions,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: oc.muted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _authorization!.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: oc.muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: l(context, '复制链接', 'Copy URL'),
                        onPressed: () => _copyText(
                          context,
                          _authorization!.url,
                          l(context, '链接已复制', 'URL copied'),
                        ),
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: oc.panelBackground,
                          border: Border.all(color: oc.border),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _webViewController == null
                            ? const SizedBox.shrink()
                            : WebViewWidget(controller: _webViewController!),
                      ),
                    ),
                  ),
                  if (_authorization!.isCode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: l(context, '授权 Code', 'Authorization code'),
                        hintText: l(
                          context,
                          '如果没有自动识别，请手动粘贴 code',
                          'Paste the code manually if it was not detected',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _completing ? null : _completeAuthorize,
                    icon: _completing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(l(context, '完成连接', 'Complete connection')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

