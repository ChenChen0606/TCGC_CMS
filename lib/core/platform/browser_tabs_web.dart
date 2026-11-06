
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/widgets.dart';

bool get browserHistoryEnabled => true;

void Function(int index)? _onTab;
StreamSubscription<html.PopStateEvent>? _popStateSub;

int _epoch = 0;

const List<String> _tabRoutes = [
  'dashboard',
  'clinic-visits',
  'individual-records',
  'bmi-records',
  'inventory',
  'records-booklet',
  'reports',
  'user-accounts',
];

class _RoutePushGuard extends WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async =>
      true;
}

void installHistoryRouteGuard() {
  WidgetsBinding.instance.addObserver(_RoutePushGuard());
}

void initTabHistory(void Function(int index) onTab) {
  _onTab = onTab;
  _epoch += 1;

  _popStateSub ??= html.window.onPopState.listen(_handlePopState);

  // Read the current URL when the dashboard initializes.
  final tab = _readTab();
  if (tab != null) {
    onTab(tab);
  } else {
    html.window.history.replaceState(
      {'tab': 0, 'epoch': _epoch},
      '',
      '#dashboard',
    );
    onTab(0);
  }
}

void _handlePopState(html.PopStateEvent event) {
  final dashboard = _onTab;
  if (dashboard == null) return;

  final tab = _readTab();

  if (tab == null) {
    html.window.history.replaceState(
      {'tab': 0, 'epoch': _epoch},
      '',
      '#dashboard',
    );
    dashboard(0);
    return;
  }

  dashboard(tab);
}

int? _readTab() {
  final hash = html.window.location.hash;

  final index = _tabRoutes.indexOf(
    hash.startsWith('#') ? hash.substring(1) : hash,
  );

  if (index < 0) return null;
  return index;
}

void pushTabHistory(int index) {
  if (index < 0 || index >= _tabRoutes.length) return;

  if (_readTab() == index) return;

  final route = _tabRoutes[index];

  html.window.history.pushState(
    {'tab': index, 'epoch': _epoch},
    '',
    '#$route',
  );
}

void resetTabHistory() {
  html.window.history.replaceState(
    {'tab': 0, 'epoch': _epoch},
    '',
    '#dashboard',
  );
}

void disposeTabHistory() {
  _onTab = null;
  _popStateSub?.cancel();
  _popStateSub = null;
}
