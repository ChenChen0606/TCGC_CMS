// ─────────────────────────────────────────────────────────────────────────────
//  visit_service_suggestions.dart
//  What a flagged reading suggests the nurse do next — as services.
//
//  WHY THIS IS A TABLE AND NOT A DECISION IN THE WIDGET
//  The bands themselves live in `vitals.dart` and are retunable from the
//  database. What a band *means for the rest of the visit* is a different
//  question, and it is a question about the clinic's services, so it lives here
//  next to nothing else and is read by the step-3 form. Moving a threshold must
//  not move these sentences, and adding a service must not mean editing a
//  widget.
//
//  WHAT A SUGGESTION IS NOT
//  It is a pre-filter, offered as one tap. Nothing is added to a visit without
//  the nurse pressing it, because a visit's service list is a record of what
//  was actually done — a service that appears on its own would be saved as a
//  row in `visit_services` for a treatment nobody gave. The same care applies to
//  the borderline bands: a reading only one step outside its range gets no
//  suggestion at all, because the band's own conclusion already says "re-check
//  before the visitor leaves" and turning that into a service would push the
//  nurse into treating numbers instead of watching them.
// ─────────────────────────────────────────────────────────────────────────────

import 'vitals.dart';

/// The service ids the rules below suggest, named once so the rules and the
/// tests cannot drift onto a typo'd string that resolves to nothing.
class SuggestedServices {
  const SuggestedServices._();

  static const String medication = 'medication';
  static const String consultation = 'medicine_consultation';
  static const String counselling = 'health_counselling';
}

/// One service a flagged reading points at, with the reading behind it.
class ServiceSuggestion {
  const ServiceSuggestion({
    required this.serviceId,
    required this.reason,
    required this.reading,
    required this.onVisit,
  });

  /// The service to open.
  final String serviceId;

  /// Why this reading suggests it, in a sentence a nurse can agree or disagree
  /// with. Deliberately about the reading and not about the service: "a fever is
  /// normally treated with something for it" is a claim she can check, and a
  /// claim she can disagree with, which is the only kind a suggestion should be.
  final String reason;

  /// The reading that produced it, kept whole so the UI can print the number and
  /// its band beside the sentence rather than making her recall them.
  final VitalReading reading;

  /// Whether the visit already has this service. True turns the offer from "add"
  /// into "open", because offering to add a service that is already on the visit
  /// is a dead control.
  final bool onVisit;
}

class VisitServiceSuggestions {
  const VisitServiceSuggestions._();

  /// The suggestions these readings earn, worst reading first, one per service.
  ///
  /// [isOnVisit] answers whether a service is already on this visit; it is a
  /// callback rather than a list because the controller owns the list and the
  /// draft order, and a second copy of it here would be a second thing to keep in
  /// step.
  ///
  /// One suggestion per service even when two readings would suggest the same
  /// one: two chips for the same service is a nurse being asked the same
  /// question twice, and the second one would only ever be the same answer.
  static List<ServiceSuggestion> forReadings(
    Iterable<VitalReading> readings, {
    required bool Function(String serviceId) isOnVisit,
  }) {
    final out = <ServiceSuggestion>[];
    final claimed = <String>{};
    final flagged = readings.where((r) => r.isAbnormal).toList()
      ..sort((a, b) => _weight(b.band).compareTo(_weight(a.band)));
    for (final r in flagged) {
      for (final rule in _rulesFor(r)) {
        if (!claimed.add(rule.serviceId)) continue;
        out.add(ServiceSuggestion(
          serviceId: rule.serviceId,
          reason: rule.reason,
          reading: r,
          onVisit: isOnVisit(rule.serviceId),
        ));
      }
    }
    return out;
  }

  /// Worst first, so a reading that needs a clinician beats one that needs a
  /// conversation, and the chip that survives deduping is the stronger reason.
  static int _weight(VitalBand band) => switch (band) {
        VitalBand.critical => 4,
        VitalBand.high => 3,
        VitalBand.watch => 2,
        VitalBand.low => 1,
        VitalBand.normal => 0,
      };

  /// The reading keys, as `VitalReading.key` spells them. Matched on the key
  /// rather than on the band label, because a label is a word a clinic can
  /// retune and "Temperature 38.4" is the fact.
  static List<_Rule> _rulesFor(VitalReading r) {
    final acted = r.band == VitalBand.high || r.band == VitalBand.critical;
    switch (r.key) {
      case 'temperature':
        if (!acted) return const [];
        return const [
          _Rule(
              SuggestedServices.medication,
              'A fever is normally treated with something for it, not just '
              'watched until the visit ends.'),
          _Rule(
              SuggestedServices.consultation,
              'A temperature this far out is a clinician\'s call rather than a '
              'screening one.'),
        ];
      case 'blood_pressure':
        if (!acted) return const [];
        return const [
          _Rule(
              SuggestedServices.consultation,
              'A blood pressure this far out of range wants a clinician, not a '
              'note in the record.'),
        ];
      case 'heart_rate':
        if (!acted) return const [];
        return const [
          _Rule(SuggestedServices.consultation,
              'A pulse this far out of range wants a clinician to hear it.'),
        ];
      case 'bmi':
        // Watch, not acted: being underweight or overweight is a conversation
        // the nurse can have in the room, which is exactly what counselling is.
        if (r.band == VitalBand.watch || r.band == VitalBand.high) {
          return const [
            _Rule(
                SuggestedServices.counselling,
                'Weight is worth talking about while the person is sitting '
                'here.'),
          ];
        }
        return const [];
      default:
        // A low oxygen saturation or a fast respiratory rate is not a service to
        // open — the band's own conclusion already says act now, and offering a
        // form at that moment would be offering paperwork instead of help.
        return const [];
    }
  }
}

class _Rule {
  const _Rule(this.serviceId, this.reason);
  final String serviceId;
  final String reason;
}
