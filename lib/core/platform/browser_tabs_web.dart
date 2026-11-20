// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

bool get browserHistoryEnabled => true;

/// Makes links look like /reports instead of /#reports.
/// Must be called before runApp.
void configureUrlStrategy() => usePathUrlStrategy();

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

  // Read the current URL when the dashboard initializes (this is what keeps
  // you on the same page after a refresh).
  final tab = _readTab();
  if (tab != null) {
    onTab(tab);
  } else {
    html.window.history.replaceState(
      {'tab': 0, 'epoch': _epoch},
      '',
      '/dashboard',
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
      '/dashboard',
    );
    dashboard(0);
    return;
  }

  dashboard(tab);
}

int? _readTab() {
  var path = html.window.location.pathname ?? '';
  if (path.startsWith('/')) path = path.substring(1);
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);

  final index = _tabRoutes.indexOf(path);
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
    '/$route',
  );
}

/// Called when the user signs out: go back to the plain address.
void resetTabHistory() {
  html.window.history.replaceState(
    {'tab': 0, 'epoch': _epoch},
    '',
    '/',
  );
}

void disposeTabHistory() {
  _onTab = null;
  _popStateSub?.cancel();
  _popStateSub = null;
}