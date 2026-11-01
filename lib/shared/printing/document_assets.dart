import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

abstract final class DocumentAssets {
  DocumentAssets._();

  static const String logoAsset = 'asset/tcgc.png';

  static Uint8List? _logoBytes;
  static Future<Uint8List>? _logoRead;
  static String? _logoDataUri;

  static Future<Uint8List> logoBytes() {
    final cached = _logoBytes;
    if (cached != null) return Future.value(cached);
    final pending = _logoRead;
    if (pending != null) return pending;
    final read = _readLogo();
    _logoRead = read;
    return read;
  }

  static Future<Uint8List> _readLogo() async {
    try {
      final data = await rootBundle.load(logoAsset);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      _logoBytes = bytes;
      return bytes;
    } catch (_) {
      _logoRead = null;
      return Uint8List(0);
    }
  }

  static Future<String> logoDataUri() async {
    final cached = _logoDataUri;
    if (cached != null) return cached;
    final bytes = await logoBytes();
    if (bytes.isEmpty) return '';
    final uri = 'data:image/png;base64,${base64Encode(bytes)}';
    _logoDataUri = uri;
    return uri;
  }

  static pw.Font serif() => pw.Font.times();

  static pw.Font serifBold() => pw.Font.timesBold();

  static pw.Font serifItalic() => pw.Font.timesItalic();

  static pw.Font serifBoldItalic() => pw.Font.timesBoldItalic();
}
