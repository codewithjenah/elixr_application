import 'package:supabase/supabase.dart' hide User;

import '../database/supabase_support.dart';
import '../database/user_profile_store.dart';
import '../models/coach_code.dart';
import '../models/teacher_access_code.dart';
import '../models/teacher_access_code_exception.dart';
import '../models/user.dart';
import '../privacy/privacy_consent.dart';
import 'teacher_access_code_repository.dart';

class SupabaseTeacherAccessCodeRepository
    implements TeacherAccessCodeRepository {
  SupabaseTeacherAccessCodeRepository({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static const _invalidMessage =
      'That Teacher access code is invalid or has already been used.';

  /// Maps database error codes to the established typed exception.
  static TeacherAccessCodeException? exceptionFor(Object error) {
    return switch (backendErrorCode(error)) {
      'malformed_code' => const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'A valid Teacher access code is required.',
      ),
      'access_code_not_found' => const TeacherAccessCodeException(
        TeacherAccessCodeError.notFound,
        _invalidMessage,
      ),
      'access_code_consumed' => const TeacherAccessCodeException(
        TeacherAccessCodeError.alreadyConsumed,
        _invalidMessage,
      ),
      'profile_exists' => const TeacherAccessCodeException(
        TeacherAccessCodeError.forbidden,
        'A profile already exists for this account.',
      ),
      'forbidden' => const TeacherAccessCodeException(
        TeacherAccessCodeError.forbidden,
        'Only a verified Teacher can manage access codes.',
      ),
      'collision_exhausted' => const TeacherAccessCodeException(
        TeacherAccessCodeError.collisionExhausted,
        'Could not allocate a unique Teacher access code.',
      ),
      _ => null,
    };
  }

  Future<T> _mapped<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw exceptionFor(error) ?? error;
    }
  }

  @override
  Future<void> assertRedeemable(String? code) {
    final normalized = CoachCode.tryNormalize(code ?? '');
    if (normalized == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'A valid Teacher access code is required.',
      );
    }
    return _mapped(
      () => _client.rpc<dynamic>(
        'check_teacher_access_code',
        params: {'p_code': normalized},
      ),
    );
  }

  @override
  Future<void> consumeAndCreateTeacherProfile({
    required String code,
    required User user,
    required RegistrationLegalConsent legalConsent,
  }) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'A valid Teacher access code is required.',
      );
    }
    if (user.id == null || user.id!.isEmpty) {
      throw ArgumentError('User id is required');
    }
    if (user.role != User.roleTeacher) {
      throw ArgumentError('Consumed codes may only create Teacher profiles.');
    }
    // One database transaction locks, validates and consumes the code while
    // creating the Teacher profile.
    await _mapped(
      () => _client.rpc<dynamic>(
        'create_own_profile',
        params: SupabaseUserProfileStore.createProfileParams(
          user.copyWith(teacherAccessCode: normalized),
          legalConsent: legalConsent,
        ),
      ),
    );
  }

  @override
  Future<User?> reconcileTeacherProfile({
    required User expectedUser,
    required String code,
  }) async {
    final userId = expectedUser.id;
    final normalized = CoachCode.tryNormalize(code);
    if (userId == null || normalized == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    final profile = SupabaseUserProfileStore.userFromRow(row);
    return profile.id == expectedUser.id &&
            profile.email.trim().toLowerCase() ==
                expectedUser.email.trim().toLowerCase() &&
            profile.role == User.roleTeacher &&
            profile.teacherAccessCode == normalized
        ? profile
        : null;
  }

  @override
  Future<TeacherAccessCode> mint({
    required String createdBy,
    String? note,
  }) async {
    if (createdBy.trim().isEmpty) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.forbidden,
        'Only a Teacher can mint an access code.',
      );
    }
    final row = await _mapped(
      () => rpcMap(_client, 'mint_teacher_access_code', {'p_note': note}),
    );
    final parsed = TeacherAccessCode.tryFromMap(row, id: row['code'] as String);
    if (parsed == null) {
      throw const FormatException('Malformed Teacher access code.');
    }
    return parsed;
  }

  @override
  Stream<List<TeacherAccessCode>> watchCreatedBy(String teacherId) {
    return _client
        .from('teacher_access_codes')
        .stream(primaryKey: ['code'])
        .eq('created_by', teacherId)
        .map(
          (rows) => [
            for (final row in rows)
              ?TeacherAccessCode.tryFromMap(
                compactRow(row),
                id: row['code'] as String,
              ),
          ],
        );
  }

  @override
  Future<void> deleteUnused({
    required String createdBy,
    required String normalizedCode,
  }) async {
    final normalized = CoachCode.tryNormalize(normalizedCode);
    if (normalized == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'A valid Teacher access code is required.',
      );
    }
    final row = await _client
        .from('teacher_access_codes')
        .select()
        .eq('code', normalized)
        .maybeSingle();
    final parsed = row == null
        ? null
        : TeacherAccessCode.tryFromMap(compactRow(row), id: normalized);
    if (parsed == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.notFound,
        _invalidMessage,
      );
    }
    if (parsed.consumed) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.alreadyConsumed,
        _invalidMessage,
      );
    }
    if (parsed.createdBy != createdBy) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.forbidden,
        'Only the Teacher who created this code can revoke it.',
      );
    }
    // RLS permits deleting only the caller's own unconsumed codes.
    await _client
        .from('teacher_access_codes')
        .delete()
        .eq('code', normalized)
        .eq('consumed', false);
  }
}
