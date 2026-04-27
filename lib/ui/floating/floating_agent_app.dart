import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/models.dart';
import '../../sdk/local_server_client.dart';
import '../i18n.dart';
import '../oc_theme.dart';

class FloatingAgentApp extends StatelessWidget {
  const FloatingAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const _FloatingAgentPage(),
    );
  }
}

class _FloatingConfig {
  const _FloatingConfig({
    required this.serverUri,
    required this.sessionId,
    required this.sessionTitle,
    required this.workspaceId,
    required this.workspaceName,
    required this.workspaceDirectory,
    required this.darkMode,
  });

  final Uri serverUri;
  final String sessionId;
  final String sessionTitle;
  final String workspaceId;
  final String workspaceName;
  final String workspaceDirectory;
  final bool darkMode;

  factory _FloatingConfig.fromJson(Map<dynamic, dynamic> json) {
    return _FloatingConfig(
      serverUri: Uri.parse(json['serverUri'] as String? ?? ''),
      sessionId: json['sessionId'] as String? ?? '',
      sessionTitle: json['sessionTitle'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      workspaceName: json['workspaceName'] as String? ?? '',
      workspaceDirectory: json['workspaceDirectory'] as String? ?? '',
      darkMode: json['darkMode'] as bool? ?? false,
    );
  }
}

class _FloatingAgentPage extends StatefulWidget {
  const _FloatingAgentPage();

  @override
  State<_FloatingAgentPage> createState() => _FloatingAgentPageState();
}

class _FloatingAgentPageState extends State<_FloatingAgentPage> {
  static const MethodChannel _channel =
      MethodChannel('mobile_agent/floating_window_view');

