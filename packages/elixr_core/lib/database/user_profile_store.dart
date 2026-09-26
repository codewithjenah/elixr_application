import 'package:supabase/supabase.dart' hide User;

import '../models/user.dart';
import '../privacy/privacy_consent.dart';
import 'supabase_support.dart';

/// Persistence for the caller's `profiles` row.
abstract class UserProfileStore {
  Future<void> upsertUserProfile(
    User user, {
    RegistrationLegalConsent? legalConsent,
  });

  /// Updates allow-listed fields of the caller's own profile. A `null` value
  /// removes an optional field.
  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  );

  Future<User?> getUserById(String id);
}

/// Supabase-backed [UserProfileStore] shared by ELIXR clients. Role, consent
/// timestamps and access-code consumption are server-controlled.
class SupabaseUserProfileStore implements UserProfileStore {
  SupabaseUserProfileStore({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  /// Parameters for `create_own_profile`. Consent is recorded server-side
  /// with the database clock; only the accepted document versions are sent.
  static Map<String, dynamic> createProfileParams(
    User user, {
    required RegistrationLegalConsent legalConsent,
  }) {
    if (!legalConsent.isCurrent) {
      throw ArgumentError('Current registration legal consent is required.');
    }
    return {
      'p_role': user.role,
      'p_first_name': user.firstName,
      'p_middle_name': user.middleName,
      'p_last_name': user.lastName,
      'p_privacy_policy_version': legalConsent.privacyPolicyVersion,
      'p_terms_of_service_version': legalConsent.termsOfServiceVersion,
      'p_teacher_access_code': user.teacherAccessCode,
    };
  }

  static User userFromRow(Map<String, dynamic> row) =>
      User.fromMap(compactRow(row));

  @override
  Future<void> upsertUserProfile(
    User user, {
    RegistrationLegalConsent? legalConsent,
  }) async {
    if (user.id == null) {
      throw ArgumentError('User id is required');
    }
    final existing = await getUserById(user.id!);
    if (existing == null) {
      if (legalConsent == null) {
        throw ArgumentError('Legal consent is required to create a profile.');
      }
      await _client.rpc<dynamic>(
        'create_own_profile',
        params: createProfileParams(user, legalConsent: legalConsent),
      );
      return;
    }
    await updateUserProfileField(user.id!, {
      'first_name': user.firstName,
      'middle_name': user.middleName,
      'last_name': user.lastName,
    });
  }

  @override
  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    final current = _client.auth.currentUser?.id;
    if (current == null || current != userId) {
      throw StateError('Profiles can only be updated by their owner.');
    }
    await _client.rpc<dynamic>(
      'update_own_profile',
      params: {'p_fields': fields},
    );
  }

  @override
  Future<User?> getUserById(String id) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return userFromRow(row);
  }
}
