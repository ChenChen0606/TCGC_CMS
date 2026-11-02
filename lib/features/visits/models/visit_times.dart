import 'package:intl/intl.dart';

class VisitTimes {
  const VisitTimes._();

  static const String outBeforeInMessage =
      'Time Out cannot be earlier than Time In.';

  static String clock(DateTime at) => DateFormat('hh:mm a').format(at);

  static String date(DateTime at) => DateFormat('MMM d, yyyy').format(at);

  static String stamp(DateTime at) => '${date(at)} · ${clock(at)}';

  static DateTime combine(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  static DateTime _minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  static bool outBeforeIn(DateTime? timeIn, DateTime? timeOut) =>
      timeIn != null &&
      timeOut != null &&
      _minute(timeOut).isBefore(_minute(timeIn));

  static String? stayLabel(Duration? length) {
    if (length == null || length.isNegative) return null;
    if (length.inMinutes < 1) return 'Under a minute';
    if (length.inHours < 1) return '${length.inMinutes} min';
    final mins = length.inMinutes - length.inHours * 60;
    return mins == 0
        ? '${length.inHours} hr'
        : '${length.inHours} hr $mins min';
  }

  static String? stayBetween(DateTime? checkedIn, DateTime? timedOut) {
    if (checkedIn == null || timedOut == null) return null;
    return stayLabel(timedOut.difference(checkedIn));
  }
}