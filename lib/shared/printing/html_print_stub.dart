// lib/shared/printing/html_print_stub.dart
// Used on platforms without a browser (desktop/mobile): callers fall back to PDF.
bool get htmlPrintSupported => false;

Future<void> printHtml(String html, {String title = 'Report'}) async {
  throw UnsupportedError('HTML printing is only available on web.');
}
