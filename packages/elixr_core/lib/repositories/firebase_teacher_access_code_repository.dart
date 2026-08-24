import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../database/user_profile_store.dart';
import '../models/coach_code.dart';
import '../models/teacher_access_code.dart';
import '../models/teacher_access_code_exception.dart';
import '../models/user.dart';
import '../privacy/privacy_consent.dart';
import 'teacher_access_code_repository.dart';

class FirebaseTeacherAccessCodeRepository
    implements TeacherAccessCodeRepository {
  FirebaseTeacherAccessCodeRepository({
    FirebaseFirestore? firestore,
    String Function()? generateNormalizedCode,
    this.maxCodeAttempts = 8,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized;

  final FirebaseFirestore _firestore;
  final String Function() _generateNormalizedCode;
  final int maxCodeAttempts;

  CollectionReference<Map<String, dynamic>> get _codes =>
      _firestore.collection(FirestoreCollections.teacherAccessCodes);
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestoreCollections.users);

  @override
  Future<void> assertRedeemable(String? code) async {
    await _loadUnconsumed(code);
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
    final userId = user.id;
    if (userId == null || userId.isEmpty) {
      throw ArgumentError('User id is required');
    }
    if (user.role != User.roleTeacher) {
      throw ArgumentError('Consumed codes may only create Teacher profiles.');
    }

    final codeRef = _codes.doc(normalized);
    final userRef = _users.doc(userId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(codeRef);
      final existingUser = await transaction.get(userRef);
      if (existingUser.exists) {
        throw const TeacherAccessCodeException(
          TeacherAccessCodeError.forbidden,
          'A profile already exists for this account.',
        );
      }
      final parsed = snapshot.exists
          ? TeacherAccessCode.tryFromMap(
              snapshot.data() ?? const {},
              id: snapshot.id,
            )
          : null;
      if (parsed == null) {
        throw const TeacherAccessCodeException(
          TeacherAccessCodeError.notFound,
          'That Teacher access code is invalid or has already been used.',
        );
      }
      if (parsed.consumed) {
        throw const TeacherAccessCodeException(
          TeacherAccessCodeError.alreadyConsumed,
          'That Teacher access code is invalid or has already been used.',
        );
      }

      transaction.update(codeRef, {
        'consumed': true,
        'consumed_by': userId,
        'consumed_at': FieldValue.serverTimestamp(),
      });
      transaction.set(userRef, {
        ...FirebaseUserProfileStore.userProfileWriteData(
          user,
          legalConsent: legalConsent,
        ),
        'teacher_access_code': normalized,
      });
    });
  }

  @override
  Future<User?> reconcileTeacherProfile({
    required User expectedUser,
    required String code,
  }) async {
    final userId = expectedUser.id;
    final normalized = CoachCode.tryNormalize(code);
    if (userId == null || normalized == null) return null;
    final snapshot = await _users.doc(userId).get();
    if (!snapshot.exists) return null;
    final profile = User.fromMap({
      'id': snapshot.id,
      ...snapshot.data()!,
      'created_at': FirebaseUserProfileStore.readCreatedAt(
        snapshot.data()!['created_at'],
      ),
      'privacy_consent_at': FirebaseUserProfileStore.readCreatedAt(
        snapshot.data()!['privacy_consent_at'],
      ),
      'terms_consent_at': FirebaseUserProfileStore.readCreatedAt(
        snapshot.data()!['terms_consent_at'],
      ),
    });
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
    final trimmedNote = note?.trim();
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = _generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized)) continue;
      final ref = _codes.doc(normalized);
      if ((await ref.get()).exists) continue;
      try {
        await ref.set({
          'consumed': false,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': createdBy,
          if (trimmedNote != null && trimmedNote.isNotEmpty)
            'note': trimmedNote,
        });
      } on FirebaseException {
        continue;
      }
      return TeacherAccessCode(
        normalizedCode: normalized,
        consumed: false,
        createdAt: DateTime.now().toUtc(),
        note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
        createdBy: createdBy,
      );
    }
    throw const TeacherAccessCodeException(
      TeacherAccessCodeError.collisionExhausted,
      'Could not allocate a unique Teacher access code.',
    );
  }

  Future<TeacherAccessCode> _loadUnconsumed(String? code) async {
    final normalized = CoachCode.tryNormalize(code ?? '');
    if (normalized == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'A valid Teacher access code is required.',
      );
    }
    final snapshot = await _codes.doc(normalized).get();
    final parsed = snapshot.exists
        ? TeacherAccessCode.tryFromMap(
            snapshot.data() ?? const {},
            id: snapshot.id,
          )
        : null;
    if (parsed == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.notFound,
        'That Teacher access code is invalid or has already been used.',
      );
    }
    if (parsed.consumed) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.alreadyConsumed,
        'That Teacher access code is invalid or has already been used.',
      );
    }
    return parsed;
  }
}
