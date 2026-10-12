import 'package:intl/intl.dart';

/// The two ends of a visit, and the words they are written and spoken in.
///
/// A visit has a check-in and a time-out, and both are facts about the visit
/// rather than about the moment a button was pressed. The rules for turning
/// them into text live here, on their own, because they are arithmetic and
/// formatting — the kind of thing that is easy to get subtly wrong and hard to
/// check through a screen.
class VisitTimes {
  const VisitTimes._();

  /// How a visit's time is stored and shown: the format `visits.visit_time` and
  /// `visits.time_out` already use, and the one the clinic writes by hand.
  static String clock(DateTime at) => DateFormat('hh:mm a').format(at);

  /// How long a stay was, in the units a clinic says it out loud: under an hour
  /// in minutes, an hour or more as hours and minutes. A queue report that
  /// reads "7 min" and one that reads "180 min" are the same number wearing
  /// different clothes, and the second is the one nobody reads.
  ///
  /// Null rather than a number when there is no honest answer: a missing end
  /// means the length is not known yet, and a negative one means the device
  /// clock went backwards — neither is zero, and neither is worth printing.
  static String? stayLabel(Duration? length) {
    if (length == null || length.isNegative) return null;
    if (length.inMinutes < 1) return 'Under a minute';
    if (length.inHours < 1) return '${length.inMinutes} min';
    final mins = length.inMinutes - length.inHours * 60;
    return mins == 0
        ? '${length.inHours} hr'
        : '${length.inHours} hr $mins min';
  }

  /// [stayLabel] for the two ends of a visit, worked out from the instants.
  ///
  /// From the `DateTime`s and never from the formatted strings: "10:30 AM" to
  /// "10:05 AM" is the next day, and a subtraction that cannot tell the two
  /// apart is a subtraction that lies.
  static String? stayBetween(DateTime? checkedIn, DateTime? timedOut) {
    if (checkedIn == null || timedOut == null) return null;
    return stayLabel(timedOut.difference(checkedIn));
  }
}
