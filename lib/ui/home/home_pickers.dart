part of '../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

/// OpenCode 式紧凑底部面板：矮把手 + 不占满屏。
Widget _compactPickerHandle() {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Center(
      child: Container(
        width: 36,
        height: 3,
        decoration: BoxDecoration(
          color: kOcMuted.withOpacity(0.28),
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
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
    prefixIcon: const Icon(Icons.search, size: 18, color: kOcMuted),
    filled: true,
    fillColor: const Color(0xFFF4F4F5),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kOcAccent, width: 1.2),
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
            color: kOcSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kOcBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
                _compactPickerHandle(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l(context, '通过 OAuth 连接 ${widget.preset.name}',
                            'Connect ${widget.preset.name} with OAuth'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kOcText,
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
                      style: const TextStyle(fontSize: 12.5, color: kOcMuted),
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
                      style: const TextStyle(fontSize: 12, color: kOcMuted),
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
                    style: const TextStyle(fontSize: 12, color: kOcMuted),
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
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: kOcMuted,
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
                          style: const TextStyle(fontSize: 12, color: kOcMuted),
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
                          color: Colors.white,
                          border: Border.all(color: kOcBorder),
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

extension _HomePagePickers on _HomePageState {
  Future<void> _openSessionPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.sessions.isEmpty) return;
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = state.sessions.where((item) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return item.title.toLowerCase().contains(q) ||
                  item.agent.toLowerCase().contains(q) ||
                  item.id.toLowerCase().contains(q);
            }).toList();
            final currentModel =
                state.modelConfig?.model ?? ModelConfig.defaults().model;
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    12,
              ),
              child: FractionallySizedBox(
                heightFactor: 0.78,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kOcSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kOcBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ocSheetDragHandle(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l(context, 'Sessions', 'Sessions'),
                                    style: const TextStyle(
                                      color: kOcText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l(
                                      context,
                                      '按更新时间排序 · 最近会话优先',
                                      'Newest first',
                                    ),
                                    style: const TextStyle(
                                      color: kOcMuted,
                                      fontSize: 12.5,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded, color: kOcMuted),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          onChanged: (value) {
                            query = value.trim().toLowerCase();
                            setModalState(() {});
                          },
                          style: const TextStyle(color: kOcText, fontSize: 15),
                          cursorColor: kOcAccent,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: kOcBgDeep,
                            hintText:
                                l(context, '搜索会话…', 'Search sessions…'),
                            hintStyle:
                                TextStyle(color: kOcMuted.withOpacity(0.9)),
                            prefixIcon:
                                const Icon(Icons.search_rounded, color: kOcMuted),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: kOcBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: kOcBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: kOcAccent, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  l(context, '没有匹配的会话', 'No matching sessions'),
                                  style: const TextStyle(color: kOcMuted),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  final selected =
                                      item.id == state.session?.id;
                                  final ratio =
                                      _contextUsageRatio(item, currentModel);
                                  final percent = (ratio * 100).round();
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        _stickToBottom = true;
                                        Navigator.of(context).pop();
                                        await widget.controller
                                            .switchSession(item);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? kOcSelectedFill
                                              : kOcBgDeep,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: selected
                                                ? kOcAccent.withOpacity(0.45)
                                                : kOcBorder,
                                            width: selected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color: kOcBorder),
                                              ),
                                              child: const Icon(
                                                Icons.terminal_rounded,
                                                color: kOcAccentMuted,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          item.title.isEmpty
                                                              ? l(
                                                                  context,
                                                                  '未命名会话',
                                                                  'Untitled session',
                                                                )
                                                              : item.title,
                                                          style: TextStyle(
                                                            color: kOcText,
                                                            fontSize: 15,
                                                            fontWeight: selected
                                                                ? FontWeight.w700
                                                                : FontWeight.w600,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      if (selected)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  left: 8),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: kOcAccent
                                                                  .withOpacity(
                                                                      0.22),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                            child: Text(
                                                              l(context, '当前',
                                                                  'Active'),
                                                              style:
                                                                  const TextStyle(
                                                                color:
                                                                    kOcAccent,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    '${_ocRelativeTime(context, item.updatedAt)} · ${item.agent} · ${_contextUsageLabel(item, currentModel)} · $percent%',
                                                    style: const TextStyle(
                                                      color: kOcMuted,
                                                      fontSize: 12.5,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAgentPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.agents.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kOcSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kOcBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ocSheetDragHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l(context, 'Agents', 'Agents'),
                              style: const TextStyle(
                                color: kOcText,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l(
                                context,
                                '主会话与子代理角色',
                                'Primary & subagent roles',
                              ),
                              style: const TextStyle(
                                color: kOcMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: kOcMuted),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: (MediaQuery.of(context).size.height * 0.5)
                      .clamp(220.0, 520.0),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: state.agents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final agent = state.agents[index];
                      final selected =
                          (_selectedAgent ?? state.session?.agent ?? 'build') ==
                              agent.name;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _selectedAgent = agent.name;
                            });
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? kOcSelectedFill
                                  : kOcBgDeep,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? kOcAccent.withOpacity(0.45)
                                    : kOcBorder,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: kOcBorder),
                                  ),
                                  child: Icon(
                                    Icons.smart_toy_outlined,
                                    color: selected ? kOcAccent : kOcMuted,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              agent.name,
                                              style: TextStyle(
                                                color: kOcText,
                                                fontSize: 15,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (selected)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: kOcAccent.withOpacity(0.22),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                l(context, '当前', 'Active'),
                                                style: const TextStyle(
                                                  color: kOcAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (agent.description.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          agent.description,
                                          style: const TextStyle(
                                            color: kOcMuted,
                                            fontSize: 12.5,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings(BuildContext context, ModelConfig? config) async {
    final current = config ?? ModelConfig.defaults();
    final connection = current.currentConnection;
    if (connection == null) return;
    final baseUrl = TextEditingController(text: connection.baseUrl);
    final apiKey = TextEditingController(text: connection.apiKey);
    final model = TextEditingController(text: current.model);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: baseUrl,
                  decoration: InputDecoration(
                      labelText: l(context, 'Base URL', 'Base URL'))),
              const SizedBox(height: 12),
              TextField(
                  controller: apiKey,
                  decoration: InputDecoration(
                      labelText: l(context, 'API Key', 'API Key'))),
              const SizedBox(height: 12),
              TextField(
                  controller: model,
                  decoration:
                      InputDecoration(labelText: l(context, '模型', 'Model'))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await widget.controller.connectProvider(
                    connection.copyWith(
                      baseUrl: baseUrl.text.trim(),
                      apiKey: apiKey.text.trim(),
                      models: model.text.trim().isEmpty
                          ? connection.models
                          : [model.text.trim(), ...connection.models],
                    ),
                    currentModelId: model.text.trim().isEmpty
                        ? current.model
                        : model.text.trim(),
                    select: true,
                  );
                  if (mounted) Navigator.of(context).pop();
                },
                child: Text(l(context, '保存', 'Save')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openConnectPresetProvider(
    BuildContext context,
    _ProviderPreset preset,
  ) async {
    final state = widget.controller.state;
    final providerInfo = _providerInfoById(preset.id, state: state);
    final authEntry = _preferredProviderAuthMethod(state, preset.id);
    final authMethod = authEntry?.value;
    final authMethodIndex = authEntry?.key ?? 0;
    final authPrompt = _firstProviderAuthTextPrompt(authMethod);
    final authLabel =
        authPrompt?.message ?? authMethod?.label ?? l(context, 'API Key', 'API Key');
    final envSummary = providerInfo != null && providerInfo.env.isNotEmpty
        ? providerInfo.env.join(', ')
        : null;
    if (authMethod != null && authMethod.isOauth) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: _kPageBackground,
        barrierColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) => _ProviderOAuthSheet(
          controller: widget.controller,
          preset: preset,
          methodIndex: authMethodIndex,
          method: authMethod,
          envSummary: envSummary,
        ),
      );
      return;
    }
    final requiresSecret = authPrompt != null || preset.requiresApiKey;
    final apiKeyController = TextEditingController();
    final baseUrlController = TextEditingController(text: preset.baseUrl);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.of(sheetContext).viewInsets.bottom + 12,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kOcSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kOcBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compactPickerHandle(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l(context, '连接 ${preset.name}', 'Connect ${preset.name}'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kOcText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if ((preset.note ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        preset.note!,
                        style: const TextStyle(fontSize: 12.5, color: kOcMuted),
                      ),
                    ),
                  if (envSummary != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        l(
                          context,
                          '环境变量：$envSummary',
                          'Environment: $envSummary',
                        ),
                        style: const TextStyle(fontSize: 12, color: kOcMuted),
                      ),
                    ),
                  TextField(
                    controller: baseUrlController,
                    decoration: InputDecoration(
                      labelText: l(context, 'Base URL', 'Base URL'),
                    ),
                  ),
                  if (requiresSecret) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKeyController,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: authLabel,
                        hintText: authPrompt?.placeholder,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l(
                          context,
                          '此供应商可直接连接，无需填写密钥。',
                          'This provider can connect without a key.',
                        ),
                        style: const TextStyle(fontSize: 12, color: kOcMuted),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      if (baseUrlController.text.trim().isEmpty) {
                        _showInfo(
                          context,
                          l(context, 'Base URL 不能为空', 'Base URL is required'),
                        );
                        return;
                      }
                      if (requiresSecret && apiKeyController.text.trim().isEmpty) {
                        _showInfo(
                          context,
                          l(
                            context,
                            '请先填写$authLabel',
                            'Please enter $authLabel',
                          ),
                        );
                        return;
                      }
                      await _connectProviderPreset(
                        preset,
                        apiKey: apiKeyController.text.trim(),
                        overrideBaseUrl: baseUrlController.text.trim(),
                      );
                      if (!mounted) return;
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: Text(l(context, '连接', 'Connect')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCustomProviderSheet(BuildContext context) async {
    final providerId = TextEditingController();
    final providerName = TextEditingController();
    final baseUrl = TextEditingController();
    final apiKey = TextEditingController();
    final models = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l(context, '自定义供应商', 'Custom Provider'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                TextField(
                  controller: providerId,
                  decoration: InputDecoration(
                    labelText: l(context, 'Provider ID', 'Provider ID'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: providerName,
                  decoration: InputDecoration(
                    labelText: l(context, '显示名称', 'Display name'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrl,
                  decoration: InputDecoration(
                    labelText: l(context, 'Base URL', 'Base URL'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKey,
                  decoration: InputDecoration(
                    labelText: l(context, 'API Key', 'API Key'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: models,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: l(context, '模型列表（每行一个）', 'Models (one per line)'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final providerIdValue = providerId.text.trim();
                    final providerNameValue = providerName.text.trim();
                    final baseUrlValue = baseUrl.text.trim();
                    final ids = models.text
                        .split(RegExp(r'[\n,]'))
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList();
                    final current =
                        widget.controller.state.modelConfig ?? ModelConfig.defaults();
                    if (providerIdValue.isEmpty ||
                        !RegExp(r'^[a-z0-9][a-z0-9-_]*$').hasMatch(providerIdValue)) {
                      _showInfo(
                        context,
                        l(
                          context,
                          'Provider ID 需为小写字母/数字，可包含 - 或 _',
                          'Provider ID must use lowercase letters/numbers, with optional - or _',
                        ),
                      );
                      return;
                    }
                    if (current.connectionFor(providerIdValue) != null) {
                      _showInfo(
                        context,
                        l(context, '这个 Provider ID 已存在', 'This provider ID already exists'),
                      );
                      return;
                    }
                    if (providerNameValue.isEmpty || baseUrlValue.isEmpty) {
                      _showInfo(
                        context,
                        l(context, '名称和 Base URL 不能为空', 'Name and Base URL are required'),
                      );
                      return;
                    }
                    if (ids.isEmpty) {
                      _showInfo(
                        context,
                        l(context, '请至少填写一个模型 ID', 'Please add at least one model ID'),
                      );
                      return;
                    }
                    await _connectCustomProvider(
                      providerId: providerIdValue,
                      name: providerNameValue,
                      baseUrl: baseUrlValue,
                      apiKey: apiKey.text.trim(),
                      models: ids,
                    );
                    if (!mounted) return;
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(l(context, '添加供应商', 'Add provider')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openManageModelsSheet(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final state = widget.controller.state;
            final config = state.modelConfig ?? ModelConfig.defaults();
            final connectedProviders =
                _connectedProviderPresets(config, state: state);
            final grouped = <_ProviderPreset, List<_ModelChoice>>{};
            for (final provider in connectedProviders) {
              final matches = _modelsForProvider(
                provider.id,
                config: config,
                state: state,
              )
                  .where((item) => _matchesModelQuery(item, query))
                  .toList();
              if (matches.isNotEmpty) {
                grouped[provider] = matches;
              }
            }
            return FractionallySizedBox(
              heightFactor: 0.72,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(sheetContext).viewInsets.bottom + 8,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: kOcSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kOcBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _compactPickerHandle(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l(context, '模型管理', 'Manage Models'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: kOcText,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: TextField(
                            onChanged: (value) {
                              query = value.trim().toLowerCase();
                              setModalState(() {});
                            },
                            decoration: _compactPickerSearchDecoration(
                              context,
                              hint: l(context, '过滤模型…', 'Filter models…'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            children: grouped.entries.map((entry) {
                            final provider = entry.key;
                            final models = entry.value;
                            final allVisible = models.every(
                              (item) => _isModelVisible(config, item),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          provider.name,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: kOcText,
                                          ),
                                        ),
                                      ),
                                      Switch.adaptive(
                                        value: allVisible,
                                        onChanged: (value) async {
                                          for (final item in models) {
                                            await widget.controller.setModelVisibility(
                                              providerId: item.providerId,
                                              modelId: item.id,
                                              visible: value,
                                            );
                                          }
                                          if (!mounted) return;
                                          setModalState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: kOcBorder),
                                    ),
                                    child: Column(
                                      children: models.map((item) {
                                        final visible = _isModelVisible(config, item);
                                        return SwitchListTile.adaptive(
                                          value: visible,
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          title: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              if (_modelChoiceIsFree(item)) ...[
                                                const SizedBox(width: 6),
                                                OcModelTag(
                                                  label: l(context, '免费', 'Free'),
                                                ),
                                              ],
                                              if (_modelChoiceIsLatest(item)) ...[
                                                const SizedBox(width: 6),
                                                OcModelTag(
                                                  label:
                                                      l(context, '最新', 'Latest'),
                                                ),
                                              ],
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              item.id,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: kOcMuted,
                                              ),
                                            ),
                                          ),
                                          onChanged: (value) async {
                                            await widget.controller.setModelVisibility(
                                              providerId: item.providerId,
                                              modelId: item.id,
                                              visible: value,
                                            );
                                            if (!mounted) return;
                                            setModalState(() {});
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }

  /// OpenCode 风格：选择要连接的 provider，而不是直接切当前 provider。
  Future<void> _openProviderPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            bool matchesPreset(_ProviderPreset item) {
              if (query.isEmpty) return true;
              final q = query;
              return item.name.toLowerCase().contains(q) ||
                  item.id.toLowerCase().contains(q) ||
                  item.baseUrl.toLowerCase().contains(q);
            }
            final sourceProviders = _allProviderPresets(state: state);
            final popularItems = sourceProviders
                .where((item) => item.popular && matchesPreset(item))
                .toList()
              ..sort((a, b) {
                final rankCompare =
                    _providerSortRank(a.id).compareTo(_providerSortRank(b.id));
                if (rankCompare != 0) return rankCompare;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });
            final otherItems = sourceProviders
                .where(matchesPreset)
                .where((item) => !item.popular)
                .toList()
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return FractionallySizedBox(
              heightFactor: 0.7,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(context).viewInsets.bottom + 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _compactPickerHandle(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l(context, '连接供应商', 'Connect provider'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                letterSpacing: -0.2,
                                color: kOcText,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        style: const TextStyle(fontSize: 13.5, height: 1.25),
                        onChanged: (value) {
                          query = value.trim().toLowerCase();
                          setModalState(() {});
                        },
                        decoration: _compactPickerSearchDecoration(
                          context,
                          hint: l(context, '过滤…', 'Filter…'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: popularItems.isEmpty && otherItems.isEmpty
                            ? Center(
                                child: Text(
                                  l(context, '没有匹配项', 'No matches'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kOcMuted,
                                  ),
                                ),
                              )
                            : ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TextButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _openCustomProviderSheet(this.context);
                                      },
                                      icon: const Icon(Icons.add_circle_outline),
                                      label: Text(
                                        l(context, '自定义 Provider', 'Custom Provider'),
                                      ),
                                    ),
                                  ),
                                  if (popularItems.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                                      child: Text(
                                        l(context, '热门', 'Popular'),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: kOcMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                  ...popularItems.map(
                                    (item) => Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ProviderListTile(
                                          item: item,
                                          selected: current.connectionFor(item.id) != null,
                                          onTap: () {
                                            Navigator.of(context).pop();
                                            _openConnectPresetProvider(this.context, item);
                                          },
                                        ),
                                        const Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Color(0xFFE4E4E7),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (otherItems.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          4, 10, 4, 6),
                                      child: Text(
                                        l(context, '其他', 'Other'),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: kOcMuted,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    ...otherItems.map(
                                      (item) => Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _ProviderListTile(
                                            item: item,
                                            selected: current.connectionFor(item.id) != null,
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _openConnectPresetProvider(
                                                  this.context, item);
                                            },
                                          ),
                                          const Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: Color(0xFFE4E4E7),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// OpenCode `/models` 风格：分组模型列表，右上保留 `+` 与管理入口。
  Future<void> _openModelPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            final visible = _visibleModelChoices(state);
            final filtered = visible
                .where((item) => _matchesModelQuery(item, query))
                .toList()
              ..sort((a, b) => _compareModelChoices(a, b, state));
            final grouped = <String, List<_ModelChoice>>{};
            for (final item in filtered) {
              grouped.putIfAbsent(item.providerId, () => []).add(item);
            }
            return FractionallySizedBox(
              heightFactor: 0.64,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(context).viewInsets.bottom + 8,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: kOcSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kOcBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _compactPickerHandle(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l(context, '模型', 'Models'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    letterSpacing: -0.2,
                                    color: kOcText,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: l(
                                    context, '连接供应商', 'Connect provider'),
                                icon: const Icon(Icons.add, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _openProviderPicker(this.context);
                                },
                              ),
                              IconButton(
                                tooltip:
                                    l(context, '模型管理', 'Manage models'),
                                icon: const Icon(Icons.tune_rounded, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _openManageModelsSheet(this.context);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                          child: TextField(
                            style: const TextStyle(
                                fontSize: 13.5, height: 1.25),
                            onChanged: (value) {
                              query = value.trim().toLowerCase();
                              setModalState(() {});
                            },
                            decoration: _compactPickerSearchDecoration(
                              context,
                              hint: l(context, '过滤模型…', 'Filter models…'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: Text(
                                      visible.isEmpty
                                          ? l(
                                              context,
                                              '还没有可见模型，请先连接供应商或在模型管理中开启模型。',
                                              'No visible models yet. Connect a provider or enable models in Manage Models.',
                                            )
                                          : l(context, '没有匹配的模型',
                                              'No matching models'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: kOcMuted,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 0, 12, 12),
                                  children: grouped.entries.map((entry) {
                                    final providerId = entry.key;
                                    final items = entry.value;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                4, 4, 4, 6),
                                            child: Text(
                                              _providerLabel(
                                                providerId,
                                                config: current,
                                                state: state,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: kOcMuted,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: kOcBorder),
                                            ),
                                            child: Column(
                                              children: [
                                                for (var i = 0;
                                                    i < items.length;
                                                    i++) ...[
                                                  _ModelListTile(
                                                    item: items[i],
                                                    selected: current
                                                                .provider ==
                                                            items[i]
                                                                .providerId &&
                                                        current.model ==
                                                            items[i].id,
                                                    onTap: () => _selectModel(
                                                        items[i]),
                                                  ),
                                                  if (i != items.length - 1)
                                                    const Divider(
                                                      height: 1,
                                                      thickness: 1,
                                                      color: Color(0xFFE4E4E7),
                                                    ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
