part of '../../home_page.dart';

class _PdfPreviewSheet extends StatefulWidget {
  const _PdfPreviewSheet({
    required this.filename,
    required this.controller,
    required this.treeUri,
    required this.relativePath,
  });

  final String filename;
  final AppController controller;
  final String treeUri;
  final String relativePath;

  @override
  State<_PdfPreviewSheet> createState() => _PdfPreviewSheetState();
}

class _PdfPreviewSheetState extends State<_PdfPreviewSheet> {
  late final Future<PdfControllerPinch> _controllerFuture = _loadController();
  PdfControllerPinch? _controller;
  int _page = 1;
  int _pages = 0;

  Future<PdfControllerPinch> _loadController() async {
    final bytes = await widget.controller.loadWorkspaceBytes(
      treeUri: widget.treeUri,
      relativePath: widget.relativePath,
    );
    final controller = PdfControllerPinch(
      document: PdfDocument.openData(bytes),
    );
    _controller = controller;
    return controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: _panelDecoration(context,
                  background: context.oc.panelBackground, radius: 16, elevated: false),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.filename,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l(context, 'PDF 预览', 'PDF preview'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.oc.foregroundMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_pages > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('$_page / $_pages'),
                    ),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<PdfControllerPinch>(
                future: _controllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                        child: Text(l(context, 'PDF 预览加载失败',
                            'Failed to load PDF preview')));
                  }
                  return PdfViewPinch(
                    controller: snapshot.data!,
                    onDocumentLoaded: (document) {
                      if (!mounted) return;
                      setState(() {
                        _pages = document.pagesCount;
                      });
                    },
                    onPageChanged: (page) {
                      if (!mounted) return;
                      setState(() {
                        _page = page;
                      });
                    },
                    onDocumentError: (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(l(
                                context, 'PDF 渲染失败', 'Failed to render PDF'))),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
