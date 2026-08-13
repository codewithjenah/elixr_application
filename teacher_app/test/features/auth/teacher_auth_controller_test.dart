import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:elixr_teacher/features/auth/teacher_auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late TeacherAuthController controller;

  setUp(() {
    repository = FakeAuthRepository();
    controller = TeacherAuthController(repository: repository);
  });

  tearDown(() {
    controller.dispose();
  });

  group('initialize', () {
    test('signed-out session stays signed out', () async {
      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.currentUser, isNull);
      expect(controller.canEnterTeacherShell, isFalse);
    });

    test('verified Teacher becomes authenticated', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = true;

      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.authenticatedTeacher);
      expect(controller.canEnterTeacherShell, isTrue);
      expect(controller.currentUser?.isTeacher, isTrue);
    });

    test('unverified Teacher requires email verification', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = false;

      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.needsEmailVerification, isTrue);
      expect(controller.canEnterTeacherShell, isFalse);
    });

    test('persisted reload failure stays off the Teacher shell', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = true;
      repository.emailVerifiedError = Exception('Account refresh timed out');

      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.canEnterTeacherShell, isFalse);
    });

    test('persisted Trainee is signed out of the Teacher app', () async {
      repository.persistedUser = fakeTrainee();

      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(repository.clearCurrentUserCallCount, 1);
      expect(controller.errorMessage, TeacherAuthMessages.notATeacher);
      expect(controller.canEnterTeacherShell, isFalse);
    });

    test('persisted Admin is signed out of the Teacher app', () async {
      repository.persistedUser = fakeAdmin();

      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(repository.clearCurrentUserCallCount, 1);
      expect(controller.errorMessage, TeacherAuthMessages.notATeacher);
    });

    test(
      'missing Firestore profile signs out without claiming a role',
      () async {
        repository.authSessionWithoutProfile = true;

        await controller.initialize();

        expect(controller.status, TeacherAuthStatus.signedOut);
        expect(controller.currentUser, isNull);
        expect(repository.clearCurrentUserCallCount, 1);
        expect(controller.errorMessage, isNull);
        expect(controller.canEnterTeacherShell, isFalse);
      },
    );

    test('load failure is a recoverable signed-out error', () async {
      repository.loadError = Exception(
        'Network error. Check your connection and try again.',
      );

      await controller.initialize();

      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(
        controller.errorMessage,
        'Network error. Check your connection and try again.',
      );
    });
  });

  group('register', () {
    setUp(() async {
      await controller.initialize();
    });

    test('passes User.roleTeacher to the shared repository', () async {
      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );

      expect(ok, isTrue);
      expect(repository.registerCallCount, 1);
      expect(repository.lastDefaultRole, User.roleTeacher);
      expect(repository.lastDefaultRole, isNot(User.roleTrainee));
      expect(repository.requestVerificationCallCount, 1);
      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.currentUser?.email, 'ada@example.com');
    });

    test('does not call the repository without legal consent', () async {
      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: false,
      );

      expect(ok, isFalse);
      expect(repository.registerCallCount, 0);
      expect(controller.errorMessage, TeacherAuthMessages.legalConsentRequired);
    });

    test('does not call the repository when passwords differ', () async {
      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret2',
        legalConsent: true,
      );

      expect(ok, isFalse);
      expect(repository.registerCallCount, 0);
      expect(controller.errorMessage, TeacherAuthMessages.passwordMismatch);
    });

    test('rejects a short password before Firebase', () async {
      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: '12345',
        confirmPassword: '12345',
        legalConsent: true,
      );

      expect(ok, isFalse);
      expect(repository.registerCallCount, 0);
      expect(controller.errorMessage, TeacherAuthMessages.passwordTooShort);
    });

    test('rejects a missing first name before Firebase', () async {
      final ok = await controller.register(
        firstName: '  ',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );

      expect(ok, isFalse);
      expect(repository.registerCallCount, 0);
      expect(controller.errorMessage, 'First name is required.');
    });

    test('rejects a malformed email before Firebase', () async {
      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'not-an-email',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );

      expect(ok, isFalse);
      expect(repository.registerCallCount, 0);
      expect(controller.errorMessage, TeacherAuthMessages.invalidEmail);
    });

    test('maps duplicate-email errors to a concise message', () async {
      repository.registerError = Exception('Email already registered');

      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.errorMessage, 'Email already registered');
    });

    test('keeps the session when verification send fails', () async {
      repository.verificationError = Exception(
        'Too many attempts. Try again later',
      );

      final ok = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );

      expect(ok, isTrue);
      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.errorMessage, 'Too many attempts. Try again later');
    });

    test('prevents double submission while registration is running', () async {
      repository.registerGate = Completer<void>();

      final first = controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );
      await Future<void>.delayed(Duration.zero);

      final second = await controller.register(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret1',
        confirmPassword: 'secret1',
        legalConsent: true,
      );

      expect(second, isFalse);
      expect(repository.registerCallCount, 1);

      repository.registerGate!.complete();
      expect(await first, isTrue);
      expect(repository.registerCallCount, 1);
    });
  });

  group('login', () {
    setUp(() async {
      await controller.initialize();
    });

    test('verified Teacher may enter the shell', () async {
      repository.loginResult = fakeTeacher();
      repository.emailVerified = true;

      final ok = await controller.login(
        email: 'teacher@example.com',
        password: 'secret1',
      );

      expect(ok, isTrue);
      expect(controller.status, TeacherAuthStatus.authenticatedTeacher);
    });

    test('unverified Teacher stays on verify-email', () async {
      repository.loginResult = fakeTeacher();
      repository.emailVerified = false;

      final ok = await controller.login(
        email: 'teacher@example.com',
        password: 'secret1',
      );

      expect(ok, isTrue);
      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.canEnterTeacherShell, isFalse);
    });

    test('Trainee cannot enter the Teacher shell', () async {
      repository.loginResult = fakeTrainee();

      final ok = await controller.login(
        email: 'trainee@example.com',
        password: 'secret1',
      );

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(repository.clearCurrentUserCallCount, 1);
      expect(controller.errorMessage, TeacherAuthMessages.notATeacher);
    });

    test('Admin cannot enter the Teacher shell', () async {
      repository.loginResult = fakeAdmin();

      final ok = await controller.login(
        email: 'admin@example.com',
        password: 'secret1',
      );

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(repository.clearCurrentUserCallCount, 1);
      expect(controller.errorMessage, TeacherAuthMessages.notATeacher);
    });

    test('wrong credentials stay signed out with a concise error', () async {
      repository.loginError = Exception('Invalid email or password');

      final ok = await controller.login(
        email: 'teacher@example.com',
        password: 'nope',
      );

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.errorMessage, 'Invalid email or password');
    });

    test('missing profile after sign-in is signed out safely', () async {
      repository.authSessionWithoutProfile = true;

      final ok = await controller.login(
        email: 'teacher@example.com',
        password: 'secret1',
      );

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.currentUser, isNull);
      expect(controller.errorMessage, TeacherAuthMessages.missingProfile);
      expect(repository.clearCurrentUserCallCount, greaterThanOrEqualTo(1));
    });

    test('prevents double submission while login is running', () async {
      repository.loginResult = fakeTeacher();
      repository.emailVerified = true;
      repository.loginGate = Completer<void>();

      final first = controller.login(
        email: 'teacher@example.com',
        password: 'secret1',
      );
      await Future<void>.delayed(Duration.zero);

      final second = await controller.login(
        email: 'teacher@example.com',
        password: 'secret1',
      );

      expect(second, isFalse);
      expect(repository.loginCallCount, 1);

      repository.loginGate!.complete();
      expect(await first, isTrue);
      expect(repository.loginCallCount, 1);
    });
  });

  group('email verification', () {
    test('successful check promotes a Teacher to the shell', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = false;
      await controller.initialize();

      repository.emailVerified = true;
      final ok = await controller.checkEmailVerification();

      expect(ok, isTrue);
      expect(controller.status, TeacherAuthStatus.authenticatedTeacher);
      expect(repository.refreshAuthenticatedUserCallCount, 1);
    });

    test('unverified check stays on verify-email', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = false;
      await controller.initialize();

      final ok = await controller.checkEmailVerification();

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.errorMessage, TeacherAuthMessages.emailNotVerifiedYet);
    });

    test('verified non-Teacher is rejected after refresh', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = false;
      await controller.initialize();

      repository.emailVerified = true;
      repository.persistedUser = fakeTrainee();
      final ok = await controller.checkEmailVerification();

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.errorMessage, TeacherAuthMessages.notATeacher);
    });

    test(
      'resend surfaces the verification error without signing out',
      () async {
        repository.persistedUser = fakeTeacher();
        repository.emailVerified = false;
        await controller.initialize();

        repository.verificationError = Exception(
          'Too many attempts. Try again later',
        );
        final ok = await controller.resendVerificationEmail();

        expect(ok, isFalse);
        expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
        expect(controller.errorMessage, 'Too many attempts. Try again later');
      },
    );

    test('check failure from reload stays on verify-email', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = false;
      await controller.initialize();

      repository.emailVerifiedError = Exception('Account refresh timed out');
      final ok = await controller.checkEmailVerification();

      expect(ok, isFalse);
      expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
      expect(controller.errorMessage, 'Account refresh timed out');
    });
  });

  group('password reset', () {
    setUp(() async {
      await controller.initialize();
    });

    test(
      'uses a generic success message that hides account existence',
      () async {
        final ok = await controller.sendPasswordResetEmail(
          email: 'anyone@example.com',
        );

        expect(ok, isTrue);
        expect(repository.sendPasswordResetEmailCallCount, 1);
        expect(repository.lastPasswordResetEmail, 'anyone@example.com');
        expect(controller.infoMessage, TeacherAuthMessages.resetEmailSent);
        expect(controller.errorMessage, isNull);
      },
    );

    test('does not call the repository for an empty email', () async {
      final ok = await controller.sendPasswordResetEmail(email: '  ');

      expect(ok, isFalse);
      expect(repository.sendPasswordResetEmailCallCount, 0);
      expect(controller.errorMessage, TeacherAuthMessages.emailEmpty);
    });

    test('surfaces a network failure without claiming success', () async {
      repository.passwordResetError = Exception(
        'Network error. Check your connection and try again.',
      );

      final ok = await controller.sendPasswordResetEmail(
        email: 'anyone@example.com',
      );

      expect(ok, isFalse);
      expect(controller.infoMessage, isNull);
      expect(
        controller.errorMessage,
        'Network error. Check your connection and try again.',
      );
    });

    test('user-not-found is treated as generic success', () async {
      repository.passwordResetError = Exception(
        '[firebase_auth/user-not-found] There is no user record',
      );

      final ok = await controller.sendPasswordResetEmail(
        email: 'anyone@example.com',
      );

      expect(ok, isTrue);
      expect(controller.infoMessage, TeacherAuthMessages.resetEmailSent);
      expect(controller.errorMessage, isNull);
    });
  });

  group('sign out', () {
    test('returns to signed-out state', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = true;
      await controller.initialize();

      await controller.signOut();

      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.currentUser, isNull);
      expect(repository.clearCurrentUserCallCount, 1);
    });

    test('local sign-out proceeds when Firebase sign-out fails', () async {
      repository.persistedUser = fakeTeacher();
      repository.emailVerified = true;
      await controller.initialize();

      repository.signOutError = Exception(
        'Network error. Check your connection and try again.',
      );
      await controller.signOut();

      expect(controller.status, TeacherAuthStatus.signedOut);
      expect(controller.currentUser, isNull);
      expect(
        controller.errorMessage,
        'Network error. Check your connection and try again.',
      );
    });
  });

  group('error sanitization', () {
    test('does not display raw Firebase exception objects', () {
      expect(
        sanitizeAuthError(
          Exception('FirebaseAuthException ([firebase_auth/internal])'),
        ),
        TeacherAuthMessages.genericFailure,
      );
    });
  });
}
