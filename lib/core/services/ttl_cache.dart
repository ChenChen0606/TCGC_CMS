import 'dart:async';

import 'package:clinicmanagementsystem/core/services/data_tracker.dart';

/// Remembers the last result of an async load so a screen can paint it at
/// once (see [peek]) while a refresh runs in the background.
///
/// * A result younger than [ttl] is returned without touching the network.
/// * Two callers asking at the same time share ONE request.
/// * Any [DataTracker.bump] (a save, edit, delete, ...) or sign-out clears it,
///   so the screen never paints data that is known to be out of date.
class TtlCache<T> {
  TtlCache({this.ttl = const Duration(seconds: 60)}) {
    DataTracker.onInvalidate(clear);
  }

  final Duration ttl;

  T? _value;
  DateTime? _at;
  Future<T>? _inflight;
  int _gen = 0;

  /// The last good value, or null if nothing is stored (never loaded, or
  /// cleared by a data change / sign-out). It may be older than [ttl].
  T? get peek => _value;

  bool get isFresh {
    final at = _at;
    return _value != null && at != null && DateTime.now().difference(at) < ttl;
  }

  Future<T> get(Future<T> Function() loader, {bool force = false}) {
    if (!force && isFresh) return Future<T>.value(_value as T);
    final running = _inflight;
    if (running != null) return running;
    final f = _run(loader, _gen);
    _inflight = f;
    return f;
  }

  Future<T> _run(Future<T> Function() loader, int gen) async {
    try {
      final v = await loader();
      // If the cache was cleared while this request was running, the answer
      // may already be out of date: hand it to the caller, but do not keep it.
      if (gen == _gen) {
        _value = v;
        _at = DateTime.now();
      }
      return v;
    } finally {
      scheduleMicrotask(() {
        if (gen == _gen) _inflight = null;
      });
    }
  }

  void clear() {
    _gen++;
    _value = null;
    _at = null;
    _inflight = null;
  }
}