import 'package:flutter/foundation.dart';

/// The signed-in user's display name, shared by the whole app.
class ProfileState {
  ProfileState._();

  static final ValueNotifier<String> displayName = ValueNotifier<String>('');

  static void set(String name) {
    final n = name.trim();
    if (n.isNotEmpty && displayName.value != n) displayName.value = n;
  }

  static void clear() => displayName.value = '';
}