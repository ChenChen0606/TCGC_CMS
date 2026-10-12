// ─────────────────────────────────────────────────────────────────────────────
//  account_service.dart
//  Supabase-backed account CRUD for the Account & User Management screen.
//
//  Storage layout on this project:
//    * `auth.users`   — Supabase Auth. Holds the login email + password hash.
//                       Not reachable from the client, by design.
//    * `public.useraccount` — the app's account table. Columns:
//                       user_id, email, username, role, is_active,
//                       must_change_password, avatar_url, created_at.
//                       It has NO name and NO contact columns.
//
//  Because there is nowhere to keep a person's name in the table, first /
//  middle / last name live in Supabase Auth `user_metadata`, and this service
//  joins the two sources. Passwords live ONLY inside Supabase Auth.
//
//  This service:
//    * lists `useraccount` rows
//    * creates a real Auth user (register) and its `useraccount` row
//    * toggles is_active / deletes rows
//    * updates the signed-in user's own name (via Auth metadata) and avatar
//    * verifies + changes the signed-in user's password via Auth
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'dart:typed_data';

import 'package:clinicmanagementsystem/services/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors the `public.useraccount` table shape (no password anywhere).
///
/// Real columns: user_id, fn, mn, ln, username, email, avatar_url, role,
/// is_active, must_change_password, created_at, created_by.
/// The name is stored abbreviated: fn / mn / ln (not first/middle/last_name).
class AppProfile {
  final String id;
  final String firstName;
  final String middleName;
  final String lastName;
  final String username;
  final String email; // recovery/login email (may be synthetic @clinic.local)
  final String contact;
  final String avatarUrl; // public URL of the optional profile picture
  final String role; // 'Clinic Head' | 'Clinic Staff'
  bool isActive;
  bool mustChangePassword;
  final DateTime? createdAt;

  AppProfile({
    required this.id,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.username = '',
    this.email = '',
    this.contact = '',
    this.avatarUrl = '',
    this.role = 'Clinic Staff',
    this.isActive = true,
    this.mustChangePassword = false,
    this.createdAt,
  });

  String get fullName =>
      [firstName, middleName, lastName].where((s) => s.isNotEmpty).join(' ');

  /// Name to display when the person has no first/last name on record (the
  /// `useraccount` table stores none), falling back to their username.
  String get displayName => fullName.isNotEmpty ? fullName : username;

  factory AppProfile.fromSupabase(Map<String, dynamic> row) {
    return AppProfile(
      id: row['user_id'] as String? ?? '',
      firstName: (row['fn'] as String? ?? '').trim(),
      middleName: (row['mn'] as String? ?? '').trim(),
      lastName: (row['ln'] as String? ?? '').trim(),
      username: (row['username'] as String? ?? '').trim(),
      email: (row['email'] as String? ?? '').trim(),
      // `useraccount` has no contact column.
      contact: '',
      avatarUrl: (row['avatar_url'] as String? ?? '').trim(),
      role: (row['role'] as String?)?.isNotEmpty == true
          ? row['role'] as String
          : 'Clinic Staff',
      isActive: row['is_active'] as bool? ?? true,
      mustChangePassword: row['must_change_password'] as bool? ?? false,
      createdAt: _parseTs(row['created_at']),
    );
  }

  /// Fills any name field the table row left blank from [other] (the Auth
  /// metadata copy). The table is authoritative, so only empty fields are
  /// taken from metadata — this keeps a signed-in user readable even if their
  /// row is stale.
  AppProfile withNamesFrom(AppProfile other) => AppProfile(
        id: id.isNotEmpty ? id : other.id,
        firstName: firstName.isNotEmpty ? firstName : other.firstName,
        middleName: middleName.isNotEmpty ? middleName : other.middleName,
        lastName: lastName.isNotEmpty ? lastName : other.lastName,
        username: username.isNotEmpty ? username : other.username,
        email: email.isNotEmpty ? email : other.email,
        contact: '',
        avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : other.avatarUrl,
        role: role,
        isActive: isActive,
        mustChangePassword: mustChangePassword,
        createdAt: createdAt ?? other.createdAt,
      );

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

class AccountService {
  AccountService._();

  static SupabaseClient get _db => supabaseClient;

  /// Username shape rule, shared by the UI and the DB: 3-20 characters,
  /// starts with a letter, then letters/numbers/dots/dashes/underscores.
  static final RegExp usernamePattern =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]{2,19}$');

