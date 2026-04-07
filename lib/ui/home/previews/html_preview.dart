part of '../../home_page.dart';

class _WorkspaceHtmlPreview extends StatefulWidget {
  const _WorkspaceHtmlPreview({required this.html});

  final String html;

  @override
  State<_WorkspaceHtmlPreview> createState() => _WorkspaceHtmlPreviewState();
}

class _WorkspaceHtmlPreviewState extends State<_WorkspaceHtmlPreview> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.html, baseUrl: 'about:blank');
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
