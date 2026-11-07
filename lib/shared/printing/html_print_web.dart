// lib/shared/printing/html_print_web.dart
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get htmlPrintSupported => true;

/// Loads [source] into a hidden iframe and opens Chrome's print dialog.
/// Chrome lays the page out for whatever paper size is chosen in its dialog.
Future<void> printHtml(String source, {String title = 'Report'}) async {
  final frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
  frame.setAttribute(
    'style',
    'position:fixed;right:0;bottom:0;width:0;height:0;border:0;',
  );
  frame.setAttribute('srcdoc', source);

  final loaded = Completer<void>();
  frame.addEventListener(
    'load',
    ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS,
  );

  web.document.body!.append(frame);
  try {
    await loaded.future;
    // Give the inline SVG/logo a moment to decode before printing.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final win = frame.contentWindow;
    if (win == null) {
      throw StateError('Could not open the print frame.');
    }
    win.print(); // blocks until the print dialog is closed
  } finally {
    frame.remove();
  }
}