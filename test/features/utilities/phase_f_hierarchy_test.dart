import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_application/features/legal/privacy_policy_screen.dart';
import 'package:elixr_application/features/messages/messages_screen.dart';
import 'package:elixr_application/features/profile/widgets/profile_header.dart';
import 'package:elixr_application/features/profile/widgets/profile_stats_section.dart';
import 'package:elixr_application/features/settings/settings_screen.dart';
import 'package:elixr_application/features/settings/settings_section.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../teacher/teacher_phase3_test_support.dart';

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  Widget child, {
  FluentThemeData? theme,
  Size size = const Size(1100, 800),
}) {
  return FluentApp(
    theme: theme ?? AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: ScaffoldPage(content: child),
    ),
  );
}

LeaderboardEntry _entry({int bestScore = 90}) {
  return LeaderboardEntry(
    userId: 'u1',
    displayName: 'Ada Lovelace',
    totalXp: 300,
    sessionsCompleted: 8,
    scoreSum: 80,
    averageScore: 80,
    bestScore: bestScore,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('messages pane uses compact editorial title at desktop width', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    final repository = InMemoryChatRepository();
    addTearDown(() async {
      auth.dispose();
      await repository.dispose();
    });

    await _setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ChatRepository>.value(value: repository),
        ],
        child: _app(const MessagesScreen(), size: const Size(1200, 800)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ElixEditorialHeader), findsOneWidget);
    final editorial = tester.widget<ElixEditorialHeader>(
      find.byType(ElixEditorialHeader),
    );
    expect(editorial.variant, ElixEditorialHeaderVariant.compact);

    final title = tester.widget<Text>(find.text('Messages'));
    expect(title.style!.fontSize, 24);
    expect(title.style!.fontFamily, ElixTypography.fontFamily);
    expect(title.style!.fontFamily, isNot(AppTheme.brandFontFamily));
    expect(find.text('Find a Teacher or Trainee'), findsOneWidget);
    expect(
      find.text(
        'Enter at least 2 characters. Email search is exact and private.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('messages pane compact breakpoint uses 22px title', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    final repository = InMemoryChatRepository();
    addTearDown(() async {
      auth.dispose();
      await repository.dispose();
    });

    await _setSurface(tester, const Size(800, 760));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ChatRepository>.value(value: repository),
        ],
        child: _app(const MessagesScreen(), size: const Size(800, 760)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Text>(find.text('Messages')).style!.fontSize, 22);
  });

  testWidgets('profile header uses compact editorial name', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        ProfileHeader(
          displayName: 'Ada Lovelace',
          showOwnerActions: true,
          onEditProfile: () {},
          onPreviewProfile: () {},
          onPrivacy: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ElixEditorialHeader), findsOneWidget);
    final editorial = tester.widget<ElixEditorialHeader>(
      find.byType(ElixEditorialHeader),
    );
    expect(editorial.variant, ElixEditorialHeaderVariant.compact);

    final name = tester.widget<Text>(find.text('Ada Lovelace'));
    expect(name.style!.fontSize, 24);
    expect(name.style!.fontFamily, ElixTypography.fontFamily);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Preview as Visitor'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('profile header compact breakpoint uses 22px name', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 640));
    await tester.pumpWidget(
      _app(
        const ProfileHeader(displayName: 'Ada Lovelace'),
        size: const Size(800, 640),
      ),
    );
    await tester.pump();

    expect(tester.widget<Text>(find.text('Ada Lovelace')).style!.fontSize, 22);
  });

  testWidgets('profile rank 1 and best score use milestone gold', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    late Color milestone;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            milestone = context.elixColors.milestone;
            return ProfileStatsSection(
              leaderboardEntry: _entry(bestScore: 12),
              rank: 1,
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Player Stats'), findsOneWidget);
    expect(tester.widget<Text>(find.text('#1')).style!.color, milestone);
    expect(tester.widget<Text>(find.text('12')).style!.color, milestone);
  });

  testWidgets(
    'privacy policy uses document editorial, not Bahnschrift wordmark',
    (tester) async {
      await _setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(
        _app(const PrivacyPolicyScreen(), size: const Size(1280, 900)),
      );
      await tester.pump();

      expect(find.byType(ElixEditorialHeader), findsWidgets);
      final editorial = tester
          .widgetList<ElixEditorialHeader>(find.byType(ElixEditorialHeader))
          .first;
      expect(editorial.variant, ElixEditorialHeaderVariant.document);

      final title = tester.widget<Text>(
        find.text(ElixrLegalDocuments.privacyPolicyTitle),
      );
      expect(title.style!.fontSize, 36);
      expect(title.style!.fontFamily, ElixTypography.fontFamily);
      expect(title.style!.fontFamily, isNot(AppTheme.brandFontFamily));
      expect(title.maxLines, 3);
      expect(
        find.text(ElixrLegalDocuments.privacyPolicySubtitle),
        findsOneWidget,
      );
      expect(find.text('IN THIS DOCUMENT'), findsOneWidget);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
    },
  );

  testWidgets('privacy policy compact breakpoint uses 30px document title', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 900));
    await tester.pumpWidget(
      _app(const PrivacyPolicyScreen(), size: const Size(800, 900)),
    );
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.text(ElixrLegalDocuments.privacyPolicyTitle))
          .style!
          .fontSize,
      30,
    );
    expect(
      tester
          .widget<Text>(find.text(ElixrLegalDocuments.privacyPolicyTitle))
          .style!
          .fontFamily,
      isNot(AppTheme.brandFontFamily),
    );
  });

  settingsChromeTests();
}

class _PhaseFSettingsHarness {
  _PhaseFSettingsHarness(this.tester);

  final WidgetTester tester;
  late SettingsService settingsService;
  late AuthService authService;
  late CameraDeviceService cameraDeviceService;

  Future<void> setUp() async {
    // This hierarchy check only reads the service defaults. Avoid async temp
    // filesystem setup because it can stall the Windows Flutter test runner.
    settingsService = SettingsService();
    cameraDeviceService = CameraDeviceService(
      httpGet: (_) async => '{"devices":[]}',
    );
    authService = phase3TeacherAuth();
  }

  Future<void> tearDown() async {
    authService.dispose();
    cameraDeviceService.dispose();
    settingsService.dispose();
  }

  Widget wrap(Widget child, {Size size = const Size(1400, 900)}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<CameraDeviceService>.value(
          value: cameraDeviceService,
        ),
      ],
      child: FluentApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: ScaffoldPage(content: child),
        ),
      ),
    );
  }
}

void settingsChromeTests() {
  testWidgets('settings chrome uses compact editorial title', (tester) async {
    final harness = _PhaseFSettingsHarness(tester);
    await harness.setUp();
    addTearDown(harness.tearDown);

    await _setSurface(tester, const Size(1400, 900));
    await tester.pumpWidget(
      harness.wrap(
        SettingsScreen(
          initialSection: SettingsSection.appearance,
          watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
          equipBorder: ({required userId, required borderId}) async =>
              const EquipBorderResult.alreadyEquipped(),
        ),
        size: const Size(1400, 900),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final settingsHeaders = tester
        .widgetList<ElixEditorialHeader>(find.byType(ElixEditorialHeader))
        .where((header) => header.heading == 'Settings');
    expect(settingsHeaders, isNotEmpty);
    expect(settingsHeaders.first.variant, ElixEditorialHeaderVariant.compact);

    final title = tester.widget<Text>(find.text('Settings'));
    expect(title.style!.fontSize, 24);
    expect(title.style!.fontFamily, ElixTypography.fontFamily);
    expect(find.text('Manage your Elixr experience'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
  });
}
