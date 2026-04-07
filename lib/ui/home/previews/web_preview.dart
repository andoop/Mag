part of '../../home_page.dart';

class _WebPreviewSheet extends StatefulWidget {
  const _WebPreviewSheet({
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final String title;
  final String subtitle;
  final String url;

  @override
  State<_WebPreviewSheet> createState() => _WebPreviewSheetState();
}

class _WebPreviewSheetState extends State<_WebPreviewSheet> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.title}. ${widget.subtitle}',
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: WebViewWidget(controller: _controller),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    tooltip: l(context, '关闭', 'Close'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.45),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(10),
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
