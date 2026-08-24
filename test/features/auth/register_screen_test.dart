import 'package:elixr_application/core/constants/app_constants.dart';
import 'package:elixr_application/core/widgets/auth_scaffold.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/features/auth/register_screen.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _RegisterTrackingRepository implements AuthRepositoryBase {
  int registerCallCount = 0;
  String? lastFirstName;
  String? lastMiddleName;
  String? lastLastName;
  String? lastEmail;
  String? lastDefaultRole;
  bool verificationRequested = false;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
    String? teacherAccessCode,
  }) async {
    registerCallCount++;
    lastFirstName = firstName;
    lastMiddleName = middleName;
    lastLastName = lastName;
    lastEmail = email;
    lastDefaultRole = defaultRole;
    return User(
      id: 'new-user',
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
    );
  }

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => false;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {
    verificationRequested = true;
  }

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {}
}

Future<void> _setSurface(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Finder _authField(String placeholder) {
  return find.byWidgetPredicate(
    (widget) => widget is TextBox && widget.placeholder == placeholder,
  );
}

Future<void> _enterAuthField(
  WidgetTester tester,
  String placeholder,
  String value,
) async {
  await tester.enterText(_authField(placeholder), value);
  await tester.pump();
}

const _registerFieldPlaceholders = [
  'First name',
  'Middle name (optional)',
  'Last name',
  'Email address',
  'Password',
  'Confirm password',
];

int _countRegisterFieldsInRow(Element rowElement) {
  var count = 0;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is TextBox &&
        _registerFieldPlaceholders.contains(widget.placeholder)) {
      count++;
    }
    element.visitChildren(visit);
  }

  rowElement.visitChildren(visit);
  return count;
}

