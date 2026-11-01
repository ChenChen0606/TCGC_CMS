// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/widgets.dart';

bool get browserHistoryEnabled => true;

void Function(int index)? _onTab;
StreamSubscription<html.PopStateEvent>? _popStateSub;

int _epoch = 0;

class _RoutePushGuard extends WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(
          RouteInformation routeInformation) async =>
      true;
}

void installHistoryRouteGuard() {
  WidgetsBinding.instance.addObserver(_RoutePushGuard());
}

void initTabHistory(void Function(int index) onTab) {
  _onTab = onTab;
  _epoch += 1;

  _popStateSub ??= html.window.onPopState.listen(_handlePopState);
}

void _handlePopState(html.PopStateEvent event) {
  final dashboard = _onTab;
  if (dashboard == null) return;

  final Object? entry = _unwrap(event.state);
  int tab = -1;
  if (entry is Map && entry['epoch'] == _epoch && entry['tab'] is int) {
    tab = entry['tab'] as int;
  }
  if (tab < 0) {
    html.window.history.replaceState({'tab': 0, 'epoch': _epoch}, '', '#tab/0');
    tab = 0;
  }
  dashboard(tab);
}

Object? _unwrap(Object? state) {
  if (state is Map && state.containsKey('state')) return state['state'];
  return state;
}

int? _readTab() {
  final match = RegExp(r'^#tab/(\d+)$').firstMatch(html.window.location.hash);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

void pushTabHistory(int index) {
  if (_readTab() == index) return;
  html.window.history
      .pushState({'tab': index, 'epoch': _epoch}, '', '#tab/$index');
}

void resetTabHistory() {
  html.window.history.replaceState(null, '', '#tab/0');
}

void disposeTabHistory() {
  _onTab = null;
  _popStateSub?.cancel();
  _popStateSub = null;
}
