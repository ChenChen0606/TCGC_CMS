// lib/shared/printing/html_sheet.dart
import 'dart:convert';

const String _css = r'''
@page { size: auto; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: #fff; }
body { font-family: "Times New Roman", Times, serif; color: #000;
  -webkit-print-color-adjust: exact; print-color-adjust: exact; }
svg { display: block; width: 100%; height: auto; overflow: visible; }

/* Outer frame: thead = small top gap on every page, tfoot = space reserved
   for the fixed footer on every page. */
.frame { width: 100%; border-collapse: collapse; border-spacing: 0; }
.frame > thead > tr > td, .frame > tbody > tr > td { padding: 0; border: 0; }
.frame > tfoot > tr > td { padding: 0 0 12px; border: 0; }
.frame > thead { display: table-header-group; }
.frame > tfoot { display: table-footer-group; }
.gap { height: 12px; }
.foot-space { width: 100%; aspect-ratio: 1545 / 120; }
.foot { position: fixed; left: 0; right: 0; bottom: 12px; }
.content { padding: 0 4%; }

.ttl { text-align: center; color: #0E6B47; }
.office { font-size: 13.5pt; font-weight: bold; margin-top: 4px; }
.loc { font-size: 10pt; }
.title { font-size: 22pt; font-weight: bold; margin-top: 8px; }
.inst { font-size: 15pt; font-weight: bold; margin-top: 4px; }
.meta { display: flex; justify-content: space-between; font-size: 10pt; margin: 8px 0; }

table.t { width: 100%; border-collapse: collapse; table-layout: fixed; font-size: 8.5pt; }
.t th, .t td { border: 0.6pt solid #000; padding: 4px; vertical-align: top;
  overflow-wrap: anywhere; white-space: pre-line; }
.t th { background: #E7EFEA; text-align: center; font-weight: bold; }
.t thead { display: table-header-group; }
.t tr { break-inside: avoid; }
.t .nopad { padding: 0; }
.c { text-align: center; }
.b { font-weight: bold; }
.sm { font-size: 7.5pt; }
.ln { margin-bottom: 3px; }
.blank td { height: 24px; }

table.sub { width: 100%; border-collapse: collapse; table-layout: fixed; }
.sub th, .sub td { border: 0; border-left: 0.6pt solid #000; padding: 4px;
  background: transparent; text-align: left; vertical-align: top; }
.sub th { text-align: center; }
.sub td { border-top: 0.4pt solid #999; }
.sub tr:first-child td { border-top: 0; }
.sub th:first-child, .sub td:first-child { border-left: 0; }

.note { font-size: 8pt; font-style: italic; margin-top: 4px; }
.sig { display: flex; gap: 30px; margin-top: 18px; break-inside: avoid; font-size: 11pt; }
.sig > div { flex: 1; }
.sig .line { display: flex; align-items: flex-end; }
.sig .line i { flex: 1; border-bottom: 0.8pt solid #000; margin-left: 6px; height: 14px; }
.sig .role { text-align: center; font-size: 10pt; margin-top: 3px; }
''';

/// Wraps [bodyHtml] with the letterhead (first page only) and the footer
/// (pinned to the bottom of every page). Everything scales with page width.
String sheetDocument({
  required String title,
  required String headerSvg,
  required String footerSvg,
  required String bodyHtml,
}) =>
    '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${const HtmlEscape().convert(title)}</title>
<style>$_css</style></head><body>
<table class="frame">
<thead><tr><td><div class="gap"></div></td></tr></thead>
<tbody><tr><td>
<div class="head">$headerSvg</div>
<div class="content">$bodyHtml</div>
</td></tr></tbody>
<tfoot><tr><td><div class="foot-space"></div></td></tr></tfoot>
</table>
<div class="foot">$footerSvg</div>
</body></html>''';