bool _rowPairsRegisterFields(Element rowElement) {
  return _countRegisterFieldsInRow(rowElement) >= 2;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RegisterTrackingRepository repository;
  late AuthService authService;
  late GoRouter router;

  setUp(() {
    repository = _RegisterTrackingRepository();
    authService = AuthService(
      repository: repository,
      leaderboardRepository: null,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );
    router = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) =>
              const ScaffoldPage(content: Center(child: Text('Dashboard'))),
        ),
      ],
    );
  });

  tearDown(() {
    authService.dispose();
    router.dispose();
  });

  Widget wrap() {
    return ChangeNotifierProvider<AuthService>.value(
      value: authService,
      child: FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    );
  }

  Future<void> pumpRegisterScreen(WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> checkPrivacyConsent(WidgetTester tester) async {
    final checkbox = find.byKey(const Key('register_privacy_consent'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
  }

  Future<void> fillValidRegistrationForm(WidgetTester tester) async {
    await _enterAuthField(tester, 'First name', 'Ada');
    await _enterAuthField(tester, 'Last name', 'Lovelace');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await _enterAuthField(tester, 'Email address', 'ada@example.com');
    await _enterAuthField(tester, 'Password', 'secret12');
    await _enterAuthField(tester, 'Confirm password', 'secret12');
    await checkPrivacyConsent(tester);
  }

  group('RegisterScreen', () {
    testWidgets(
      'disables Create Account until privacy consent checkbox is checked',
      (tester) async {
        await _setSurface(tester);
        await pumpRegisterScreen(tester);

        await _enterAuthField(tester, 'First name', 'Ada');
        await _enterAuthField(tester, 'Last name', 'Lovelace');
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await _enterAuthField(tester, 'Email address', 'ada@example.com');
        await _enterAuthField(tester, 'Password', 'secret12');
        await _enterAuthField(tester, 'Confirm password', 'secret12');
        await tester.pump();

        final disabled = tester.widget<ElixPrimaryButton>(
          find.widgetWithText(ElixPrimaryButton, 'Create Account'),
        );
        expect(disabled.onPressed, isNull);

        await tester.tap(
          find.widgetWithText(ElixPrimaryButton, 'Create Account'),
        );
        await tester.pump();
        expect(repository.registerCallCount, 0);

        await checkPrivacyConsent(tester);

        final enabled = tester.widget<ElixPrimaryButton>(
          find.widgetWithText(ElixPrimaryButton, 'Create Account'),
        );
        expect(enabled.onPressed, isNotNull);

        await tester.tap(
          find.widgetWithText(ElixPrimaryButton, 'Create Account'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(repository.registerCallCount, 1);
        expect(repository.verificationRequested, isTrue);
      },
    );

    testWidgets('requires first and last name', (tester) async {
      await _setSurface(tester);
      await pumpRegisterScreen(tester);

      expect(repository.registerCallCount, 0);
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.widgetWithText(ElixPrimaryButton, 'Continue'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Enter your first and last name to continue.'),
        findsOneWidget,
      );
    });

    testWidgets('accepts an empty middle name', (tester) async {
      await _setSurface(tester);
      await pumpRegisterScreen(tester);

      await fillValidRegistrationForm(tester);
      await tester.tap(find.byType(ElixPrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repository.registerCallCount, 1);
      expect(repository.lastMiddleName, isNull);
      expect(repository.verificationRequested, isTrue);
      expect(authService.isAuthenticated, isTrue);
    });

    testWidgets(
      'passes normalized structured names to AuthService/repository',
      (tester) async {
        await _setSurface(tester);
        await pumpRegisterScreen(tester);

        await _enterAuthField(tester, 'First name', '  Ada   Marie  ');
        await _enterAuthField(tester, 'Middle name (optional)', '  Augusta  ');
        await _enterAuthField(tester, 'Last name', '  Lovelace  ');
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await _enterAuthField(tester, 'Email address', ' ada@example.com ');
        await _enterAuthField(tester, 'Password', 'secret12');
        await _enterAuthField(tester, 'Confirm password', 'secret12');
        await checkPrivacyConsent(tester);
        await tester.tap(
          find.widgetWithText(ElixPrimaryButton, 'Create Account'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(repository.registerCallCount, 1);
        expect(repository.lastFirstName, 'Ada Marie');
        expect(repository.lastMiddleName, 'Augusta');
        expect(repository.lastLastName, 'Lovelace');
        expect(repository.lastEmail, 'ada@example.com');
        expect(repository.lastDefaultRole, AppConstants.defaultRole);
      },
    );

    testWidgets(
      'keeps each registration step vertically arranged at full width',
      (tester) async {
        await _setSurface(tester, size: const Size(1366, 768));
        await pumpRegisterScreen(tester);

        double? previousBottom;
        double? referenceWidth;
        for (final placeholder in _registerFieldPlaceholders.take(3)) {
          final rect = tester.getRect(_authField(placeholder));
          referenceWidth ??= rect.width;
          expect(rect.width, closeTo(referenceWidth, 2));
          if (previousBottom != null) {
            expect(rect.top, greaterThanOrEqualTo(previousBottom - 1));
          }
          previousBottom = rect.bottom;
        }

        final rowFinder = find.descendant(
          of: find.byKey(const Key('register_form_fields')),
          matching: find.byType(Row),
        );
        for (final rowElement in tester.elementList(rowFinder)) {
          expect(_rowPairsRegisterFields(rowElement), isFalse);
        }
        await _enterAuthField(tester, 'First name', 'Ada');
        await _enterAuthField(tester, 'Last name', 'Lovelace');
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 150));
        for (final placeholder in _registerFieldPlaceholders.skip(3)) {
          expect(_authField(placeholder), findsOneWidget);
        }
        await tester.tap(find.text('Back'));
        await tester.pump(const Duration(milliseconds: 150));
        expect(_authField('First name'), findsOneWidget);
        expect(
          tester.widget<TextBox>(_authField('First name')).controller?.text,
          'Ada',
        );
      },
    );

    testWidgets('does not overflow at a representative laptop size', (
      tester,
    ) async {
      await _setSurface(tester, size: const Size(1366, 768));
      await pumpRegisterScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ElixPrimaryButton), findsOneWidget);
      expect(find.byType(AuthFooterLink), findsOneWidget);
    });

    testWidgets('does not overflow at a compact auth window size', (
      tester,
    ) async {
      await _setSurface(tester, size: const Size(660, 680));
      await pumpRegisterScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(RegisterScreen), findsOneWidget);
    });

    testWidgets('remains usable at a shorter viewport height', (tester) async {
      await _setSurface(tester, size: const Size(1366, 560));
      await pumpRegisterScreen(tester);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(RegisterScreen), findsOneWidget);
      for (final placeholder in _registerFieldPlaceholders.take(3)) {
        expect(_authField(placeholder), findsOneWidget);
      }
    });
  });
}