  // ─────────────────────────────────────────────────────────────────────────────
  //  USERNAME → AUTH EMAIL
  //
  //  Staff sign in with a USERNAME, but Supabase Auth only understands an
  //  EMAIL. `useraccount` maps username -> email, so the address is resolved
  //  with one read; see [resolveAuthEmailForIdentifier].
  //
  //  This address is a login identity only; for a synthetic one it is never
  //  deliverable. A real mailbox is kept separately for "forgot password".
  // ─────────────────────────────────────────────────────────────────────────────

  /// Domain of the synthetic, non-deliverable Auth email used for sign-in.
  static const String authEmailDomain = 'clinic.local';

  /// Converts whatever the user typed at the sign-in prompt into the Auth
  /// email. A value containing `@` is treated as an email and passed through
  /// unchanged (so an account created directly in the Supabase dashboard with
  /// a real address can still sign in); anything else is treated as a username.
  static String authEmailForIdentifier(String identifier) {
    final value = identifier.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value.contains('@')) return value;
    return '$value@$authEmailDomain';
  }

  /// Inverse of [authEmailForIdentifier]: the username part of an Auth email.
  static String usernameFromAuthEmail(String? email) {
    final value = (email ?? '').trim();
    if (value.isEmpty) return '';
    final at = value.lastIndexOf('@');
    return (at > 0 ? value.substring(0, at) : value).trim();
  }

  /// A user's own `user_metadata`, which is the only per-account store
  /// available without a name column in `useraccount`. Never returns null.
  static Map<String, dynamic> metadataOf(User? user) {
    final raw = user?.userMetadata;
    if (raw == null || raw.isEmpty) return const <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  static String _metaString(Map<String, dynamic> meta, String key) {
    final v = meta[key];
    return v is String ? v.trim() : '';
  }

  static bool _metaBool(Map<String, dynamic> meta, String key, bool fallback) {
    final v = meta[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  /// Builds a profile from Auth alone, for when the `useraccount` row is
  /// missing or unreadable. Fields absent from
  /// `user_metadata` degrade gracefully rather than failing the sign-in.
  static AppProfile profileFromAuthUser(User? user) {
    final meta = metadataOf(user);
    final username = _metaString(meta, 'username').isNotEmpty
        ? _metaString(meta, 'username')
        : usernameFromAuthEmail(user?.email);
    return AppProfile(
      id: user?.id ?? '',
      firstName: _metaString(meta, 'first_name'),
      middleName: _metaString(meta, 'middle_name'),
      lastName: _metaString(meta, 'last_name'),
      username: username,
      email: (user?.email ?? '').trim(),
      contact: _metaString(meta, 'contact'),
      avatarUrl: _metaString(meta, 'avatar_url'),
      role: _metaString(meta, 'role').isNotEmpty
          ? _metaString(meta, 'role')
          : 'Clinic Staff',
      isActive: _metaBool(meta, 'is_active', true),
      mustChangePassword: _metaBool(meta, 'must_change_password', false),
      createdAt: AppProfile._parseTs(user?.createdAt),
    );
  }

  /// The signed-in user's profile row id ('' when signed out).
  static String get currentUserId => _db.auth.currentUser?.id ?? '';

  /// All clinic accounts, oldest first.
  ///
  /// Names come from the table's own fn / mn / ln columns, so every entry has
  /// a real name as long as the caller is allowed to read the rows.
  static Future<List<AppProfile>> fetchAll() async {
    final rows = await _db.from('useraccount').select().order('created_at');
    return rows
        .map<AppProfile>(
            (r) => AppProfile.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// The signed-in user's own profile, joined with their Auth metadata so their
  /// first / last name is populated (the table cannot store it).
  ///
  /// Returns a metadata-only profile if the table has no row for this user yet,
  /// so a freshly registered account still works.
  static Future<AppProfile?> fetchOwn() async {
    final user = _db.auth.currentUser;
    final uid = user?.id;
    if (uid == null) return null;
    try {
      final row = await _db
          .from('useraccount')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return profileFromAuthUser(user);
      return AppProfile.fromSupabase(Map<String, dynamic>.from(row))
          .withNamesFrom(profileFromAuthUser(user));
    } catch (_) {
      return profileFromAuthUser(user);
    }
  }

  /// Resolves a sign-in identifier to the Auth email of the matching account.
  ///
  /// Tried in order, so sign-in works in every configuration:
  ///   1. the value already contains `@` → used as-is, no lookup;
  ///   2. the `resolve_email_by_username` function, which is SECURITY DEFINER
  ///      and therefore works even when RLS hides `useraccount` from the anon
  ///      key (this is what keeps accounts with a real mailbox working);
  ///   3. reading `useraccount` directly, for when only the table exists;
  ///   4. deriving `<username>@clinic.local`.
  ///
  /// Returns `null` only when the identifier is blank; the caller reports a
  /// generic "incorrect" error either way, so the form never reveals whether a
  /// username exists.
  static Future<String?> resolveAuthEmailForIdentifier(
      String identifier) async {
    final value = identifier.trim().toLowerCase();
    if (value.isEmpty) return null;

    // A full email address needs no lookup at all.
    if (value.contains('@')) return value;

    // 2. The function, when the migration has been applied.
    try {
      final resolved = await _db.rpc(
        'resolve_email_by_username',
        params: {'p_username': value},
      );
      String? fromRpc(Object? v) {
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v is List) {
          for (final e in v) {
            if (e is String && e.trim().isNotEmpty) return e.trim();
          }
        }
        return null;
      }

      final email = fromRpc(resolved);
      if (email != null) return email;
    } catch (_) {
      // Function not deployed → fall through.
    }

    // 3. The table, when it is readable.
    try {
      final row = await _db
          .from('useraccount')
          .select('email')
          .eq('username', value)
          .maybeSingle();
      final email = row == null ? null : (row['email'] as String?)?.trim();
      if (email != null && email.isNotEmpty) return email;
    } catch (_) {
      // Table unreadable (missing or blocked by RLS) → use the derived form.
    }

    // 4. The deterministic fallback.
    return authEmailForIdentifier(value);
  }

  /// Registers a brand-new clinic account and returns its profile.
  ///
  /// Only a signed-in Clinic Head should call this.
  ///
  /// Credentials are auto-derived so the user ONLY ever has to remember their
  /// USERNAME: the Supabase Auth email is a hidden internal value
  /// (`<username>@clinic.local`, see [authEmailForIdentifier]) that is derived
  /// from it. Account creation tries, in order:
  ///   1. the Head-gated `admin_create_user` Edge Function,
  ///   2. the SQL `admin_create_user` RPC (same behavior, applied via migration),
  ///   3. the `signUp()` flow, which is the only path that works while this
  ///      project has neither of the above deployed.
  static Future<AppProfile> register({
    required String firstName,
    required String lastName,
    required String username,
    required String password,
    required String role,
    String email = '',
  }) async {
    final trimmedFirstName = firstName.trim();
    final trimmedLastName = lastName.trim();
    final trimmedUsername = username.trim().toLowerCase();
    // A real email is stored when supplied (needed for "forgot password");
    // otherwise the hidden `<username>@clinic.local` identity is used.
    final trimmedEmail = email.trim().toLowerCase();
    final authEmail = trimmedEmail.isNotEmpty
        ? trimmedEmail
        : authEmailForIdentifier(trimmedUsername);

    // ── Preferred path: Head-gated Edge Function (creates a confirmed user) ──
    try {
      final res = await _db.functions.invoke('admin_create_user', body: {
        'first_name': trimmedFirstName,
        'last_name': trimmedLastName,
        'username': trimmedUsername,
        'password': password,
        'role': role,
        'email': trimmedEmail,
      });
      final data =
          res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      final uid = data?['id'] as String?;
      if (uid == null) {
        throw AuthException(
            'Account was created, but its profile could not be loaded. '
            'It will appear in the list shortly.');
      }
      final row = await _db
          .from('useraccount')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) {
        throw AuthException(
            'Account was created. Refresh the list to see it appear.');
      }
      return AppProfile.fromSupabase(Map<String, dynamic>.from(row));
    } on Exception catch (e) {
      // Any failure to reach the function counts as "not available" and falls
      // through to the SQL RPC below. This matters on Flutter Web, where an
      // undeployed (404) function surfaces as a generic
      // `http.ClientException: Failed to fetch` instead of a FunctionException.
      if (e is FunctionException && e.status != 404 && e.status != 308) {
        // The Edge Function IS deployed but rejected the request.
        final details = e.details;
        final msg = details is Map && details['error'] is String
            ? details['error'] as String
            : null;
        throw AuthException((msg == null || msg.isEmpty)
            ? 'Account registration failed.'
            : msg);
      }
      // 404/308, network/connect failures, or anything else → fall through.
    }

    // ── SQL RPC path (same head-gated behavior once the migration is applied) ──
    try {
      final uid = await _db.rpc('admin_create_user', params: {
        'p_first_name': trimmedFirstName,
        'p_last_name': trimmedLastName,
        'p_username': trimmedUsername,
        'p_password': password,
        'p_role': role,
        'p_email': trimmedEmail,
      });
      final id = _rpcScalar(uid);
      if (id == null || id.isEmpty) {
        throw AuthException(
            'Account was created, but its profile could not be loaded. '
            'Refresh the list to see it appear.');
      }
      final row = await _db
          .from('useraccount')
          .select()
          .eq('user_id', id)
          .maybeSingle();
      if (row == null) {
        throw AuthException(
            'Account was created. It will appear in the list shortly.');
      }
      return AppProfile.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      // Not deployed on this project yet → legacy sign-up fallback below.
      if ('$e'.toLowerCase().contains('could not find the function')) {
        // continue to the legacy path
      } else {
        throw e is AuthException
            ? e
            : AuthException(_extractMessage('Account registration failed.', e));
      }
    }

    // ── signUp path — the only one that works while this project has no
    // `admin_create_user` Edge Function / RPC deployed. ──
    final sessionBefore = _db.auth.currentSession;

    final res = await _db.auth.signUp(
      email: authEmail,
      password: password,
      data: {
        // `useraccount` has no name columns, so the name is stored here.
        'first_name': trimmedFirstName,
        'middle_name': '',
        'last_name': trimmedLastName,
        'username': trimmedUsername,
        'role': role,
        'is_active': true,
        'must_change_password': true,
      },
    );

    // Restore the registering user's session (signUp auto-confirm replaces it).
    final rt = sessionBefore?.refreshToken;
    if (rt != null) {
      try {
        await _db.auth.setSession(rt, accessToken: sessionBefore?.accessToken);
      } catch (_) {
        // Best effort — the account was still created successfully.
      }
    }

    // `signUp` reports the created account on `user`, even when email
    // confirmation is enabled and therefore no session was handed back.
    final created = res.user;
    if (created?.id == null) {
      throw AuthException(
          'Account created, but its profile could not be loaded. '
          'It will appear in the list shortly.');
    }

    final uid = created!.id;

    // Mirror the new account into `useraccount`, writing every column the table
    // actually has. The name is stored abbreviated (fn / mn / ln) and is also
    // kept in Auth metadata so the account stays readable if RLS hides the row.
    // A failure here is non-fatal: the Auth account exists and can sign in, and
    // [fetchOwn] falls back to metadata.
    try {
      await _db.from('useraccount').insert({
        'user_id': uid,
        'fn': trimmedFirstName,
        'mn': '',
        'ln': trimmedLastName,
        'email': authEmail,
        'username': trimmedUsername,
        'role': role,
        'is_active': true,
        'must_change_password': true,
        'avatar_url': '',
        'created_by': _db.auth.currentUser?.id,
      });
    } catch (_) {
      // RLS may forbid the insert; the account is still usable.
    }

    return profileFromAuthUser(created);
  }

  /// Enables/disables an account. Head-only via RLS +
  /// `prevent_profile_escalation`. Deactivated accounts are rejected on login.
  static Future<void> setActive(String userId, bool isActive) async {
    await _db
        .from('useraccount')
        .update({'is_active': isActive}).eq('user_id', userId);
  }

  /// Removes an account's `useraccount` row, and its Auth user when possible.
  ///
  /// Deleting an Auth user needs the secret admin API, so it is delegated to
  /// the `admin_delete_user` database function. Without that function the Auth
  /// user survives and can still sign in — the account row is removed but the
  /// credentials are not. Use [setActive] to actually block sign-in.
  static Future<void> delete(String userId) async {
    try {
      await _db.rpc('admin_delete_user', params: {'p_user_id': userId});
      return;
    } catch (_) {
      // Function not deployed → remove the row only.
    }
    await _db.from('useraccount').delete().eq('user_id', userId);
  }

  /// Updates the signed-in user's own name + avatar.
  ///
  /// The name is written to BOTH places: `useraccount` (fn / mn / ln), which is
  /// what other users and the Clinic Head see, and Auth `user_metadata`, so the
  /// name is still readable if the row is ever missing or locked down by RLS.
  ///
  /// The `contact` field was removed because the table has no column for it.
  /// The username is deliberately NOT editable here — username changes go
  /// through [updateOwnUsername], which also verifies the current password.
  static Future<void> updateOwnProfile({
    required String firstName,
    String middleName = '',
    required String lastName,
    String avatarUrl = '',
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw AuthException('You are not signed in.');
    }

    final fn = firstName.trim();
    final mn = middleName.trim();
    final ln = lastName.trim();

    await _db.auth.updateUser(UserAttributes(
      data: <String, dynamic>{
        ...metadataOf(user),
        'first_name': fn,
        'middle_name': mn,
        'last_name': ln,
      },
    ));

    try {
      final patch = <String, dynamic>{
        'fn': fn,
        'mn': mn,
        'ln': ln,
      };
      if (avatarUrl.trim().isNotEmpty) patch['avatar_url'] = avatarUrl.trim();
      await _db.from('useraccount').update(patch).eq('user_id', user.id);
    } catch (_) {
      // Row missing or RLS forbids the update — the metadata copy above still
      // keeps the signed-in user's own name correct.
    }
  }

  /// Validates + checks uniqueness of a candidate username (server-side).
  ///
  /// The `is_username_available` RPC only exists once the schema is deployed.
  /// While it is missing this reports "available" rather than `false`: the check
  /// cannot run, and blocking every registration on a function that does not
  /// exist would make signup impossible. Uniqueness is still ultimately enforced
  /// by Auth itself, which rejects a duplicate email.
  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final res = await _db.rpc(
        'is_username_available',
        params: {'p_username': username.trim()},
      );
      return res is bool ? res : true;
    } catch (e) {
      final missing =
          '$e'.toLowerCase().contains('could not find the function');
      if (missing) return true;
      return false;
    }
  }

  /// Optional profile picture: uploads [bytes] for the signed-in user and
  /// saves the public URL on their profile. Uses user-scoped paths
  /// (`avatars/<uid>/profile.<ext>`) so each user can only touch their own
  /// file (enforced by the `avatars` storage policies).
  static Future<String> uploadOwnAvatar(
    Uint8List bytes, {
    String extension = 'png',
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      throw AuthException('You are not signed in.');
    }

    final ext = extension.toLowerCase().replaceAll('.', '');
    final contentTypes = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
    };
    final mime = contentTypes[ext] ?? 'image/png';

    final path = '$uid/profile.$ext';
    await _db.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: mime),
        );

    final url = _db.storage.from('avatars').getPublicUrl(path);
    await _db
        .from('useraccount')
        .update({'avatar_url': url}).eq('user_id', uid);
    return url;
  }

  /// Removes the signed-in user's profile picture (both the stored file and
  /// the `avatar_url` value).
  static Future<void> removeOwnAvatar() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      throw AuthException('You are not signed in.');
    }

    try {
      await _db.storage.from('avatars').remove([
        '$uid/profile.png',
        '$uid/profile.jpg',
        '$uid/profile.jpeg',
        '$uid/profile.gif',
        '$uid/profile.webp',
        '$uid/profile.bmp',
      ]);
    } catch (_) {
      // No stored file yet — fine.
    }
    await _db.from('useraccount').update({'avatar_url': ''}).eq('user_id', uid);
  }

  /// Changes the signed-in user's own username. Auth email stays untouched
  /// (it is derived from the username at creation), so login keeps working.
  static Future<void> updateOwnUsername(String username) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw AuthException('You are not signed in.');
    }

    final clean = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,19}$').hasMatch(clean)) {
      throw AuthException(
          'Username must be 3-20 characters and start with a letter '
          '(letters, numbers, dots, dashes, underscores).');
    }

    try {
      await _db.from('useraccount').update({
        'username': clean,
      }).eq('user_id', user.id);
    } on Exception catch (e) {
      final s = '$e'.toLowerCase();
      if (s.contains('username_lower') ||
          s.contains('unique') ||
          s.contains('duplicate')) {
        throw AuthException('That username is already taken.');
      }
      rethrow;
    }
  }

  /// Changes the signed-in user's own email (the login + password-recovery
  /// address). Delegated to the `update_own_email` database function, which
  /// updates Supabase Auth and `useraccount` together so sign-in by username
  /// keeps resolving to the new address.
  static Future<void> updateOwnEmail(String email, {String? verifier}) async {
    final clean = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) {
      throw AuthException('Enter a valid email address.');
    }
    try {
      await _db.rpc('update_own_email', params: {
        'p_email': clean,
        if (verifier != null && verifier.isNotEmpty) 'p_verifier': verifier,
      });
    } on Exception catch (e) {
      final s = '$e'.toLowerCase();
      if (s.contains('already used') ||
          s.contains('unique') ||
          s.contains('duplicate')) {
        throw AuthException('That email is already used by another account.');
      }
      rethrow;
    }
  }

  /// Forces every new account and every Head-reset account to set a fresh
  /// password: called both after self-initiated password changes and after
  /// the forced first-login / reset flow.
  static Future<void> changePassword(String newPassword) async {
    final user = _db.auth.currentUser;
    // The "must change" flag lives in `user_metadata` on a bare Auth project,
    // so it is cleared through Auth itself. Existing metadata is preserved
    // because `data` replaces the whole map.
    await _db.auth.updateUser(UserAttributes(
      password: newPassword,
      data: <String, dynamic>{
        ...metadataOf(user),
        'must_change_password': false,
      },
    ));

    // Mirror the cleared flag into `useraccount`, which is the authoritative
    // store. A missing row is tolerated so an otherwise successful password
    // change is not reported as a failure.
    if (user != null) {
      try {
        await _db
            .from('useraccount')
            .update({'must_change_password': false}).eq('user_id', user.id);
      } catch (_) {
        // No `useraccount` row yet — the metadata flag is already cleared.
      }
    }
  }

  /// Confirms [password] is the signed-in user's current password by signing
  /// in with it (the same account, so no session switch happens).
  static Future<bool> verifyPassword(String password) async {
    final user = _db.auth.currentUser;
    if (user == null || password.isEmpty) return false;
    try {
      await _db.auth.signInWithPassword(
        email: user.email ?? '',
        password: password,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Generates a strong, human-typed password (no ambiguous 0/O-1/I/l).
  static String generatePassword({int length = 12}) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const all = upper + lower + digits;
    final rnd = Random.secure();
    final buf = StringBuffer();
    buf.write(upper[rnd.nextInt(upper.length)]);
    buf.write(digits[rnd.nextInt(digits.length)]);
    for (var i = 2; i < length; i++) {
      buf.write(all[rnd.nextInt(all.length)]);
    }
    return buf.toString();
  }

  /// Suggests a username from a person's full name (used in the dialog).
  static String suggestUsername(String fullName) {
    final parts = fullName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final base = parts.join('.');
    return base.length > 20 ? base.substring(0, 20) : base;
  }

  /// Head-only password reset. Returns the one-time temporary password so the
  /// Head can show it NOW; it is not stored anywhere client-side afterwards.
  ///
  /// Resets someone ELSE's password, which only Supabase's admin API (the
  /// secret `service_role` key) can do — it is deliberately never shipped in a
  /// client app. That work is therefore delegated to the
  /// `admin_reset_password` database function. If it has not been deployed, a
  /// clear error is raised rather than a raw database message, because there is
  /// no safe client-side substitute.
  static Future<String> resetPasswordFor(
    String userId, {
    String? verifier,
  }) async {
    final temp = generatePassword();

    if (verifier != null && verifier.isNotEmpty) {
      try {
        await _db.rpc('admin_reset_password', params: {
          'p_user_id': userId,
          'p_password': temp,
          'p_verifier': verifier,
        });
        return temp;
      } on PostgrestException catch (e) {
        if (!'$e'.toLowerCase().contains('could not find the function')) {
          rethrow; // function exists but the verification (or reset) failed
        }
        // New overload not deployed yet → fall through to the 2-arg version.
      }
    }

    try {
      await _db.rpc('admin_reset_password', params: {
        'p_user_id': userId,
        'p_password': temp,
      });
      return temp;
    } on PostgrestException catch (e) {
      if ('$e'.toLowerCase().contains('could not find the function')) {
        throw AuthException(
            'Password reset is unavailable: the admin_reset_password function '
            'has not been set up on this project. Set the new password '
            'directly in Supabase → Authentication → Users instead.');
      }
      rethrow;
    }
  }

  static String? _rpcScalar(Object? value) {
    if (value is String) return value;
    if (value is Map) {
      for (final v in value.values) {
        if (v is String) return v;
      }
    }
    return null;
  }

  static String _extractMessage(String fallback, Object err) {
    final s = '$err';
    final lower = s.toLowerCase();
    if (lower.contains('already taken') ||
        lower.contains('already exists') ||
        lower.contains('duplicate')) {
      return 'That username is already taken.';
    }
    if (lower.contains('could not find the function')) {
      return fallback;
    }
    final trimmed = s.trim();
    return trimmed.isNotEmpty ? trimmed : fallback;
  }
}
