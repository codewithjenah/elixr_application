import 'dart:typed_data';

import 'package:elixr_core/repositories/firebase_teacher_evidence_repository.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only Storage object-not-found as an unavailable image', () {
    expect(
      FirebaseTeacherEvidenceRepository.isObjectNotFound(
        FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
      ),
      isTrue,
    );
    expect(
      FirebaseTeacherEvidenceRepository.isObjectNotFound(
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'permission-denied',
        ),
      ),
      isFalse,
    );
  });

  test('refreshes a stale auth token and retries the download once', () async {
    var attempts = 0;
    var refreshes = 0;
    final repository = FirebaseTeacherEvidenceRepository(
      downloadData: (path, maximumBytes) async {
        attempts++;
        expect(path, 'users/trainee/session_evidence/session.jpg');
        expect(maximumBytes, 256 * 1024);
        if (attempts == 1) {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
          );
        }
        return Uint8List.fromList([1, 2, 3]);
      },
      forceRefreshIdToken: () async => refreshes++,
    );

    final bytes = await repository.downloadEvidence(
      traineeId: 'trainee',
      sessionId: 'session',
    );

    expect(bytes, orderedEquals([1, 2, 3]));
    expect(attempts, 2);
    expect(refreshes, 1);
  });

  test('does not retry a non-auth Storage failure', () async {
    var attempts = 0;
    var refreshes = 0;
    final repository = FirebaseTeacherEvidenceRepository(
      downloadData: (_, _) async {
        attempts++;
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'quota-exceeded',
        );
      },
      forceRefreshIdToken: () async => refreshes++,
    );

    await expectLater(
      repository.downloadEvidence(traineeId: 'trainee', sessionId: 'session'),
      throwsA(
        isA<FirebaseException>().having(
          (error) => error.code,
          'code',
          'quota-exceeded',
        ),
      ),
    );
    expect(attempts, 1);
    expect(refreshes, 0);
  });

  test('a missing object after auth refresh remains unavailable', () async {
    var attempts = 0;
    final repository = FirebaseTeacherEvidenceRepository(
      downloadData: (_, _) async {
        attempts++;
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: attempts == 1 ? 'unauthenticated' : 'object-not-found',
        );
      },
      forceRefreshIdToken: () async {},
    );

    expect(
      await repository.downloadEvidence(
        traineeId: 'trainee',
        sessionId: 'session',
      ),
      isNull,
    );
    expect(attempts, 2);
  });
}
