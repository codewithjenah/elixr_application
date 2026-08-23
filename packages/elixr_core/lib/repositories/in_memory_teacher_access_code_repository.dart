import '../models/coach_code.dart';
import '../models/teacher_access_code.dart';
import '../models/teacher_access_code_exception.dart';
import '../models/user.dart';
import 'teacher_access_code_repository.dart';

class InMemoryTeacherAccessCodeRepository
    implements TeacherAccessCodeRepository {
  InMemoryTeacherAccessCodeRepository({
    String Function()? generateNormalizedCode,
    DateTime Function()? now,
    this.maxCodeAttempts = 8,
  }) : generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized,
       _now = now;

  final String Function() generateNormalizedCode;
  final DateTime Function()? _now;
  final int maxCodeAttempts;

  final Map<String, TeacherAccessCode> codes = {};
  final Map<String, User> users = {};

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  void seed(TeacherAccessCode code) {
    codes[code.normalizedCode] = code;
  }

  @override
  Future<void> assertRedeemable(String? code) async {
    _requireUnconsumed(code);
  }

  @override
  Future<void> consumeAndCreateTeacherProfile({
    required String code,
    required User user,
    bool includePrivacyConsent = true,
  }) async {
    final parsed = _requireUnconsumed(code);
    final userId = user.id;
    if (userId == null || userId.isEmpty) {
      throw ArgumentError('User id is required');
    }
    if (user.role != User.roleTeacher) {
      throw ArgumentError('Consumed codes may only create Teacher profiles.');
    }
    if (users.containsKey(userId)) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.forbidden,
        'A profile already exists for this account.',
      );
    }
    codes[parsed.normalizedCode] = TeacherAccessCode(
      normalizedCode: parsed.normalizedCode,
      consumed: true,
      createdAt: parsed.createdAt,
      note: parsed.note,
      createdBy: parsed.createdBy,
      consumedBy: userId,
      consumedAt: now,
    );
    users[userId] = user;
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
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized) ||
          codes.containsKey(normalized)) {
        continue;
      }
      final trimmedNote = note?.trim();
      final minted = TeacherAccessCode(
        normalizedCode: normalized,
        consumed: false,
        createdAt: now,
        note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
        createdBy: createdBy,
      );
      codes[normalized] = minted;
      return minted;
    }
    throw const TeacherAccessCodeException(
      TeacherAccessCodeError.collisionExhausted,
      'Could not allocate a unique Teacher access code.',
    );
  }

  TeacherAccessCode _requireUnconsumed(String? code) {
    final normalized = CoachCode.tryNormalize(code ?? '');
    if (normalized == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'A valid Teacher access code is required.',
      );
    }
    final existing = codes[normalized];
    if (existing == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.notFound,
        'That Teacher access code is invalid or has already been used.',
      );
    }
    if (existing.consumed) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.alreadyConsumed,
        'That Teacher access code is invalid or has already been used.',
      );
    }
    return existing;
  }
}
