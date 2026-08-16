import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherRelationshipRepository repository;
  var codeIndex = 0;
  final codes = ['7KPMXR4DQ2WT', 'ABCD2345EFGH', 'ZZZZ2345YYYY'];

  setUp(() {
    codeIndex = 0;
    repository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => codes[codeIndex++ % codes.length],
      now: () => DateTime.utc(2026, 8, 16, 8),
    );
  });

  tearDown(() => repository.dispose());

  test('Teacher roster invite is durable until rotated or revoked', () async {
    final invite = await repository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    expect(invite.displayCode, '7KPM-XR4D-Q2WT');
    expect(invite.teacherId, 'teacher-1');
    expect(invite.joinUri.toString(), 'elixr://join?code=7KPMXR4DQ2WT');
    expect(
      await repository.getActiveRosterInvite(teacherId: 'teacher-1'),
      same(invite),
    );

    final rotated = await repository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    expect(rotated.normalizedCode, 'ABCD2345EFGH');
    await expectLater(
      repository.resolveRosterCode('7KPM-XR4D-Q2WT'),
      throwsA(isA<TeacherRelationshipException>()),
    );

    await repository.revokeRosterInvite(teacherId: 'teacher-1');
    expect(
      await repository.getActiveRosterInvite(teacherId: 'teacher-1'),
      isNull,
    );
  });

  test('collisions are retried without overwriting another Teacher', () async {
    repository.seedInvite(
      TeacherRosterInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        teacherId: 'other',
        teacherDisplayName: 'Other Teacher',
        createdAt: DateTime.utc(2026, 8, 1),
      ),
    );
    final invite = await repository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    expect(invite.normalizedCode, 'ABCD2345EFGH');
    expect(repository.invites['7KPMXR4DQ2WT']?.teacherId, 'other');
  });

  test('Trainee creates V2 request and Teacher decides it', () async {
    await repository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    final link = await repository.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: '7kpm-xr4d-q2wt',
    );
    expect(link.id, 'teacher-1_trainee-1');
    expect(link.requestVersion, 2);
    expect(link.status, TeacherStudentLinkStatus.pending);

    await repository.approveJoin(linkId: link.id, teacherId: 'teacher-1');
    expect(repository.links[link.id]?.isApproved, isTrue);
  });

  test(
    'legacy non-approved row is superseded, approved row is preserved',
    () async {
      await repository.createOrRotateRosterInvite(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
      );
      repository.seedLink(
        const TeacherStudentLink(
          id: 'teacher-1_trainee-1',
          teacherId: 'teacher-1',
          traineeId: 'trainee-1',
          teacherDisplayName: 'Old Teacher',
          traineeDisplayName: 'Old Trainee',
          status: TeacherStudentLinkStatus.rejected,
        ),
      );
      final replaced = await repository.requestTeacherJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: '7KPMXR4DQ2WT',
      );
      expect(replaced.isV2Request, isTrue);
      expect(replaced.teacherDisplayName, 'Grace Hopper');

      await repository.approveJoin(linkId: replaced.id, teacherId: 'teacher-1');
      await expectLater(
        repository.requestTeacherJoin(
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          code: '7KPMXR4DQ2WT',
        ),
        throwsA(
          isA<TeacherRelationshipException>().having(
            (error) => error.code,
            'code',
            TeacherRelationshipError.alreadyLinked,
          ),
        ),
      );
    },
  );

  test('progress withdrawal and relationship revoke clear evidence', () async {
    await repository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    final link = await repository.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: '7KPMXR4DQ2WT',
    );
    await repository.approveJoin(linkId: link.id, teacherId: 'teacher-1');
    await repository.grantProgressAccess(
      linkId: link.id,
      traineeId: 'trainee-1',
    );
    await repository.grantEvidenceAccess(
      linkId: link.id,
      traineeId: 'trainee-1',
    );
    expect(repository.links[link.id]?.hasEffectiveEvidenceAccess, isTrue);

    await repository.removeProgressAccess(
      linkId: link.id,
      traineeId: 'trainee-1',
    );
    expect(repository.links[link.id]?.hasEffectiveEvidenceAccess, isFalse);
    expect(
      repository.links[link.id]?.evidenceAccess,
      TeacherProgressAccess.none,
    );
  });

  test('Trainee can revoke a legacy approved relationship', () async {
    repository.seedLink(
      TeacherStudentLink(
        id: 'teacher-1_trainee-1',
        teacherId: 'teacher-1',
        traineeId: 'trainee-1',
        teacherDisplayName: 'Grace Hopper',
        traineeDisplayName: 'Ada Lovelace',
        status: TeacherStudentLinkStatus.approved,
        createdAt: DateTime.utc(2025, 1, 1),
      ),
    );

    await repository.revokeLink(
      linkId: 'teacher-1_trainee-1',
      traineeId: 'trainee-1',
    );

    expect(
      repository.links['teacher-1_trainee-1']?.status,
      TeacherStudentLinkStatus.revoked,
    );
  });
}