  _FloatingConfig? _config;
  LocalServerClient? _client;
  List<SessionMessageBundle> _messages = const [];
  SessionRunStatus _status = const SessionRunStatus.idle();
  StreamSubscription<ServerEvent>? _events;
  Timer? _refreshDebounce;
  Object? _error;
  bool _loading = true;
  bool _collapsed = false;
  // Use system brightness as the initial value so there's no light→dark flash
  // before the config (which carries the host app's ThemeMode) is loaded.
  bool _darkMode =
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _events?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getInitialState',
      );
      final config = _FloatingConfig.fromJson(raw ?? const {});
      final client = LocalServerClient(config.serverUri);
      setState(() {
        _config = config;
        _client = client;
        _darkMode = config.darkMode;
      });
      await _refreshAll();
      _events = client
          .globalEvents(directory: config.workspaceDirectory)
          .listen(_handleEvent, onError: (error) {
        if (mounted) setState(() => _error = error);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    final config = _config;
    final client = _client;
    if (config == null || client == null || config.sessionId.isEmpty) return;
    try {
      final results = await Future.wait<dynamic>([
        client.listSessionMessages(config.sessionId),
        if (config.workspaceId.isNotEmpty)
          client.listSessionStatuses(config.workspaceId)
        else
          Future<Map<String, SessionRunStatus>>.value(const {}),
      ]);
      final statuses = results[1] as Map<String, SessionRunStatus>;
      if (!mounted) return;
      setState(() {
        _messages = results[0] as List<SessionMessageBundle>;
        _status = statuses[config.sessionId] ?? _status;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _handleEvent(ServerEvent event) {
    final config = _config;
    if (config == null) return;
    final sessionId = event.properties['sessionID'] as String?;
    if (sessionId != null && sessionId != config.sessionId) return;
    if (event.type == 'session.status') {
      setState(() {
        _status = SessionRunStatus.fromJson(
          Map<String, dynamic>.from(event.properties),
        );
      });
      return;
    }
    if (event.type == 'message.updated' ||
        event.type == 'message.part.updated' ||
        event.type == 'message.part.delta' ||
        event.type == 'session.updated') {
      _scheduleRefresh();
    }
    if (event.type == 'session.deleted') {
      setState(() {
        _status = const SessionRunStatus.idle();
        _messages = const [];
      });
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), _refreshAll);
  }

  Future<void> _openMainApp() async {
    await _channel.invokeMethod<void>('openMainApp');
  }

  Future<void> _close() async {
    await _channel.invokeMethod<void>('closeFloatingWindow');
  }

  Future<void> _setCollapsed(bool value) async {
    setState(() => _collapsed = value);
    await _channel.invokeMethod<void>('setCollapsed', {'collapsed': value});
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Theme(
      data: _darkMode ? buildDarkTheme() : buildLightTheme(),
      child: Builder(
        builder: (context) {
          final oc = context.oc;
          // Material is transparent so the ClipRRect rounded corners show
          // through to the OS background layer.  The Container inside supplies
          // the solid page background for the visible area.
          return Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                decoration: BoxDecoration(
                  color: oc.pageBackground,
                  border: Border.all(color: oc.borderColor),
                ),
                child: Column(
                  children: [
                    _FloatingHeader(
                      title: config?.sessionTitle ??
                          l(context, 'Mag 小窗', 'Mag Floating'),
                      subtitle: config?.workspaceName ?? '',
                      status: _status,
                      collapsed: _collapsed,
                      onOpen: _openMainApp,
                      onClose: _close,
                      onToggleCollapsed: () => _setCollapsed(!_collapsed),
                    ),
                    if (!_collapsed)
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _FloatingTimeline(
                                messages: _messages,
                                status: _status,
                                error: _error,
                                onOpenMainApp: _openMainApp,
                              ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FloatingHeader extends StatelessWidget {
  const _FloatingHeader({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.collapsed,
    required this.onOpen,
    required this.onClose,
    required this.onToggleCollapsed,
  });

  final String title;
  final String subtitle;
  final SessionRunStatus status;
  final bool collapsed;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: oc.panelBackground,
        border: Border(bottom: BorderSide(color: oc.borderColor)),
      ),
      child: Row(
        children: [
          if (status.isBusy)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.smart_toy_outlined, size: 16, color: oc.foregroundMuted),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty
                        ? l(context, '当前会话', 'Current session')
                        : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _statusLabel(context, status, subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: oc.foregroundMuted),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: collapsed
                ? l(context, '展开', 'Expand')
                : l(context, '收起', 'Collapse'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: onToggleCollapsed,
            icon: Icon(
              collapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 19,
            ),
          ),
          IconButton(
            tooltip: l(context, '回到 Mag', 'Open Mag'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_full_rounded, size: 17),
          ),
          IconButton(
            tooltip: l(context, '关闭', 'Close'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  String _statusLabel(
    BuildContext context,
    SessionRunStatus status,
    String subtitle,
  ) {
    if (status.isRetrying) {
      return status.message ?? l(context, '正在重试', 'Retrying');
    }
    if (status.isCompacting) return l(context, '正在压缩上下文', 'Compacting context');
    if (status.isBusy) return l(context, 'Agent 运行中', 'Agent is running');
    if (status.hasError) return status.message!;
    return subtitle.isEmpty
        ? l(context, '点击回到 Mag', 'Tap to open Mag')
        : subtitle;
  }
}

class _FloatingTimeline extends StatelessWidget {
  const _FloatingTimeline({
    required this.messages,
    required this.status,
    required this.error,
    required this.onOpenMainApp,
  });

  final List<SessionMessageBundle> messages;
  final SessionRunStatus status;
  final Object? error;
  final VoidCallback onOpenMainApp;

  @override
  Widget build(BuildContext context) {
    if (error != null && messages.isEmpty) {
      return _StateMessage(
        icon: Icons.error_outline_rounded,
        text: error.toString(),
        onTap: onOpenMainApp,
      );
    }
    if (messages.isEmpty) {
      return _StateMessage(
        icon: status.isBusy ? Icons.hourglass_top_rounded : Icons.chat_outlined,
        text: status.isBusy
            ? l(context, 'Agent 正在准备回复…', 'Agent is preparing a reply...')
            : l(context, '还没有消息', 'No messages yet'),
        onTap: onOpenMainApp,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      itemCount: messages.length + (status.isBusy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 4),
            child: _FloatingRunningIndicator(),
          );
        }
        return _FloatingMessageCard(bundle: messages[index]);
      },
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: oc.foregroundMuted),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: oc.foregroundMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingMessageCard extends StatelessWidget {
  const _FloatingMessageCard({required this.bundle});

  final SessionMessageBundle bundle;

  @override
  Widget build(BuildContext context) {
    final message = bundle.message;
    final isUser = message.role == SessionRole.user;
    final oc = context.oc;
    final parts = _visibleParts(bundle);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isUser ? oc.userBubble : oc.panelBackground,
          border: Border.all(color: oc.borderColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUser
                      ? Icons.person_outline_rounded
                      : Icons.smart_toy_outlined,
                  size: 14,
                  color: oc.foregroundMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  isUser ? l(context, '你', 'You') : message.agent,
                  style: TextStyle(
                    fontSize: 11,
                    color: oc.foregroundMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (message.text.trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              _MarkdownBlock(text: message.text),
            ],
            for (final part in parts) ...[
              const SizedBox(height: 7),
              _FloatingPartView(part: part),
            ],
          ],
        ),
      ),
    );
  }

  List<MessagePart> _visibleParts(SessionMessageBundle bundle) {
    return bundle.parts.where((part) {
      if (bundle.message.role == SessionRole.user &&
          part.type == PartType.text) {
        return false;
      }
      if (part.type == PartType.stepStart) return false;
      return true;
    }).toList(growable: false);
  }
}

class _FloatingPartView extends StatelessWidget {
  const _FloatingPartView({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    switch (part.type) {
      case PartType.text:
        return _MarkdownBlock(text: part.data['text'] as String? ?? '');
      case PartType.reasoning:
        return _CompactPanel(
          icon: Icons.psychology_alt_outlined,
          title: l(context, '推理', 'Reasoning'),
          child: _MarkdownBlock(text: part.data['text'] as String? ?? ''),
        );
      case PartType.tool:
        return _ToolPanel(part: part);
      case PartType.error:
        return _CompactPanel(
          icon: Icons.error_outline_rounded,
          title: l(context, '错误', 'Error'),
          child: Text(part.data['message'] as String? ?? ''),
        );
      case PartType.file:
      case PartType.patch:
      case PartType.retry:
      case PartType.subtask:
      case PartType.compaction:
      case PartType.approvalRequest:
      case PartType.approvalResult:
      case PartType.stepFinish:
      case PartType.stepStart:
        return _DataPanel(
          title: _partTitle(context, part.type),
          data: part.data,
        );
    }
  }

  String _partTitle(BuildContext context, PartType type) {
    switch (type) {
      case PartType.file:
        return l(context, '文件', 'File');
      case PartType.patch:
        return l(context, '补丁', 'Patch');
      case PartType.retry:
        return l(context, '重试', 'Retry');
      case PartType.subtask:
        return l(context, '子任务', 'Subtask');
      case PartType.compaction:
        return l(context, '上下文压缩', 'Compaction');
      case PartType.approvalRequest:
        return l(context, '等待确认', 'Approval needed');
      case PartType.approvalResult:
        return l(context, '确认结果', 'Approval result');
      case PartType.stepFinish:
        return l(context, '步骤完成', 'Step finished');
      default:
        return type.name;
    }
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final state =
        Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
    final tool = part.data['tool'] as String? ?? l(context, '工具', 'Tool');
    final status = state['status'] as String? ?? 'pending';
    final title = state['title'] as String? ?? tool;
    final output =
        (state['displayOutput'] as String?) ?? (state['output'] as String?);
    final input = Map<String, dynamic>.from(state['input'] as Map? ?? const {});
    return _CompactPanel(
      icon: _toolIcon(status),
      title: '$title · $status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (input.isNotEmpty) _MonoText(_prettyJson(input), maxLines: 5),
          if (output != null && output.trim().isNotEmpty) ...[
            if (input.isNotEmpty) const SizedBox(height: 6),
            _MonoText(output, maxLines: 10),
          ],
        ],
      ),
    );
  }

  IconData _toolIcon(String status) {
    if (status == 'running' || status == 'pending') {
      return Icons.sync_rounded;
    }
    if (status == 'error') return Icons.error_outline_rounded;
    return Icons.build_circle_outlined;
  }
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({
    required this.title,
    required this.data,
  });

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return _CompactPanel(
      icon: Icons.article_outlined,
      title: title,
      child: _MonoText(_prettyJson(data), maxLines: 12),
    );
  }
}

class _CompactPanel extends StatelessWidget {
  const _CompactPanel({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: oc.mutedPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: oc.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: oc.foregroundMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oc.foregroundMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _MarkdownBlock extends StatelessWidget {
  const _MarkdownBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final oc = context.oc;
    return MarkdownBody(
      data: text,
      selectable: false,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(fontSize: 12.5, height: 1.35, color: oc.foreground),
        code: TextStyle(
          fontSize: 11.5,
          fontFamily: 'monospace',
          backgroundColor: oc.mutedPanel,
        ),
        codeblockDecoration: BoxDecoration(
          color: oc.mutedPanel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: oc.borderColor),
        ),
      ),
    );
  }
}

class _MonoText extends StatelessWidget {
  const _MonoText(this.text, {required this.maxLines});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.35,
        color: context.oc.foreground,
      ),
    );
  }
}

class _FloatingRunningIndicator extends StatelessWidget {
  const _FloatingRunningIndicator();

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: oc.mutedPanel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: oc.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            l(context, '运行中', 'Running'),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _prettyJson(Object value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}
