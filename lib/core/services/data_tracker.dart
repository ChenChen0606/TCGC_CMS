import 'package:flutter/foundation.dart';

class DataTracker {
  DataTracker._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final List<VoidCallback> _invalidators = [];

  /// Registers a callback that drops cached data. It runs on every [bump]
  /// BEFORE the screens are told to reload, so a reload never gets old data
  /// back from a cache.
  static void onInvalidate(VoidCallback cb) {
    if (!_invalidators.contains(cb)) _invalidators.add(cb);
  }

  /// Drops every cache without telling the screens to reload (sign-out).
  static void invalidateAll() {
    for (final cb in List<VoidCallback>.of(_invalidators)) {
      cb();
    }
  }

  static void bump() {
    invalidateAll();
    revision.value++;
  }

  static void listen(VoidCallback listener) => revision.addListener(listener);

  static void unlisten(VoidCallback listener) =>
      revision.removeListener(listener);
}