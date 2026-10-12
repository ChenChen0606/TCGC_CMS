// Web implementation of the browser history facade. Tab switches are pushed
// as `#tab/<index>` hash entries and the popstate listener restores the tab
// when the user clicks the browser back/forward arrows.
//
// dart:html is the only browser API available without pulling in package:web;
// it is deprecated but fully functional for this use.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

bool get browserHistoryEnabled => true;

void Function(int index)? _onTab;

void initTabHistory(void Function(int index) onTab) {
  _onTab = onTab;
  html.window.onPopState.listen((_) {
    final idx = _readTab();
    if (idx != null) _onTab?.call(idx);
  });
  // Restore the tab on refresh / deep-link when a `#tab/n` hash is present.
  final initial = _readTab();
  if (initial != null) {
    scheduleMicrotask(() => _onTab?.call(initial));
  }
}

int? _readTab() {
  final match = RegExp(r'^#tab/(\d+)$').firstMatch(html.window.location.hash);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

void pushTabHistory(int index) {
  final current = _readTab();
  if (current == index) return;
  html.window.history.pushState(null, '', '#tab/$index');
}

void disposeTabHistory() {
  _onTab = null;
}
