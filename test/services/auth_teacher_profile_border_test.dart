import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elixr_application/services/auth_service.dart';

class _BorderRepository extends Fake
    implements AuthRepositoryBase, TeacherProfileBorderRepositoryBase {
  _BorderRepository(this.savedUser);

  User savedUser;
  final calls = <String?>[];

  @override
  Future<User> updateTeacherProfileBorder({
    required String userId,
    required String? profileBorderId,
  }) async {
    calls.add(profileBorderId);
    savedUser = savedUser.copyWith(
      profileBorderId: profileBorderId,
      clearProfileBorderId: profileBorderId == null,
    );
    return savedUser;
  }
}

void main() {
  test(
    'Teacher border persistence updates the canonical current user',
    () async {
      final initial = const User(
        id: 'teacher-1',
        firstName: 'Grace',
        lastName: 'Hopper',
        email: 'grace@example.com',
        role: User.roleTeacher,
      );
      final repository = _BorderRepository(initial);
      final auth = AuthService(repository: repository);
      addTearDown(auth.dispose);
      auth.seedAuthenticatedUser(initial);

      await auth.updateTeacherProfileBorder(profileBorderId: ' starter_glow ');

      expect(repository.calls, ['starter_glow']);
      expect(auth.currentUser?.profileBorderId, 'starter_glow');

      await auth.updateTeacherProfileBorder();

      expect(repository.calls, ['starter_glow', null]);
      expect(auth.currentUser?.profileBorderId, isNull);
    },
  );

  test('invalid Teacher border IDs are rejected before persistence', () async {
    final initial = const User(
      id: 'teacher-1',
      firstName: 'Grace',
      lastName: 'Hopper',
      email: 'grace@example.com',
      role: User.roleTeacher,
    );
    final repository = _BorderRepository(initial);
    final auth = AuthService(repository: repository);
    addTearDown(auth.dispose);
    auth.seedAuthenticatedUser(initial);

    await expectLater(
      auth.updateTeacherProfileBorder(profileBorderId: 'arbitrary-border'),
      throwsA(isA<ArgumentError>()),
    );

    expect(repository.calls, isEmpty);
    expect(auth.currentUser?.profileBorderId, isNull);
  });

  test(
    'Trainees cannot use the Teacher border persistence operation',
    () async {
      final initial = const User(
        id: 'trainee-1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
      );
      final repository = _BorderRepository(initial);
      final auth = AuthService(repository: repository);
      addTearDown(auth.dispose);
      auth.seedAuthenticatedUser(initial);

      await expectLater(
        auth.updateTeacherProfileBorder(profileBorderId: 'starter_glow'),
        throwsException,
      );

      expect(repository.calls, isEmpty);
    },
  );
}
