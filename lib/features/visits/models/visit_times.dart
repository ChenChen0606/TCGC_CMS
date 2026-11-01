import 'package:intl/intl.dart';

class VisitTimes {
  const VisitTimes._();

  static String clock(DateTime at) => DateFormat('hh:mm a').format(at);

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
