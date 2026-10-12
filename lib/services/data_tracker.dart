import 'package:flutter/foundation.dart';

/// Global revision signal so pages that stay alive in the dashboard's
/// IndexedStack can still notice when another tab (or the session) wrote
/// data. Any service write path calls [bump]; subscribed screens re-query
/// the database in their listener.
class DataTracker {
  DataTracker._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void bump() => revision.value++;

  static void listen(VoidCallback listener) => revision.addListener(listener);

  static void unlisten(VoidCallback listener) =>
      revision.removeListener(listener);
}
