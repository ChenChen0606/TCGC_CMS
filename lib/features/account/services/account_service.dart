import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/services/profile_state.dart';

class AppProfile {
  final String id;
  final String firstName;
  final String middleName;
  final String lastName;
  final String username;
  final String email;
  final String avatarUrl;
  final String role;
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
    this.avatarUrl = '',
    this.role = 'Clinic Staff',
    this.isActive = true,
    this.mustChangePassword = false,
    this.createdAt,
  });

  String get fullName =>
      [firstName, middleName, lastName].where((s) => s.isNotEmpty).join(' ');

  String get displayName => fullName.isNotEmpty ? fullName : username;

  factory AppProfile.fromSupabase(Map<String, dynamic> row) {
    return AppProfile(
      id: row['user_id'] as String? ?? '',
      firstName: (row['fn'] as String? ?? '').trim(),
      middleName: (row['mn'] as String? ?? '').trim(),
      lastName: (row['ln'] as String? ?? '').trim(),
      username: (row['username'] as String? ?? '').trim(),
      email: (row['email'] as String? ?? '').trim(),
      avatarUrl: (row['avatar_url'] as String? ?? '').trim(),
      role: (row['role'] as String?)?.isNotEmpty == true
          ? row['role'] as String
          : 'Clinic Staff',
      isActive: row['is_active'] as bool? ?? true,
      mustChangePassword: row['must_change_password'] as bool? ?? false,
      createdAt: _parseTs(row['created_at']),
    );
  }

  /// Fills what this row lacks from [other] (the auth metadata). Names are
  /// taken from ONE source only: if the row has any name, all three come from
  /// it, so a cleared middle name stays cleared instead of coming back from
  /// the old metadata.
  AppProfile withNamesFrom(AppProfile other) {
    final useOwnNames = fullName.isNotEmpty;
    return AppProfile(
      id: id.isNotEmpty ? id : other.id,
      firstName: useOwnNames ? firstName : other.firstName,
      middleName: useOwnNames ? middleName : other.middleName,
      lastName: useOwnNames ? lastName : other.lastName,
      username: username.isNotEmpty ? username : other.username,
      email: email.isNotEmpty ? email : other.email,
      avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : other.avatarUrl,
      role: role,
      isActive: isActive,
      mustChangePassword: mustChangePassword,
      createdAt: createdAt ?? other.createdAt,
    );
  }

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

/// Everything the app needs to open the main screen for a signed-in user.
class SessionInfo {
  const SessionInfo(this.profile, this.email, this.username);

  final AppProfile profile;
  final String email;
  final String username;

  String get role => profile.role;
  bool get mustChangePassword => profile.mustChangePassword;
  String get name => profile.displayName.isNotEmpty ? profile.displayName : username;
}

class AccountService {
  AccountService._();

  static SupabaseClient get _db => supabaseClient;

