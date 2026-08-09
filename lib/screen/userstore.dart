// ─────────────────────────────────────────────────────────────────────────────
//  user_store.dart
//  Single source of truth for all user accounts (no database yet).
//  Import this file in login_screen.dart, account_screen.dart, etc.
// ─────────────────────────────────────────────────────────────────────────────

class AppUser {
  final String id;
  String firstName;
  String lastName;
  String email;
  String password;
  String role; // 'Clinic Head' | 'Clinic Staff'
  bool   isActive; // Clinic Head can toggle this on/off

  AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.role,
    this.isActive = true,
  });

  String get fullName => '$firstName $lastName';
}

// ─────────────────────────────────────────────────────────────────────────────
//  UserStore – static singleton
// ─────────────────────────────────────────────────────────────────────────────
class UserStore {
  UserStore._();

  // Seed accounts — edit email/password here before you add a real DB
  static final List<AppUser> _users = [
    AppUser(
      id:        'u1',
      firstName: 'Anna',
      lastName:  'Gonzaga',
      email:     'annagoz@tcgcclinic.com',
      password:  'ClinicHead@2026',
      role:      'Clinic Head',
      isActive:  true,
    ),
    AppUser(
      id:        'u2',
      firstName: 'Kate',
      lastName:  'Sale',
      email:     'katesale@tcgcclinic.com',
      password:  'ClinicStaff@2026',
      role:      'Clinic Staff',
      isActive:  true,
    ),
  ];

  // ── Read ──────────────────────────────────────────────────────────────────
  static List<AppUser> get all => List.unmodifiable(_users);

  static AppUser? findByEmail(String email) {
    final matches = _users.where((u) => u.email == email);
    return matches.isEmpty ? null : matches.first;
  }

  static AppUser? login(String email, String password) {
    final u = findByEmail(email.trim());
    if (u == null) return null;
    if (u.password != password) return null;
    if (!u.isActive) return null; // blocked accounts cannot log in
    return u;
  }

  // ── Write ─────────────────────────────────────────────────────────────────
  static String _nextId() => 'u${DateTime.now().millisecondsSinceEpoch}';

  /// Returns null on success, or an error string.
  static String? register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
  }) {
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      return 'First and last name are required.';
    }
    if (!email.contains('@')) return 'Enter a valid email address.';
    if (password.length < 6)  return 'Password must be at least 6 characters.';
    if (findByEmail(email) != null) return 'An account with that email already exists.';

    _users.add(AppUser(
      id:        _nextId(),
      firstName: firstName.trim(),
      lastName:  lastName.trim(),
      email:     email.trim(),
      password:  password,
      role:      role,
      isActive:  true,   // active by default; head can deactivate later
    ));
    return null; // success
  }

  static void toggleActive(String id) {
    final u = _users.firstWhere((u) => u.id == id, orElse: () => throw StateError('not found'));
    u.isActive = !u.isActive;
  }

  static void delete(String id) => _users.removeWhere((u) => u.id == id);
}