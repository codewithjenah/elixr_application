import 'dart:async';

import '../models/coach_code.dart';
import '../models/teacher_access_code.dart';
import '../models/teacher_access_code_exception.dart';
import '../models/user.dart';
import '../privacy/privacy_consent.dart';
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
  final _createdByControllers =
      <String, StreamController<List<TeacherAccessCode>>>{};

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  void seed(TeacherAccessCode code) {
    codes[code.normalizedCode] = code;
    _emitCreatedBy();
  }

  void dispose() {
    for (final controller in _createdByControllers.values) {
      controller.close();
    }
    _createdByControllers.clear();
  }

  @override
  Future<void> assertRedeemable(String? code) async {
    _requireUnconsumed(code);
  }

  @override
  Future<void> consumeAndCreateTeacherProfile({
    required String code,
    required User user,
    required RegistrationLegalConsent legalConsent,
  }) async {
    if (!legalConsent.isCurrent) {
      throw ArgumentError('Current registration legal consent is required.');
    }
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
    _emitCreatedBy();
  }

  @override
  Future<User?> reconcileTeacherProfile({
    required User expectedUser,
    required String code,
  }) async {
    final normalized = CoachCode.tryNormalize(code);
    final existing = users[expectedUser.id];
    if (normalized == null || existing == null) return null;
    return existing.role == User.roleTeacher &&
            existing.teacherAccessCode == normalized &&
            existing.email.trim().toLowerCase() ==
                expectedUser.email.trim().toLowerCase()
        ? existing
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
      _emitCreatedBy();
      return minted;
    }
    throw const TeacherAccessCodeException(
      TeacherAccessCodeError.collisionExhausted,
      'Could not allocate a unique Teacher access code.',
    );
  }

  @override
  Stream<List<TeacherAccessCode>> watchCreatedBy(String teacherId) {
    final existing = _createdByControllers[teacherId];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<TeacherAccessCode>> controller;
    controller = StreamController<List<TeacherAccessCode>>.broadcast(
      onListen: () => controller.add(_codesCreatedBy(teacherId)),
    );
    _createdByControllers[teacherId] = controller;
    return controller.stream;
  }

  @override
  Future<void> deleteUnused({
    required String createdBy,
    required String normalizedCode,
  }) async {
    final parsed = _requireUnconsumed(normalizedCode);
    if (parsed.createdBy != createdBy) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.forbidden,
        'Only the Teacher who created this code can revoke it.',
      );
    }
    codes.remove(parsed.normalizedCode);
    _emitCreatedBy();
  }

  List<TeacherAccessCode> _codesCreatedBy(String teacherId) {
    return [
      for (final code in codes.values)
        if (code.createdBy == teacherId) code,
    ];
  }

  void _emitCreatedBy() {
    for (final entry in _createdByControllers.entries) {
      if (!entry.value.isClosed) {
        entry.value.add(_codesCreatedBy(entry.key));
      }
    }
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