  static final RegExp usernamePattern =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]{2,19}$');

  static const String authEmailDomain = 'clinic.local';

  static String authEmailForIdentifier(String identifier) {
    final value = identifier.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value.contains('@')) return value;
    return '$value@$authEmailDomain';
  }

  static String usernameFromAuthEmail(String? email) {
    final value = (email ?? '').trim();
    if (value.isEmpty) return '';
    final at = value.lastIndexOf('@');
    return (at > 0 ? value.substring(0, at) : value).trim();
  }

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
      avatarUrl: _metaString(meta, 'avatar_url'),
      role: _metaString(meta, 'role').isNotEmpty
          ? _metaString(meta, 'role')
          : 'Clinic Staff',
      isActive: _metaBool(meta, 'is_active', true),
      mustChangePassword: _metaBool(meta, 'must_change_password', false),
      createdAt: AppProfile._parseTs(user?.createdAt),
    );
  }

  static String get currentUserId => _db.auth.currentUser?.id ?? '';

  static bool get canSeeRestrictedCounselling {
    final role = profileFromAuthUser(_db.auth.currentUser).role;
    return role == 'Clinic Head' || role == 'Clinic Staff';
  }

  static List<AppProfile> _profiles(List<dynamic> rows) => [
        for (final r in rows)
          AppProfile.fromSupabase(Map<String, dynamic>.from(r as Map))
      ];

  static Future<List<AppProfile>> fetchAll() async =>
      _profiles(await _db.from('useraccount').select().order('created_at'));

  static Future<List<AppProfile>> fetchActiveClinicHeads() async =>
      _profiles(await _db
          .from('useraccount')
          .select()
          .eq('role', 'Clinic Head')
          .eq('is_active', true)
          .order('ln'));

  static Future<Map<String, dynamic>?> _ownRow(String uid) async {
    final row =
        await _db.from('useraccount').select().eq('user_id', uid).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  static AppProfile _merge(Map<String, dynamic>? row, User user) {
    final fromAuth = profileFromAuthUser(user);
    return row == null
        ? fromAuth
        : AppProfile.fromSupabase(row).withNamesFrom(fromAuth);
  }

  static Future<AppProfile?> fetchOwn() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    try {
      return _merge(await _ownRow(user.id), user);
    } catch (_) {
      return profileFromAuthUser(user);
    }
  }

  /// Used by the login screen and by the page-refresh restore, so both open
  /// the app the same way. Returns null (after signing out) when the account
  /// is deactivated.
  static Future<SessionInfo?> openSession(User user) async {
    Map<String, dynamic>? row;
    try {
      row = await _ownRow(user.id);
    } catch (e) {
      debugPrint('SESSION: useraccount fetch failed: $e');
    }

    final profile = _merge(row, user);
    if (!profile.isActive) {
      await _db.auth.signOut();
      return null;
    }

    final username = profile.username.isNotEmpty
        ? profile.username
        : usernameFromAuthEmail(user.email);
    return SessionInfo(profile, user.email ?? '', username);
  }

  static Future<String?> resolveAuthEmailForIdentifier(
      String identifier) async {
    final value = identifier.trim().toLowerCase();
    if (value.isEmpty) return null;

    if (value.contains('@')) return value;

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
    } catch (_) {}

    try {
      final row = await _db
          .from('useraccount')
          .select('email')
          .eq('username', value)
          .maybeSingle();
      final email = row == null ? null : (row['email'] as String?)?.trim();
      if (email != null && email.isNotEmpty) return email;
    } catch (_) {}

    return authEmailForIdentifier(value);
  }

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

    final trimmedEmail = email.trim().toLowerCase();
    final authEmail = trimmedEmail.isNotEmpty
        ? trimmedEmail
        : authEmailForIdentifier(trimmedUsername);

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
      return await _createdProfile(uid);
    } on Exception catch (e) {
      if (e is FunctionException && e.status != 404 && e.status != 308) {
        final details = e.details;
        final msg = details is Map && details['error'] is String
            ? details['error'] as String
            : null;
        throw AuthException((msg == null || msg.isEmpty)
            ? 'Account registration failed.'
            : msg);
      }
    }

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
      return await _createdProfile(id);
    } catch (e) {
      if ('$e'.toLowerCase().contains('could not find the function')) {
      } else {
        throw e is AuthException
            ? e
            : AuthException(_extractMessage('Account registration failed.', e));
      }
    }

    final sessionBefore = _db.auth.currentSession;

    final res = await _db.auth.signUp(
      email: authEmail,
      password: password,
      data: {
        'first_name': trimmedFirstName,
        'middle_name': '',
        'last_name': trimmedLastName,
        'username': trimmedUsername,
        'role': role,
        'is_active': true,
        'must_change_password': true,
      },
    );

    final rt = sessionBefore?.refreshToken;
    if (rt != null) {
      try {
        await _db.auth.setSession(rt, accessToken: sessionBefore?.accessToken);
      } catch (_) {}
    }

    final created = res.user;
    if (created?.id == null) {
      throw AuthException(
          'Account created, but its profile could not be loaded. '
          'It will appear in the list shortly.');
    }

    final uid = created!.id;

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
    } catch (_) {}

    return profileFromAuthUser(created);
  }

  static Future<AppProfile> _createdProfile(String uid) async {
    final row = await _ownRow(uid);
    if (row == null) {
      throw AuthException(
          'Account was created. Refresh the list to see it appear.');
    }
    return AppProfile.fromSupabase(row);
  }

  static Future<void> setActive(String userId, bool isActive) async {
    await _db
        .from('useraccount')
        .update({'is_active': isActive}).eq('user_id', userId);
  }

  static Future<void> delete(String userId) async {
    try {
      await _db.rpc('admin_delete_user', params: {'p_user_id': userId});
      return;
    } catch (_) {}
    await _db.from('useraccount').delete().eq('user_id', userId);
  }

  /// Saves the signed-in user's name. The database row is written first and
  /// checked (a blocked update used to be ignored silently), then the auth
  /// metadata is kept in step, and finally the shared name every screen shows
  /// is refreshed.
  static Future<AppProfile> updateOwnProfile({
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

    final rows = await _db
        .from('useraccount')
        .update({
          'fn': fn,
          'mn': mn,
          'ln': ln,
          if (avatarUrl.trim().isNotEmpty) 'avatar_url': avatarUrl.trim(),
        })
        .eq('user_id', user.id)
        .select();
    if (rows.isEmpty) {
      throw AuthException('Your profile could not be saved. '
          'Your account may not have permission to edit it.');
    }

    try {
      await _db.auth.updateUser(UserAttributes(data: <String, dynamic>{
        ...metadataOf(user),
        'first_name': fn,
        'middle_name': mn,
        'last_name': ln,
      }));
    } catch (e) {
      // The database already holds the new name; the metadata is only a
      // fallback copy, so this must not fail the save.
      debugPrint('PROFILE: metadata update failed: $e');
    }

    final profile = _merge(Map<String, dynamic>.from(rows.first as Map),
        _db.auth.currentUser ?? user);
    ProfileState.set(profile.displayName);
    return profile;
  }

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
    } catch (_) {}
    await _db.from('useraccount').update({'avatar_url': ''}).eq('user_id', uid);
  }

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

  static Future<void> changePassword(String newPassword) async {
    final user = _db.auth.currentUser;

    await _db.auth.updateUser(UserAttributes(
      password: newPassword,
      data: <String, dynamic>{
        ...metadataOf(user),
        'must_change_password': false,
      },
    ));

    if (user != null) {
      try {
        await _db
            .from('useraccount')
            .update({'must_change_password': false}).eq('user_id', user.id);
      } catch (_) {}
    }
  }

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
          rethrow;
        }
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
