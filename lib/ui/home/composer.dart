part of '../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

enum _ComposerAttachmentSource {
  workspace,
  deviceFile,
  camera,
  microphone,
  video
}

enum _ComposerAttachmentAction {
  chooseImage,
  capturePhoto,
  recordAudio,
  recordVideo,
  workspaceFile,
}

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.id,
    required this.source,
    required this.path,
    required this.name,
    required this.mimeType,
    this.size,
    this.workspaceEntry,
  });

  factory _ComposerAttachment.workspace(WorkspaceEntry entry) {
    final mimeType = entry.mimeType ??
        (entry.isDirectory ? 'application/x-directory' : 'text/plain');
    return _ComposerAttachment(
      id: 'workspace:${entry.path}',
      source: _ComposerAttachmentSource.workspace,
      path: entry.path,
      name: entry.name,
      mimeType: mimeType,
      workspaceEntry: entry,
    );
  }

  factory _ComposerAttachment.localImage(
    DeviceCapabilityFile file, {
    required _ComposerAttachmentSource source,
  }) {
    return _ComposerAttachment(
      id: '${source.name}:${file.path}',
      source: source,
      path: file.path,
      name: file.name,
      mimeType: file.mimeType.isEmpty ? 'image/jpeg' : file.mimeType,
      size: file.size,
    );
  }

  factory _ComposerAttachment.localMedia(
    DeviceCapabilityFile file, {
    required _ComposerAttachmentSource source,
    required String fallbackMimeType,
  }) {
    return _ComposerAttachment(
      id: '${source.name}:${file.path}',
      source: source,
      path: file.path,
      name: file.name,
      mimeType: file.mimeType.isEmpty ? fallbackMimeType : file.mimeType,
      size: file.size,
    );
  }

  final String id;
  final _ComposerAttachmentSource source;
  final String path;
  final String name;
  final String mimeType;
  final int? size;
  final WorkspaceEntry? workspaceEntry;

  String get dedupeKey =>
      source == _ComposerAttachmentSource.camera ? id : '${source.name}:$path';

  bool get isWorkspace => source == _ComposerAttachmentSource.workspace;
  bool get isImage => mimeType.startsWith('image/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isDirectory => workspaceEntry?.isDirectory ?? false;
}

extension _HomePageComposer on _HomePageState {
  void _handlePromptComposerChanged() {
    final match = _currentPromptMentionMatch();
    if (!_promptFocusNode.hasFocus || match == null) {
      _promptMentionDebounce?.cancel();
      if (_activePromptMention != null ||
          _promptMentionSuggestions.isNotEmpty ||
          _promptMentionSearching) {
        setState(() {
          _activePromptMention = null;
          _promptMentionSuggestions = const [];
          _promptMentionSelectedIndex = 0;
          _promptMentionSearching = false;
        });
      }
      return;
    }
    final sameMatch = _activePromptMention != null &&
        _activePromptMention!.start == match.start &&
        _activePromptMention!.end == match.end &&
        _activePromptMention!.query == match.query;
    if (sameMatch) return;
    setState(() {
      _activePromptMention = match;
      _promptMentionSelectedIndex = 0;
      _promptMentionSearching = true;
    });
    _promptMentionDebounce?.cancel();
    _promptMentionDebounce = Timer(const Duration(milliseconds: 120), () async {
      final requestId = ++_promptMentionRequestId;
      final results = await widget.controller.searchWorkspaceEntries(
        query: match.query,
        limit: 8,
      );
      if (!mounted || requestId != _promptMentionRequestId) return;
      final latest = _currentPromptMentionMatch();
      if (latest == null ||
          latest.start != match.start ||
          latest.query != match.query) {
        return;
      }
      setState(() {
        _activePromptMention = latest;
        _promptMentionSuggestions = results;
        _promptMentionSelectedIndex = 0;
        _promptMentionSearching = false;
      });
    });
  }

  _PromptMentionMatch? _currentPromptMentionMatch() {
    final workspace = widget.controller.state.workspace;
    if (workspace == null) return null;
    final value = _promptController.value;
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    final prefix = value.text.substring(0, cursor);
    final atIndex = prefix.lastIndexOf('@');
    if (atIndex < 0) return null;
    if (atIndex > 0) {
      final prev = prefix[atIndex - 1];
      final allowedPrefix = RegExp(r'[\s\(\[\{"]');
      if (!allowedPrefix.hasMatch(prev)) return null;
    }
    final token = prefix.substring(atIndex + 1);
    if (token.contains(RegExp(r'\s'))) return null;
    return _PromptMentionMatch(start: atIndex, end: cursor, query: token);
  }

  void _insertPromptMentionSuggestion(WorkspaceEntry entry) {
    final match = _activePromptMention ?? _currentPromptMentionMatch();
    if (match == null) return;
    final suffix = entry.isDirectory && !entry.path.endsWith('/') ? '/' : '';
    final replacement = '@${entry.path}$suffix ';
    final text = _promptController.text;
    final next = text.replaceRange(match.start, match.end, replacement);
    final cursor = match.start + replacement.length;
    _promptController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _promptMentionDebounce?.cancel();
    setState(() {
      _activePromptMention = null;
      _promptMentionSuggestions = const [];
      _promptMentionSelectedIndex = 0;
      _promptMentionSearching = false;
    });
    _promptFocusNode.requestFocus();
  }

  void _movePromptMentionSelection(int delta) {
    if (_promptMentionSuggestions.isEmpty) return;
    final next = (_promptMentionSelectedIndex + delta)
        .clamp(0, _promptMentionSuggestions.length - 1);
    if (next == _promptMentionSelectedIndex) return;
    setState(() {
      _promptMentionSelectedIndex = next;
    });
  }

  void _confirmPromptMentionSelection() {
    if (_promptMentionSuggestions.isEmpty) return;
    final index = _promptMentionSelectedIndex.clamp(
        0, _promptMentionSuggestions.length - 1);
    _insertPromptMentionSuggestion(_promptMentionSuggestions[index]);
  }

  void _dismissPromptMentionSelection() {
    if (_activePromptMention == null &&
        _promptMentionSuggestions.isEmpty &&
        !_promptMentionSearching) {
      return;
    }
    _promptMentionDebounce?.cancel();
    setState(() {
      _activePromptMention = null;
      _promptMentionSuggestions = const [];
      _promptMentionSelectedIndex = 0;
      _promptMentionSearching = false;
    });
  }

