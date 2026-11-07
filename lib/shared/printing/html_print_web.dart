// lib/shared/printing/html_print_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

bool get htmlPrintSupported => true;

/// Loads [source] into a hidden iframe and opens Chrome's print dialog.
/// Chrome lays the page out for whatever paper size is chosen in its dialog.
Future<void> printHtml(String source, {String title = 'Report'}) async {
  final frame = html.IFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0'
    ..srcdoc = source;
  final loaded = frame.onLoad.first;
  html.document.body!.append(frame);
  try {
    await loaded;
    // Give the inline SVG/logo a moment to decode before printing.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final dynamic win = frame.contentWindow;
    if (win == null) {
      throw StateError('Could not open the print frame.');
    }
    win.print(); // blocks until the print dialog is closed
  } finally {
    frame.remove();
  }
}