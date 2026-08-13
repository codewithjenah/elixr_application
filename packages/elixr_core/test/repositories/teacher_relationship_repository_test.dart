import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_relationship_exception.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/in_memory_teacher_relationship_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherRelationshipRepository repo;
  var codeIndex = 0;
  final codes = ['7KPMXR4DQ2WT', 'ABCD2345EFGH', 'ZZZZ2345YYYY'];

  setUp(() {
    codeIndex = 0;
    repo = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => codes[codeIndex++ % codes.length],
      now: () => DateTime.utc(2026, 8, 13, 8),
    );
  });

  tearDown(() {
    repo.dispose();
  });

  test('createOrRotateInvite stores a 7-day invite for the trainee', () async {
    final invite = await repo.createOrRotateInvite(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
    );

    expect(invite.normalizedCode, '7KPMXR4DQ2WT');
    expect(invite.displayCode, '7KPM-XR4D-Q2WT');
    expect(invite.traineeId, 'trainee-1');
    expect(invite.expiresAt, DateTime.utc(2026, 8, 20, 8));
    expect(await repo.getActiveInvite(traineeId: 'trainee-1'), invite);
  });

  test(
    'rotating invalidates the previous invite and retries collisions',
    () async {
      await repo.createOrRotateInvite(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
      );
      repo.seedInvite(
        TeacherInvite(
          normalizedCode: 'ABCD2345EFGH',
          traineeId: 'other',
          traineeDisplayName: 'Other',
          createdAt: DateTime.utc(2026, 8, 13),
          expiresAt: DateTime.utc(2026, 8, 20),
        ),
      );

      final rotated = await repo.createOrRotateInvite(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
      );

      expect(rotated.normalizedCode, 'ZZZZ2345YYYY');
      expect(repo.invites.containsKey('7KPMXR4DQ2WT'), isFalse);
      expect(repo.invites['ABCD2345EFGH']?.traineeId, 'other');
    },
  );

  test(
    'collisionExhausted is thrown when every generated code exists',
    () async {
      repo = InMemoryTeacherRelationshipRepository(
        generateNormalizedCode: () => '7KPMXR4DQ2WT',
        maxCodeAttempts: 2,
      );
      repo.seedInvite(
        TeacherInvite(
          normalizedCode: '7KPMXR4DQ2WT',
          traineeId: 'other',
          traineeDisplayName: 'Other',
          createdAt: DateTime.utc(2026, 8, 13),
          expiresAt: DateTime.utc(2026, 8, 20),
        ),
      );

      await expectLater(
        repo.createOrRotateInvite(
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada',
        ),
        throwsA(
          isA<TeacherRelationshipException>().having(
            (e) => e.code,
            'code',
            TeacherRelationshipError.collisionExhausted,
          ),
        ),
      );
    },
  );

  test(
    'resolveCoachCode rejects malformed, missing, and expired codes',
    () async {
      await expectLater(
        repo.resolveCoachCode('pin-123'),
        throwsA(
          isA<TeacherRelationshipException>().having(
            (e) => e.code,
            'code',
            TeacherRelationshipError.malformedCode,
          ),
        ),
      );

      await expectLater(
        repo.resolveCoachCode('7KPM-XR4D-Q2WT'),
        throwsA(
          isA<TeacherRelationshipException>().having(
            (e) => e.code,
            'code',
            TeacherRelationshipError.inviteNotFound,
          ),
        ),
      );

      repo.seedInvite(
        TeacherInvite(
          normalizedCode: '7KPMXR4DQ2WT',
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          createdAt: DateTime.utc(2026, 8, 1),
          expiresAt: DateTime.utc(2026, 8, 8),
        ),
      );

      await expectLater(
        repo.resolveCoachCode('7KPM-XR4D-Q2WT'),
        throwsA(
          isA<TeacherRelationshipException>().having(
            (e) => e.code,
            'code',
            TeacherRelationshipError.inviteExpired,
          ),
        ),
      );
    },
  );

  test('requestLink creates a pending deterministic relationship', () async {
    await repo.createOrRotateInvite(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
    );

    final link = await repo.requestLink(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      code: '7kpm-xr4d-q2wt',
    );

    expect(link.id, 'teacher-1_trainee-1');
    expect(link.status, TeacherStudentLinkStatus.pending);
    expect(link.traineeDisplayName, 'Ada Lovelace');
  });

  test(
    'trainee can approve, then revoke; teacher can cancel pending',
    () async {
      await repo.createOrRotateInvite(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
      );
      final link = await repo.requestLink(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        code: '7KPMXR4DQ2WT',
      );

      await repo.cancelLink(linkId: link.id, teacherId: 'teacher-1');
      expect(repo.links[link.id]!.status, TeacherStudentLinkStatus.cancelled);

      await repo.requestLink(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        code: '7KPMXR4DQ2WT',
      );
      await repo.approveLink(linkId: link.id, traineeId: 'trainee-1');
      expect(repo.links[link.id]!.isApproved, isTrue);

      await repo.revokeLink(linkId: link.id, traineeId: 'trainee-1');
      expect(repo.links[link.id]!.status, TeacherStudentLinkStatus.revoked);
    },
  );

  test(
    'reject leaves the deterministic document for later re-request',
    () async {
      await repo.createOrRotateInvite(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
      );
      final link = await repo.requestLink(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        code: '7KPMXR4DQ2WT',
      );
      await repo.rejectLink(linkId: link.id, traineeId: 'trainee-1');
      expect(repo.links[link.id]!.status, TeacherStudentLinkStatus.rejected);

      final again = await repo.requestLink(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        code: '7KPMXR4DQ2WT',
      );
      expect(again.status, TeacherStudentLinkStatus.pending);
    },
  );
}