  void _applyVoiceInputText(String transcript) {
    final trimmed = transcript.trim();
    final prefix = _voiceInputPrefix.trimRight();
    final next = trimmed.isEmpty
        ? prefix
        : prefix.isEmpty
            ? trimmed
            : '$prefix\n\n$trimmed';
    _promptController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openVoiceSettingsFromComposer(BuildContext context) {
    return openAppSettingsSheet(
      context,
      controller: widget.controller,
      modelConfig:
          widget.controller.state.modelConfig ?? ModelConfig.defaults(),
      initialDestination: 'voice',
    );
  }

  Future<void> _showVoiceSetupPrompt(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final oc = sheetContext.oc;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              MediaQuery.of(sheetContext).viewInsets.bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: oc.accent
                            .withOpacity(sheetContext.isDarkMode ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.mic_none_rounded, color: oc.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l(sheetContext, '配置语音输入', 'Set up voice input'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: oc.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l(
                    sheetContext,
                    '需要先启用语音输入，并配置 Qwen 或豆包的实时语音凭证。',
                    'Enable voice input and configure Qwen or Doubao realtime voice credentials first.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: oc.foregroundMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: Text(l(sheetContext, '取消', 'Cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_openVoiceSettingsFromComposer(context));
                      },
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: Text(l(sheetContext, '去设置', 'Open settings')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openVoiceInputSheet(BuildContext context) async {
    final voiceState = widget.controller.state;
    if (voiceState.voiceRecording || voiceState.voiceConnecting) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _VoiceInputSheet(
          controller: widget.controller,
          initialPrefix: _voiceInputPrefix,
          initialText: _promptController.text,
          onTranscript: _applyVoiceInputText,
          onOpenSettings: () => _openVoiceSettingsFromComposer(context),
        ),
      );
      return;
    }
    if (!voiceState.voiceConfig.enabled ||
        !voiceState.voiceConfig.selectedProviderConfigured) {
      await _showVoiceSetupPrompt(context);
      return;
    }
    _voiceInputPrefix = _promptController.text;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VoiceInputSheet(
        controller: widget.controller,
        initialPrefix: _voiceInputPrefix,
        initialText: _promptController.text,
        onTranscript: _applyVoiceInputText,
        onOpenSettings: () => _openVoiceSettingsFromComposer(context),
      ),
    );
    _promptFocusNode.requestFocus();
  }

  Future<void> _openAttachmentActions(BuildContext context) async {
    final action = await showModalBottomSheet<_ComposerAttachmentAction>(
      context: context,
      builder: (sheetContext) {
        final oc = sheetContext.oc;
        Widget tile({
          required IconData icon,
          required String title,
          required String subtitle,
          required _ComposerAttachmentAction action,
        }) {
          return ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: oc.composerOptionBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.fromBorderSide(
                  BorderSide(color: oc.softBorderColor),
                ),
              ),
              child: Icon(icon, size: 18, color: oc.foreground),
            ),
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: () => Navigator.of(sheetContext).pop(action),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: oc.borderColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                tile(
                  icon: Icons.image_outlined,
                  title: l(sheetContext, '选择图片', 'Choose image'),
                  subtitle: l(sheetContext, '从设备相册或文件中选择图片',
                      'Pick images from this device'),
                  action: _ComposerAttachmentAction.chooseImage,
                ),
                tile(
                  icon: Icons.photo_camera_outlined,
                  title: l(sheetContext, '拍照', 'Take photo'),
                  subtitle: l(sheetContext, '打开相机拍摄一张图片',
                      'Open the camera and attach a photo'),
                  action: _ComposerAttachmentAction.capturePhoto,
                ),
                tile(
                  icon: Icons.mic_none_rounded,
                  title: l(sheetContext, '录音', 'Record audio'),
                  subtitle: l(sheetContext, '录制一段音频作为附件',
                      'Record an audio clip and attach it'),
                  action: _ComposerAttachmentAction.recordAudio,
                ),
                tile(
                  icon: Icons.videocam_outlined,
                  title: l(sheetContext, '录制视频', 'Record video'),
                  subtitle: l(sheetContext, '录制一段视频作为附件',
                      'Record a video clip and attach it'),
                  action: _ComposerAttachmentAction.recordVideo,
                ),
                tile(
                  icon: Icons.folder_outlined,
                  title: l(sheetContext, '工作区文件', 'Workspace file'),
                  subtitle: l(sheetContext, '选择项目里的文件作为附件',
                      'Attach files from the current workspace'),
                  action: _ComposerAttachmentAction.workspaceFile,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    final currentContext = this.context;
    switch (action) {
      case _ComposerAttachmentAction.chooseImage:
        await _pickPromptImages(currentContext);
        break;
      case _ComposerAttachmentAction.capturePhoto:
        await _capturePromptPhoto(currentContext);
        break;
      case _ComposerAttachmentAction.recordAudio:
        await _recordPromptAudio(currentContext);
        break;
      case _ComposerAttachmentAction.recordVideo:
        await _recordPromptVideo(currentContext);
        break;
      case _ComposerAttachmentAction.workspaceFile:
        await _openPromptAttachmentPicker(currentContext);
        break;
    }
  }

  Future<void> _pickPromptImages(BuildContext context) async {
    if (!DeviceCapabilityBridge.isSupported) {
      _showInfo(
        context,
        l(context, '当前平台暂不支持选择设备图片',
            'Choosing device images is not supported on this platform.'),
      );
      return;
    }
    try {
      final files = await DeviceCapabilityBridge.pickFiles(
        accept: 'image/*',
        multiple: true,
      );
      final attachments = files
          .where((file) => file.mimeType.startsWith('image/'))
          .map(
            (file) => _ComposerAttachment.localImage(
              file,
              source: _ComposerAttachmentSource.deviceFile,
            ),
          )
          .toList();
      if (attachments.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _promptAttachments = _mergePromptAttachments([
          ..._promptAttachments,
          ...attachments,
        ]);
      });
    } catch (error) {
      if (!mounted || !context.mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _capturePromptPhoto(BuildContext context) async {
    if (!DeviceCapabilityBridge.isSupported) {
      _showInfo(
        context,
        l(context, '当前平台暂不支持拍照附件',
            'Camera attachments are not supported on this platform.'),
      );
      return;
    }
    try {
      final file = await DeviceCapabilityBridge.capturePhoto();
      if (file == null) return;
      final attachment = _ComposerAttachment.localImage(
        file,
        source: _ComposerAttachmentSource.camera,
      );
      if (!mounted) return;
      setState(() {
        _promptAttachments = _mergePromptAttachments([
          ..._promptAttachments,
          attachment,
        ]);
      });
    } catch (error) {
      if (!mounted || !context.mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _recordPromptAudio(BuildContext context) async {
    if (!DeviceCapabilityBridge.isSupported) {
      _showInfo(
        context,
        l(context, '当前平台暂不支持录音附件',
            'Audio recording attachments are not supported on this platform.'),
      );
      return;
    }
    try {
      final file = await DeviceCapabilityBridge.recordAudio();
      if (file == null) return;
      final attachment = _ComposerAttachment.localMedia(
        file,
        source: _ComposerAttachmentSource.microphone,
        fallbackMimeType: 'audio/m4a',
      );
      if (!mounted) return;
      setState(() {
        _promptAttachments = _mergePromptAttachments([
          ..._promptAttachments,
          attachment,
        ]);
      });
    } catch (error) {
      if (!mounted || !context.mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _recordPromptVideo(BuildContext context) async {
    if (!DeviceCapabilityBridge.isSupported) {
      _showInfo(
        context,
        l(context, '当前平台暂不支持视频附件',
            'Video recording attachments are not supported on this platform.'),
      );
      return;
    }
    try {
      final file = await DeviceCapabilityBridge.recordVideo();
      if (file == null) return;
      final attachment = _ComposerAttachment.localMedia(
        file,
        source: _ComposerAttachmentSource.video,
        fallbackMimeType: 'video/mp4',
      );
      if (!mounted) return;
      setState(() {
        _promptAttachments = _mergePromptAttachments([
          ..._promptAttachments,
          attachment,
        ]);
      });
    } catch (error) {
      if (!mounted || !context.mounted) return;
      _showInfo(context, error.toString());
    }
  }

  List<_ComposerAttachment> _mergePromptAttachments(
    Iterable<_ComposerAttachment> attachments,
  ) {
    final seen = <String>{};
    final out = <_ComposerAttachment>[];
    for (final attachment in attachments) {
      if (seen.add(attachment.dedupeKey)) {
        out.add(attachment);
      }
    }
    return out;
  }

  Future<void> _openPromptAttachmentPicker(BuildContext context) async {
    final workspace = widget.controller.state.workspace;
    if (workspace == null) {
      _showInfo(
        context,
        l(context, '请先选择工作区', 'Please select a workspace first.'),
      );
      return;
    }
    final initial = <String, WorkspaceEntry>{
      for (final attachment in _promptAttachments)
        if (attachment.workspaceEntry != null)
          attachment.workspaceEntry!.path: attachment.workspaceEntry!,
    };
    final selected = await showModalBottomSheet<List<WorkspaceEntry>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final queryController = TextEditingController();
        final selectedMap = <String, WorkspaceEntry>{...initial};
        var results = <WorkspaceEntry>[];
        var loading = true;
        var requestId = 0;

        Future<void> loadResults(
            StateSetter setModalState, String query) async {
          final current = ++requestId;
          setModalState(() => loading = true);
          final found = await widget.controller.searchWorkspaceEntries(
            query: query,
            limit: 40,
          );
          if (current != requestId) return;
          setModalState(() {
            results = found.where((item) => !item.isDirectory).toList();
            loading = false;
          });
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (loading && results.isEmpty && requestId == 0) {
              unawaited(loadResults(setModalState, ''));
            }
            return FractionallySizedBox(
              heightFactor: 0.82,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l(context, '添加附件', 'Add attachments'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: queryController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText:
                              l(context, '搜索工作区文件', 'Search workspace files'),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          unawaited(loadResults(setModalState, value));
                        },
                      ),
                      const SizedBox(height: 12),
                      if (selectedMap.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: selectedMap.values
                              .map(
                                (entry) => InputChip(
                                  label: Text(
                                    entry.path,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onDeleted: () {
                                    setModalState(() {
                                      selectedMap.remove(entry.path);
                                    });
                                  },
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: loading && results.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : results.isEmpty
                                ? Center(
                                    child: Text(
                                      l(context, '没有匹配文件', 'No matching files'),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: results.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final entry = results[index];
                                      final selected =
                                          selectedMap.containsKey(entry.path);
                                      return ListTile(
                                        dense: true,
                                        leading: Icon(
                                          (entry.mimeType ?? '')
                                                  .startsWith('image/')
                                              ? Icons.image_outlined
                                              : (entry.mimeType ==
                                                      'application/pdf')
                                                  ? Icons
                                                      .picture_as_pdf_outlined
                                                  : Icons.description_outlined,
                                        ),
                                        title: Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          entry.path,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: Icon(
                                          selected
                                              ? Icons.check_circle
                                              : Icons.add_circle_outline,
                                          color: selected
                                              ? context.oc.accent
                                              : context.oc.foregroundHint,
                                        ),
                                        onTap: () {
                                          setModalState(() {
                                            if (selected) {
                                              selectedMap.remove(entry.path);
                                            } else {
                                              selectedMap[entry.path] = entry;
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l(context, '取消', 'Cancel')),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pop(selectedMap.values.toList()),
                            child: Text(l(context, '完成', 'Done')),
                          ),
                        ],
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
    if (!mounted || selected == null) return;
    setState(() {
      final localAttachments = _promptAttachments
          .where((attachment) => !attachment.isWorkspace)
          .toList();
      _promptAttachments = _mergePromptAttachments([
        ...localAttachments,
        ...selected.map(_ComposerAttachment.workspace),
      ]);
    });
  }

  Future<List<JsonMap>> _buildPromptParts({
    required WorkspaceInfo workspace,
    required String text,
  }) async {
    final parts = <JsonMap>[];
    if (text.isNotEmpty) {
      parts.add({
        'type': PartType.text.name,
        'text': text,
      });
    }
    for (final entry in _promptAttachments) {
      final mime = entry.mimeType;
      final source = <String, dynamic>{
        'type': 'file',
        'origin': entry.source.name,
        'path': entry.path,
        if (entry.size != null) 'size': entry.size,
      };
      final base = <String, dynamic>{
        'type': PartType.file.name,
        'mime': mime,
        'filename': entry.name,
        'path': entry.path,
        'url': entry.path,
        'source': source,
      };
      if (mime.startsWith('image/') ||
          mime.startsWith('audio/') ||
          mime.startsWith('video/') ||
          mime == 'application/pdf') {
        final bytes = entry.isWorkspace
            ? await widget.controller.loadWorkspaceBytes(
                treeUri: workspace.treeUri,
                relativePath: entry.path,
              )
            : await File(entry.path).readAsBytes();
        base['url'] = 'data:$mime;base64,${base64Encode(bytes)}';
      } else if (mime == 'text/plain' ||
          mime == 'text/markdown' ||
          mime == 'text/html' ||
          mime == 'application/json' ||
          mime == 'application/x-directory') {
        final content = entry.isDirectory
            ? 'Directory: ${entry.path}'
            : entry.isWorkspace
                ? await widget.controller.loadWorkspaceText(
                    treeUri: workspace.treeUri,
                    relativePath: entry.path,
                  )
                : await File(entry.path).readAsString();
        source['text'] = {
          'value': content,
          'start': 0,
          'end': content.length,
        };
      }
      parts.add(base);
    }
    return parts;
  }

  bool _currentModelSupportsImageInput(AppState state) {
    final modalities =
        state.modelConfig?.currentModelModalities?.input ?? const <String>[];
    return modalities.any((item) => item.toLowerCase() == 'image');
  }

  String _attachmentSourceLabel(
    BuildContext context,
    _ComposerAttachment attachment,
  ) {
    switch (attachment.source) {
      case _ComposerAttachmentSource.workspace:
        return l(context, '工作区', 'Workspace');
      case _ComposerAttachmentSource.deviceFile:
        return l(context, '相册', 'Device');
      case _ComposerAttachmentSource.camera:
        return l(context, '拍照', 'Camera');
      case _ComposerAttachmentSource.microphone:
        return l(context, '录音', 'Recording');
      case _ComposerAttachmentSource.video:
        return l(context, '视频', 'Video');
    }
  }

  IconData _attachmentIcon(_ComposerAttachment attachment) {
    if (attachment.isImage) return Icons.image_outlined;
    if (attachment.isAudio) return Icons.audio_file_outlined;
    if (attachment.isVideo) return Icons.video_file_outlined;
    if (attachment.mimeType == 'application/pdf') {
      return Icons.picture_as_pdf_outlined;
    }
    if (attachment.isDirectory) return Icons.folder_outlined;
    return Icons.attach_file;
  }

  Widget _buildPromptAttachmentChip(
    BuildContext context,
    _ComposerAttachment attachment,
  ) {
    final oc = context.oc;
    final label = _attachmentSourceLabel(context, attachment);
    return InputChip(
      label: Text(
        '${attachment.name} · $label',
        overflow: TextOverflow.ellipsis,
      ),
      avatar: Icon(
        _attachmentIcon(attachment),
        size: 16,
        color: oc.foregroundMuted,
      ),
      onDeleted: () {
        setState(() {
          _promptAttachments = _promptAttachments
              .where((item) => item.id != attachment.id)
              .toList();
        });
      },
    );
  }

  Widget _buildComposerDock(
      BuildContext context, AppState state, bool isKeyboardOpen) {
    final oc = context.oc;
    final currentModel = state.modelConfig ?? ModelConfig.defaults();
    final currentModelChoice = _findModelChoice(
      currentModel.provider,
      currentModel.model,
      config: currentModel,
    );
    final variantOptions = _currentPromptVariantOptions(state);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
              10, isKeyboardOpen ? 4 : 5, 10, isKeyboardOpen ? 6 : 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.permissions.isNotEmpty || state.questions.isNotEmpty)
                Builder(
                  builder: (context) {
                    final h = MediaQuery.of(context).size.height;
                    final tall = state.questions.isNotEmpty;
                    final maxH = tall
                        ? (isKeyboardOpen ? h * 0.44 : h * 0.58)
                            .clamp(240.0, 560.0)
                        : (isKeyboardOpen ? 120.0 : 168.0);
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxH),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          children: [
                            if (state.permissions.isNotEmpty)
                              _PermissionPanel(
                                  controller: widget.controller, state: state),
                            if (state.questions.isNotEmpty)
                              _QuestionPanel(
                                  controller: widget.controller, state: state),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              SizedBox(height: isKeyboardOpen ? 4 : 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activePromptMention != null &&
                      (_promptMentionSearching ||
                          _promptMentionSuggestions.isNotEmpty)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: oc.composerOptionBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: oc.softBorderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                              child: Row(
                                children: [
                                  Icon(Icons.alternate_email,
                                      size: 15, color: oc.foregroundHint),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _activePromptMention!.query.isEmpty
                                          ? l(context, '引用工作区文件或目录',
                                              'Reference workspace files or folders')
                                          : l(
                                              context,
                                              '搜索 "${_activePromptMention!.query}"',
                                              'Search "${_activePromptMention!.query}"',
                                            ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              color: oc.foregroundHint,
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (_promptMentionSearching)
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: oc.foregroundHint,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: _promptMentionSuggestions.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 4, 12, 12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          l(context, '没有匹配结果',
                                              'No matches found'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: oc.foregroundMuted),
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding:
                                          const EdgeInsets.fromLTRB(6, 0, 6, 6),
                                      shrinkWrap: true,
                                      itemCount:
                                          _promptMentionSuggestions.length,
                                      separatorBuilder: (_, __) => Divider(
                                          height: 1, color: oc.softBorderColor),
                                      itemBuilder: (context, index) {
                                        final entry =
                                            _promptMentionSuggestions[index];
                                        final selected = index ==
                                            _promptMentionSelectedIndex;
                                        final fullPath = entry.path +
                                            (entry.isDirectory &&
                                                    !entry.path.endsWith('/')
                                                ? '/'
                                                : '');
                                        final itemName = entry.isDirectory
                                            ? entry.name
                                                .replaceAll(RegExp(r'/+$'), '')
                                            : entry.name;
                                        return InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () =>
                                              _insertPromptMentionSuggestion(
                                                  entry),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 10),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? oc.selectedFill
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 8),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    entry.isDirectory
                                                        ? Icons.folder_outlined
                                                        : Icons
                                                            .description_outlined,
                                                    size: 16,
                                                    color: selected
                                                        ? oc.accent
                                                        : oc.foregroundHint,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          itemName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color:
                                                                oc.foreground,
                                                            fontSize: 13,
                                                            height: 1.25,
                                                            fontWeight: selected
                                                                ? FontWeight
                                                                    .w600
                                                                : FontWeight
                                                                    .w400,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          fullPath,
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                                  fontSize:
                                                                      11.5,
                                                                  color: oc
                                                                      .foregroundMuted),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          entry.isDirectory
                                                              ? l(context, '目录',
                                                                  'Directory')
                                                              : l(context, '文件',
                                                                  'File'),
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .labelSmall
                                                              ?.copyWith(
                                                                  color: oc
                                                                      .foregroundMuted),
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
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: isKeyboardOpen
                        ? const SizedBox.shrink()
                        : Padding(
                            key: const ValueKey('composer-tools'),
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                            child: SingleChildScrollView(
                              clipBehavior: Clip.none,
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _PromptTrayButton(
                                    icon: Icons.psychology_outlined,
                                    label: _selectedAgent ??
                                        state.session?.agent ??
                                        'build',
                                    onTap: () => _openAgentPicker(context),
                                  ),
                                  const SizedBox(width: 6),
                                  _PromptTrayButton(
                                    icon: Icons.auto_awesome_outlined,
                                    label: currentModelChoice?.name ??
                                        currentModel.model,
                                    onTap: () => _openModelChooser(context),
                                  ),
                                  if (variantOptions.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    _PromptTrayButton(
                                      icon: Icons.tune_outlined,
                                      label: _variantTrayLabel(context, state),
                                      onTap: () => _openVariantPicker(context),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                                  _PromptTrayButton(
                                    icon: Icons.settings_outlined,
                                    label: l(context, '选项', 'Options'),
                                    onTap: () =>
                                        _openComposerOptionsSheet(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  if (_promptAttachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_promptAttachments.any((item) => item.isImage) &&
                              !_currentModelSupportsImageInput(state)) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(
                                    context.isDarkMode ? 0.12 : 0.09),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.24),
                                ),
                              ),
                              child: Text(
                                l(
                                  context,
                                  '当前模型可能无法读取图片，发送后会自动降级提示。',
                                  'The current model may not read images; unsupported images will degrade to a prompt warning.',
                                ),
                                style: TextStyle(
                                  color: context.isDarkMode
                                      ? Colors.orange.shade200
                                      : Colors.orange.shade800,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _promptAttachments
                                  .map(
                                    (attachment) => _buildPromptAttachmentChip(
                                      context,
                                      attachment,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    decoration: _chatSurfaceDecoration(
                      context,
                      color: oc.panelBackground
                          .withOpacity(context.isDarkMode ? 0.92 : 0.96),
                      radius: 18,
                      accent: _promptFocusNode.hasFocus,
                    ),
                    child: Stack(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(
                                      LogicalKeyboardKey.arrowDown):
                                  _activePromptMention != null
                                      ? () => _movePromptMentionSelection(1)
                                      : () {},
                              const SingleActivator(LogicalKeyboardKey.arrowUp):
                                  _activePromptMention != null
                                      ? () => _movePromptMentionSelection(-1)
                                      : () {},
                              const SingleActivator(LogicalKeyboardKey.tab):
                                  _activePromptMention != null
                                      ? _confirmPromptMentionSelection
                                      : () {},
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  _dismissPromptMentionSelection,
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: TextField(
                                controller: _promptController,
                                focusNode: _promptFocusNode,
                                minLines: 1,
                                maxLines: 10,
                                textAlignVertical: TextAlignVertical.center,
                                textInputAction: TextInputAction.newline,
                                style:
                                    const TextStyle(fontSize: 14, height: 1.32),
                                decoration: InputDecoration(
                                  isDense: true,
                                  isCollapsed: false,
                                  hintText: l(context, '问任何事，输入 @ 引用文件',
                                      'Ask anything, type @ to reference files'),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(
                                    40,
                                    12,
                                    state.session != null ? 130 : 90,
                                    12,
                                  ),
                                  hintStyle: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: oc.foregroundHint,
                                        fontSize: 13.5,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: _CompactIconButton(
                            tooltip: l(context, '附件', 'Attach'),
                            onPressed: () => _openAttachmentActions(context),
                            icon: Icons.add,
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.session != null) ...[
                                _ContextRingButton(
                                  ratio: _contextUsageRatio(
                                    state.session,
                                    currentModel.model,
                                    limit: state.modelConfig?.currentModelLimit,
                                  ),
                                  compacted: state.session?.hasSummary == true,
                                  onPressed: () => _openContextStatsSheet(
                                    context,
                                    session: state.session,
                                    model: currentModel.model,
                                    modelLimit:
                                        state.modelConfig?.currentModelLimit,
                                    onInitializeMemory: state.isBusy
                                        ? null
                                        : widget
                                            .controller.initializeProjectMemory,
                                    onCompactSession: state.isBusy
                                        ? null
                                        : widget.controller.compactSession,
                                    onViewRawContext: state.session == null
                                        ? null
                                        : () {
                                            _openRawContextSheet(
                                              context,
                                              title: l(context, '原始 Context',
                                                  'Raw Context'),
                                              subtitle: l(
                                                context,
                                                '当前会话发给模型的请求 payload',
                                                'Request payload sent to the model for this session',
                                              ),
                                              loader: widget.controller
                                                  .buildCurrentContextPreview,
                                            );
                                          },
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              _CompactIconButton(
                                tooltip: state.voiceRecording
                                    ? l(context, '查看语音输入', 'View voice input')
                                    : state.voiceConnecting
                                        ? l(context, '正在连接语音服务',
                                            'Connecting voice service')
                                        : l(context, '语音输入', 'Voice input'),
                                onPressed: () => _openVoiceInputSheet(context),
                                icon: state.voiceRecording
                                    ? Icons.mic_rounded
                                    : state.voiceConnecting
                                        ? Icons.more_horiz_rounded
                                        : Icons.mic_none_rounded,
                              ),
                              const SizedBox(width: 6),
                              state.isBusy
                                  ? _CompactIconButton(
                                      tooltip: l(context, '停止', 'Stop'),
                                      onPressed: () =>
                                          widget.controller.cancelPrompt(),
                                      icon: Icons.stop_rounded,
                                      iconColor: Colors.red.shade500,
                                    )
                                  : _CompactIconButton(
                                      tooltip: l(context, '发送', 'Send'),
                                      onPressed: () async {
                                        final text =
                                            _promptController.text.trim();
                                        final workspace =
                                            widget.controller.state.workspace;
                                        if (text.isEmpty &&
                                            _promptAttachments.isEmpty) {
                                          return;
                                        }
                                        if (workspace == null) return;
                                        MessageFormat? format;
                                        if (_structuredOutputEnabled) {
                                          try {
                                            final decoded = jsonDecode(
                                                _schemaController.text.trim());
                                            format = MessageFormat.jsonSchema(
                                              schema: Map<String, dynamic>.from(
                                                  decoded as Map),
                                            );
                                          } catch (_) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(l(
                                                        context,
                                                        'Schema 不是合法 JSON 对象',
                                                        'Schema is not a valid JSON object'))),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                        final parts = await _buildPromptParts(
                                          workspace: workspace,
                                          text: text,
                                        );
                                        _promptController.clear();
                                        _promptFocusNode.unfocus();
                                        setState(() {
                                          _promptAttachments = const [];
                                        });
                                        await widget.controller.sendPrompt(
                                          text,
                                          agent: _selectedAgent ??
                                              state.session?.agent,
                                          format: format,
                                          parts: parts,
                                          variant:
                                              _effectiveSelectedVariant(state),
                                        );
                                      },
                                      icon: Icons.arrow_upward_rounded,
                                      iconColor: oc.sendButtonBg,
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSchemaEditor(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l(context, '结构化输出 Schema', 'Structured Output Schema'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _structuredSchemaTemplates.keys
                    .map(
                      (key) => ChoiceChip(
                        label: Text(_schemaTemplateLabels[key] ?? key),
                        selected: _selectedSchemaTemplate == key,
                        onSelected: (_) {
                          setState(() {
                            _selectedSchemaTemplate = key;
                            _schemaController.text =
                                const JsonEncoder.withIndent('  ')
                                    .convert(_structuredSchemaTemplates[key]);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schemaController,
                minLines: 10,
                maxLines: 18,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: l(context, '输入 JSON Schema', 'Enter JSON Schema'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  try {
                    final decoded = jsonDecode(_schemaController.text.trim());
                    Map<String, dynamic>.from(decoded as Map);
                    Navigator.of(context).pop();
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l(context, 'Schema 必须是合法 JSON 对象',
                              'Schema must be a valid JSON object'))),
                    );
                  }
                },
                child: Text(l(context, '完成', 'Done')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openComposerOptionsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.38,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l(context, '选项', 'Options'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ComposerOptionTile(
                    icon: Icons.tune_outlined,
                    title: _structuredOutputEnabled
                        ? l(context, '关闭结构化输出', 'Disable Structured Output')
                        : l(context, '开启结构化输出', 'Enable Structured Output'),
                    subtitle: l(
                      context,
                      '控制是否按 Schema 输出',
                      'Toggle schema-based structured output',
                    ),
                    trailing: _structuredOutputEnabled
                        ? Icon(Icons.check_circle,
                            size: 18, color: context.oc.accent)
                        : null,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() {
                        _structuredOutputEnabled = !_structuredOutputEnabled;
                      });
                    },
                  ),
                  if (_structuredOutputEnabled)
                    _ComposerOptionTile(
                      icon: Icons.data_object,
                      title: l(context, '编辑 Schema', 'Edit Schema'),
                      subtitle: l(
                        context,
                        '配置结构化输出格式',
                        'Configure structured output schema',
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openSchemaEditor(context);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openContextStatsSheet(
    BuildContext context, {
    required SessionInfo? session,
    required String model,
    ProviderModelLimit? modelLimit,
    required VoidCallback? onInitializeMemory,
    required VoidCallback? onCompactSession,
    required VoidCallback? onViewRawContext,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.58,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l(context, '上下文', 'Context'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _contextUsageLabel(session, model,
                                limit: modelLimit),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: context.oc.foregroundMuted),
                          ),
                        ],
                      ),
                    ),
                    _CompactIconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ContextStatsCard(
                  session: session,
                  model: model,
                  modelLimit: modelLimit,
                  onInitializeMemory: onInitializeMemory,
                  onCompactSession: onCompactSession,
                  onViewRawContext: onViewRawContext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openRawContextSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<JsonMap> Function() loader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        child: _RawContextSheet(
          title: title,
          subtitle: subtitle,
          loader: loader,
        ),
      ),
    ),
  );
}

class _RawContextSheet extends StatefulWidget {
  const _RawContextSheet({
    required this.title,
    required this.subtitle,
    required this.loader,
  });

  final String title;
  final String subtitle;
  final Future<JsonMap> Function() loader;

  @override
  State<_RawContextSheet> createState() => _RawContextSheetState();
}

class _RawContextSheetState extends State<_RawContextSheet> {
  String _view = 'payload';
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;

  @override
  void initState() {
    super.initState();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  String _encodeForView(JsonMap payload) {
    Object selected;
    switch (_view) {
      case 'messages':
        selected = payload['messages'] ?? const [];
        break;
      case 'tools':
        selected = payload['tools'] ?? const [];
        break;
      default:
        selected = payload;
        break;
    }
    return const JsonEncoder.withIndent('  ').convert(selected);
  }

  String _viewLabel(BuildContext context, String id) {
    switch (id) {
      case 'messages':
        return l(context, 'messages', 'messages');
      case 'tools':
        return l(context, 'tools', 'tools');
      default:
        return l(context, '完整 payload', 'Full payload');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CompactIconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icons.close,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<JsonMap>(
              future: widget.loader(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: _panelDecoration(context,
                        background: context.oc.shadow,
                        radius: 14,
                        elevated: false),
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        child: Text(
                          snapshot.error.toString(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final payload = snapshot.data ?? <String, dynamic>{};
                final raw = _encodeForView(payload);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: _panelDecoration(context,
                      background: context.oc.shadow,
                      radius: 14,
                      elevated: false),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final view in const [
                            'payload',
                            'messages',
                            'tools'
                          ])
                            ChoiceChip(
                              label: Text(_viewLabel(context, view)),
                              selected: _view == view,
                              onSelected: (_) => setState(() => _view = view),
                            ),
                          _CompactActionButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: raw),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l(
                                        context, '已复制', 'Copied to clipboard')),
                                  ),
                                );
                              }
                            },
                            icon: Icons.copy_all_outlined,
                            label: l(context, '复制', 'Copy'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Scrollbar(
                          controller: _verticalScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _verticalScrollController,
                            child: Scrollbar(
                              controller: _horizontalScrollController,
                              thumbVisibility: true,
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: SelectionArea(
                                  child: Text(
                                    raw,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptTrayButton extends StatelessWidget {
  const _PromptTrayButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 26, maxWidth: 148),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: oc.composerOptionBg.withOpacity(0.74),
          foregroundColor: oc.foreground,
          side: BorderSide(color: oc.softBorderColor),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 26),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: oc.foregroundMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: oc.foreground,
                  letterSpacing: 0.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerOptionTile extends StatelessWidget {
  const _ComposerOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: oc.composerOptionBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.fromBorderSide(
                BorderSide(color: oc.borderColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: oc.panelBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.fromBorderSide(
                      BorderSide(color: oc.borderColor),
                    ),
                  ),
                  child: Icon(icon, size: 17, color: oc.foreground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: oc.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: oc.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: oc.foregroundFaint,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _VoiceSheetPhase {
  idle,
  connecting,
  recording,
  finishing,
  completed,
  error,
}

class _VoiceInputSheet extends StatefulWidget {
  const _VoiceInputSheet({
    required this.controller,
    required this.initialPrefix,
    required this.initialText,
    required this.onTranscript,
    required this.onOpenSettings,
  });

  final AppController controller;
  final String initialPrefix;
  final String initialText;
  final ValueChanged<String> onTranscript;
  final Future<void> Function() onOpenSettings;

  @override
  State<_VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<_VoiceInputSheet> {
  _VoiceSheetPhase _phase = _VoiceSheetPhase.idle;
  String _transcript = '';
  String _lastProviderText = '';
  String? _error;
  bool _startedHere = false;

  VoiceRealtimeConfig get _config => widget.controller.state.voiceConfig;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncControllerState);
    final state = widget.controller.state;
    final prefix = widget.initialPrefix.trimRight();
    final initial = widget.initialText.trim();
    if (initial.isNotEmpty && initial != prefix) {
      _transcript = prefix.isEmpty
          ? initial
          : initial.startsWith(prefix)
              ? initial.substring(prefix.length).trim()
              : '';
    }
    if (state.voiceConnecting) {
      _phase = _VoiceSheetPhase.connecting;
      _startedHere = true;
    } else if (state.voiceRecording) {
      _phase = _VoiceSheetPhase.recording;
      _startedHere = true;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncControllerState);
    if (_startedHere &&
        (widget.controller.state.voiceConnecting ||
            widget.controller.state.voiceRecording)) {
      unawaited(widget.controller.stopVoiceInput());
    }
    super.dispose();
  }

  void _syncControllerState() {
    if (!mounted) return;
    final state = widget.controller.state;
    final voiceError = state.voiceError;
    setState(() {
      if (voiceError != null && voiceError.trim().isNotEmpty) {
        _phase = _VoiceSheetPhase.error;
        _error = voiceError;
      } else if (state.voiceConnecting) {
        _phase = _VoiceSheetPhase.connecting;
      } else if (state.voiceRecording) {
        _phase = _VoiceSheetPhase.recording;
      } else if (_phase == _VoiceSheetPhase.finishing) {
        _phase = _transcript.trim().isEmpty
            ? _VoiceSheetPhase.idle
            : _VoiceSheetPhase.completed;
      }
    });
  }

  String _providerLabel(BuildContext context) {
    switch (_config.provider) {
      case VoiceRealtimeProvider.qwen:
        return 'Qwen ASR Realtime';
      case VoiceRealtimeProvider.doubao:
        return l(context, '豆包 / 火山引擎', 'Doubao / Volcengine');
    }
  }

  String _phaseLabel(BuildContext context) {
    switch (_phase) {
      case _VoiceSheetPhase.idle:
        return l(context, '准备就绪', 'Ready');
      case _VoiceSheetPhase.connecting:
        return l(context, '正在连接', 'Connecting');
      case _VoiceSheetPhase.recording:
        return l(context, '正在听写', 'Listening');
      case _VoiceSheetPhase.finishing:
        return l(context, '正在整理结果', 'Finalizing');
      case _VoiceSheetPhase.completed:
        return l(context, '已完成', 'Completed');
      case _VoiceSheetPhase.error:
        return l(context, '出错了', 'Error');
    }
  }

  IconData _phaseIcon() {
    switch (_phase) {
      case _VoiceSheetPhase.connecting:
        return Icons.sync_rounded;
      case _VoiceSheetPhase.recording:
        return Icons.graphic_eq_rounded;
      case _VoiceSheetPhase.finishing:
        return Icons.auto_fix_high_rounded;
      case _VoiceSheetPhase.completed:
        return Icons.check_rounded;
      case _VoiceSheetPhase.error:
        return Icons.error_outline_rounded;
      case _VoiceSheetPhase.idle:
        return Icons.mic_none_rounded;
    }
  }

  void _handleTranscript(String value) {
    if (!mounted) return;
    final next = _appendTranscriptValue(value);
    if (next == null) return;
    setState(() {
      _transcript = next;
      _error = null;
    });
    widget.onTranscript(_transcript);
  }

  String? _appendTranscriptValue(String value) {
    final incoming = value.trim();
    if (incoming.isEmpty) return null;
    String addition;
    if (_lastProviderText.isEmpty) {
      addition = incoming;
    } else if (incoming.startsWith(_lastProviderText)) {
      addition = incoming.substring(_lastProviderText.length).trimLeft();
    } else if (_lastProviderText.startsWith(incoming)) {
      return null;
    } else {
      addition = incoming;
    }
    _lastProviderText = incoming;
    if (addition.trim().isEmpty) return null;
    return _joinTranscript(_transcript, addition);
  }

  String _joinTranscript(String current, String addition) {
    final left = current.trimRight();
    final right = addition.trimLeft();
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    final last = left.characters.last;
    final first = right.characters.first;
    final needsSpace = RegExp(r'[A-Za-z0-9]').hasMatch(last) &&
        RegExp(r'[A-Za-z0-9]').hasMatch(first);
    return needsSpace ? '$left $right' : '$left$right';
  }

  Future<void> _start() async {
    if (_phase == _VoiceSheetPhase.connecting ||
        _phase == _VoiceSheetPhase.recording ||
        _phase == _VoiceSheetPhase.finishing) {
      return;
    }
    setState(() {
      _phase = _VoiceSheetPhase.connecting;
      _error = null;
      _lastProviderText = '';
    });
    _startedHere = true;
    try {
      await widget.controller.startVoiceInput(onText: _handleTranscript);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _VoiceSheetPhase.error;
        _error = error.toString();
      });
    }
  }

  Future<void> _stop() async {
    if (_phase != _VoiceSheetPhase.recording &&
        _phase != _VoiceSheetPhase.connecting) {
      return;
    }
    setState(() {
      _phase = _VoiceSheetPhase.finishing;
    });
    await widget.controller.stopVoiceInput();
    if (!mounted) return;
    setState(() {
      _phase = _transcript.trim().isEmpty
          ? _VoiceSheetPhase.idle
          : _VoiceSheetPhase.completed;
    });
  }

  void _clear() {
    setState(() {
      _transcript = '';
      _lastProviderText = '';
      _error = null;
      _phase = _VoiceSheetPhase.idle;
    });
    widget.onTranscript('');
  }

  Future<void> _openSettings() async {
    Navigator.of(context).pop();
    await widget.onOpenSettings();
  }

  Widget _buildPulse(BuildContext context) {
    final oc = context.oc;
    final active = _phase == _VoiceSheetPhase.recording;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 52 : 48,
      height: active ? 52 : 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _phase == _VoiceSheetPhase.error
            ? Colors.red.withOpacity(context.isDarkMode ? 0.18 : 0.10)
            : oc.accent.withOpacity(active
                ? (context.isDarkMode ? 0.24 : 0.16)
                : (context.isDarkMode ? 0.16 : 0.09)),
        border: Border.all(
          color: _phase == _VoiceSheetPhase.error
              ? Colors.red.withOpacity(0.55)
              : oc.accent.withOpacity(active ? 0.75 : 0.38),
        ),
      ),
      child: Icon(
        _phaseIcon(),
        color: _phase == _VoiceSheetPhase.error ? Colors.red : oc.accent,
        size: active ? 24 : 22,
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final oc = context.oc;
    final active = _phase == _VoiceSheetPhase.recording;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _settingsSurfaceDecoration(
        context,
        color:
            oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.62 : 0.86),
        radius: 20,
        elevated: false,
        accent: active,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildPulse(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l(context, '语音输入', 'Voice input'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: oc.foreground,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? oc.accent
                                .withOpacity(context.isDarkMode ? 0.20 : 0.12)
                            : oc.panelBackground.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active
                              ? oc.accent.withOpacity(0.45)
                              : oc.softBorderColor,
                        ),
                      ),
                      child: Text(
                        _phaseLabel(context),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? oc.accent : oc.foregroundMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _providerLabel(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oc.foregroundMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.language_rounded,
                        size: 13, color: oc.foregroundFaint),
                    const SizedBox(width: 4),
                    Text(
                      _config.language,
                      style: TextStyle(
                        color: oc.foregroundMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.graphic_eq_rounded,
                        size: 13, color: oc.foregroundFaint),
                    const SizedBox(width: 4),
                    Text(
                      '${_config.sampleRate ~/ 1000}k PCM',
                      style: TextStyle(
                        color: oc.foregroundMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: l(context, '语音设置', 'Voice settings'),
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: oc.panelBackground.withOpacity(0.66),
              side: BorderSide(color: oc.softBorderColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard(BuildContext context, bool configured) {
    final oc = context.oc;
    final empty = _transcript.trim().isEmpty;
    return Container(
      constraints: BoxConstraints(
        minHeight: empty ? 84 : 132,
        maxHeight: 220,
      ),
      padding: const EdgeInsets.all(10),
      decoration: _settingsSurfaceDecoration(
        context,
        color: oc.panelBackground,
        radius: 18,
        elevated: true,
        accent: _phase == _VoiceSheetPhase.recording,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.notes_rounded, size: 16, color: oc.foregroundMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l(context, '转写内容', 'Transcript'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: oc.foregroundMuted,
                  ),
                ),
              ),
              if (!empty)
                Text(
                  '${_transcript.characters.length}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: oc.foregroundFaint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: empty ? 34 : 84,
                maxHeight: 156,
              ),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: oc.composerOptionBg
                      .withOpacity(context.isDarkMode ? 0.42 : 0.58),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: oc.softBorderColor),
                ),
                child: empty
                    ? Center(
                        child: Text(
                          l(
                            context,
                            configured ? '点击“开始说话”' : '请先配置语音 Provider',
                            configured
                                ? 'Tap "Start speaking"'
                                : 'Configure a voice provider first',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: oc.foregroundMuted,
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Text(
                          _transcript,
                          style: TextStyle(
                            color: oc.foreground,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required bool busy,
    required bool configured,
  }) {
    final oc = context.oc;
    final buttonStyle = FilledButton.styleFrom(
      fixedSize: const Size.fromHeight(38),
      minimumSize: const Size(0, 38),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final secondaryStyle = OutlinedButton.styleFrom(
      fixedSize: const Size.fromHeight(38),
      minimumSize: const Size(0, 38),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: oc.softBorderColor),
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: _settingsSurfaceDecoration(
        context,
        color:
            oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.44 : 0.68),
        radius: 18,
        elevated: false,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : _clear,
              style: secondaryStyle,
              child: Text(l(context, '清空', 'Clear')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: !configured
                  ? _openSettings
                  : _phase == _VoiceSheetPhase.recording ||
                          _phase == _VoiceSheetPhase.connecting
                      ? _stop
                      : _phase == _VoiceSheetPhase.finishing
                          ? null
                          : _start,
              style: buttonStyle,
              icon: Icon(
                _phase == _VoiceSheetPhase.recording ||
                        _phase == _VoiceSheetPhase.connecting
                    ? Icons.stop_rounded
                    : Icons.mic_rounded,
                size: 18,
              ),
              label: Text(
                !configured
                    ? l(context, '去设置', 'Open settings')
                    : _phase == _VoiceSheetPhase.recording ||
                            _phase == _VoiceSheetPhase.connecting
                        ? l(context, '停止', 'Stop')
                        : _phase == _VoiceSheetPhase.finishing
                            ? l(context, '整理中', 'Finalizing')
                            : l(context, '开始说话', 'Start speaking'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: secondaryStyle,
              child: Text(l(context, '完成', 'Done')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final busy = _phase == _VoiceSheetPhase.connecting ||
        _phase == _VoiceSheetPhase.recording ||
        _phase == _VoiceSheetPhase.finishing;
    final configured = _config.enabled && _config.selectedProviderConfigured;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          14,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return Container(
              decoration: _settingsSurfaceDecoration(
                context,
                color: oc.panelBackground,
                radius: 28,
                elevated: true,
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: oc.borderColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildStatusCard(context),
                  const SizedBox(height: 12),
                  _buildTranscriptCard(context, configured),
                  if (_error != null && _error!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red
                            .withOpacity(context.isDarkMode ? 0.13 : 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withOpacity(0.30)),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildActionCard(
                    context,
                    busy: busy,
                    configured: configured,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
