import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validCode = '7KPMXR4DQ2WT';
  final teacher = User(
    id: 'teacher-new',
    firstName: 'Grace',
    lastName: 'Hopper',
    email: 'grace@school.edu',
    role: User.roleTeacher,
  );

  group('InMemoryTeacherAccessCodeRepository', () {
    late InMemoryTeacherAccessCodeRepository repository;

    setUp(() {
      repository = InMemoryTeacherAccessCodeRepository(
        generateNormalizedCode: () => validCode,
        now: () => DateTime.utc(2026, 8, 23, 8),
      );
      repository.seed(
        const TeacherAccessCode(normalizedCode: validCode, consumed: false),
      );
    });

    test('assertRedeemable accepts hyphenated unused codes', () async {
      await repository.assertRedeemable('7kpm-xr4d-q2wt');
    });

    test(
      'assertRedeemable rejects malformed, missing, and consumed codes',
      () async {
        await expectLater(
          repository.assertRedeemable('not-a-code'),
          throwsA(
            isA<TeacherAccessCodeException>().having(
              (e) => e.code,
              'code',
              TeacherAccessCodeError.malformedCode,
            ),
          ),
        );
        await expectLater(
          repository.assertRedeemable('ABCD2345EFGH'),
          throwsA(
            isA<TeacherAccessCodeException>().having(
              (e) => e.code,
              'code',
              TeacherAccessCodeError.notFound,
            ),
          ),
        );
        repository.seed(
          const TeacherAccessCode(normalizedCode: validCode, consumed: true),
        );
        await expectLater(
          repository.assertRedeemable(validCode),
          throwsA(
            isA<TeacherAccessCodeException>().having(
              (e) => e.code,
              'code',
              TeacherAccessCodeError.alreadyConsumed,
            ),
          ),
        );
      },
    );

    test('consumeAndCreateTeacherProfile is one-time', () async {
      await repository.consumeAndCreateTeacherProfile(
        code: '7KPM-XR4D-Q2WT',
        user: teacher,
        legalConsent: RegistrationLegalConsent.current(),
      );
      expect(repository.codes[validCode]!.consumed, isTrue);
      expect(repository.codes[validCode]!.consumedBy, 'teacher-new');
      expect(repository.users['teacher-new']!.isTeacher, isTrue);

      await expectLater(
        repository.consumeAndCreateTeacherProfile(
          code: validCode,
          user: teacher.copyWith(id: 'other'),
          legalConsent: RegistrationLegalConsent.current(),
        ),
        throwsA(
          isA<TeacherAccessCodeException>().having(
            (e) => e.code,
            'code',
            TeacherAccessCodeError.alreadyConsumed,
          ),
        ),
      );
    });

    test('mint allocates a unique unconsumed code', () async {
      repository.codes.clear();
      final minted = await repository.mint(createdBy: 'teacher-1', note: 'lab');
      expect(minted.normalizedCode, validCode);
      expect(minted.consumed, isFalse);
      expect(minted.createdBy, 'teacher-1');
      expect(minted.note, 'lab');
      expect(minted.displayCode, '7KPM-XR4D-Q2WT');
    });

    test('mint retries collisions then exhausts', () async {
      final colliding = InMemoryTeacherAccessCodeRepository(
        generateNormalizedCode: () => validCode,
        maxCodeAttempts: 2,
      );
      colliding.seed(
        const TeacherAccessCode(normalizedCode: validCode, consumed: false),
      );
      await expectLater(
        colliding.mint(createdBy: 'teacher-1'),
        throwsA(
          isA<TeacherAccessCodeException>().having(
            (e) => e.code,
            'code',
            TeacherAccessCodeError.collisionExhausted,
          ),
        ),
      );
    });

    test('watchCreatedBy and deleteUnused are owner unused only', () async {
      repository.codes.clear();
      repository.seed(
        const TeacherAccessCode(
          normalizedCode: validCode,
          consumed: false,
          createdBy: 'teacher-1',
        ),
      );
      repository.seed(
        const TeacherAccessCode(
          normalizedCode: 'ABCD2345EFGH',
          consumed: false,
          createdBy: 'teacher-2',
        ),
      );
      repository.seed(
        const TeacherAccessCode(
          normalizedCode: '23456789ABCD',
          consumed: true,
          createdBy: 'teacher-1',
        ),
      );

      final mine = await repository.watchCreatedBy('teacher-1').first;
      expect(mine.map((code) => code.normalizedCode).toSet(), {
        validCode,
        '23456789ABCD',
      });

      await repository.deleteUnused(
        createdBy: 'teacher-1',
        normalizedCode: validCode,
      );
      expect(repository.codes.containsKey(validCode), isFalse);

      await expectLater(
        repository.deleteUnused(
          createdBy: 'teacher-1',
          normalizedCode: 'ABCD2345EFGH',
        ),
        throwsA(
          isA<TeacherAccessCodeException>().having(
            (e) => e.code,
            'code',
            TeacherAccessCodeError.forbidden,
          ),
        ),
      );
      await expectLater(
        repository.deleteUnused(
          createdBy: 'teacher-1',
          normalizedCode: '23456789ABCD',
        ),
        throwsA(
          isA<TeacherAccessCodeException>().having(
            (e) => e.code,
            'code',
            TeacherAccessCodeError.alreadyConsumed,
          ),
        ),
      );
    });
  });
}
