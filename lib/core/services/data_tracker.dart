import 'package:flutter/foundation.dart';

class DataTracker {
  DataTracker._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void bump() => revision.value++;

  static void listen(VoidCallback listener) => revision.addListener(listener);

  static void unlisten(VoidCallback listener) =>
      revision.removeListener(listener);
}
