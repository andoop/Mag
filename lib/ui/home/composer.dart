part of '../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

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
      for (final entry in _promptAttachments) entry.path: entry,
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
      _promptAttachments = selected;
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
      final mime = entry.mimeType ??
          (entry.isDirectory ? 'application/x-directory' : 'text/plain');
      final source = <String, dynamic>{
        'type': 'file',
        'path': entry.path,
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
        final bytes = await widget.controller.loadWorkspaceBytes(
          treeUri: workspace.treeUri,
          relativePath: entry.path,
        );
        base['url'] = 'data:$mime;base64,${base64Encode(bytes)}';
      } else if (mime == 'text/plain' ||
          mime == 'text/markdown' ||
          mime == 'text/html' ||
          mime == 'application/json' ||
          mime == 'application/x-directory') {
        final content = entry.isDirectory
            ? 'Directory: ${entry.path}'
            : await widget.controller.loadWorkspaceText(
                treeUri: workspace.treeUri,
                relativePath: entry.path,
              );
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
      decoration: BoxDecoration(
        color: oc.pageBackground,
        border: Border(top: BorderSide(color: oc.softBorderColor)),
        boxShadow: [
          BoxShadow(
            color: oc.shadow,
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
              12, isKeyboardOpen ? 4 : 8, 12, isKeyboardOpen ? 6 : 10),
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
              Container(
                decoration: BoxDecoration(
                  color: oc.panelBackground,
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.fromBorderSide(BorderSide(color: oc.borderColor)),
                  boxShadow: [
                    BoxShadow(
                      color: oc.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
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
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                                        padding: const EdgeInsets.fromLTRB(
                                            6, 0, 6, 6),
                                        shrinkWrap: true,
                                        itemCount:
                                            _promptMentionSuggestions.length,
                                        separatorBuilder: (_, __) => Divider(
                                            height: 1,
                                            color: oc.softBorderColor),
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
                                              ? entry.name.replaceAll(
                                                  RegExp(r'/+$'), '')
                                              : entry.name;
                                          return InkWell(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            onTap: () =>
                                                _insertPromptMentionSuggestion(
                                                    entry),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 10),
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
                                                          ? Icons
                                                              .folder_outlined
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
                                                            overflow:
                                                                TextOverflow
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
                                                                ? l(
                                                                    context,
                                                                    '目录',
                                                                    'Directory')
                                                                : l(
                                                                    context,
                                                                    '文件',
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
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                              child: SingleChildScrollView(
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
                                        label:
                                            _variantTrayLabel(context, state),
                                        onTap: () =>
                                            _openVariantPicker(context),
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
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _promptAttachments
                                .map(
                                  (entry) => InputChip(
                                    label: Text(
                                      entry.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    avatar: Icon(
                                      (entry.mimeType ?? '')
                                              .startsWith('image/')
                                          ? Icons.image_outlined
                                          : (entry.mimeType ==
                                                  'application/pdf')
                                              ? Icons.picture_as_pdf_outlined
                                              : Icons.attach_file,
                                      size: 16,
                                    ),
                                    onDeleted: () {
                                      setState(() {
                                        _promptAttachments = _promptAttachments
                                            .where((item) =>
                                                item.path != entry.path)
                                            .toList();
                                      });
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              10, isKeyboardOpen ? 2 : 3, 10, 8),
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
                            child: TextField(
                              controller: _promptController,
                              focusNode: _promptFocusNode,
                              minLines: 1,
                              maxLines: isKeyboardOpen ? 4 : 3,
                              textInputAction: TextInputAction.newline,
                              style:
                                  const TextStyle(fontSize: 14, height: 1.32),
                              decoration: InputDecoration(
                                hintText: l(context, '问我关于这个工作区的任何事，输入 @ 引用文件',
                                    'Ask anything about this workspace, type @ to reference files'),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                    38, isKeyboardOpen ? 7 : 8, 86, 11),
                                hintStyle: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: oc.foregroundHint),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _CompactIconButton(
                            tooltip: l(context, '附件', 'Attach'),
                            onPressed: () =>
                                _openPromptAttachmentPicker(context),
                            icon: Icons.add,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
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
                                const SizedBox(width: 8),
                              ],
                              state.isBusy
                                  ? FilledButton(
                                      style: FilledButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(0),
                                        minimumSize: const Size(36, 36),
                                        fixedSize: const Size(36, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: Colors.red.shade500,
                                        elevation: 0,
                                      ),
                                      onPressed: () =>
                                          widget.controller.cancelPrompt(),
                                      child: const Icon(Icons.stop,
                                          color: Colors.white, size: 16),
                                    )
                                  : FilledButton(
                                      style: FilledButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(0),
                                        minimumSize: const Size(36, 36),
                                        fixedSize: const Size(36, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: oc.sendButtonBg,
                                        foregroundColor: oc.sendButtonFg,
                                        elevation: 0,
                                      ),
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
                                      child: const Icon(Icons.arrow_upward,
                                          size: 16),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: oc.panelBackground,
        side: BorderSide(color: oc.borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: oc.foreground),
          const SizedBox(width: 6),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: oc.foreground,
            ),
          ),
        ],
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
