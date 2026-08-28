import 'package:elixr_application/core/shell/teacher_shell.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/auth_scaffold.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/features/history/widgets/history_header.dart';
import 'package:elixr_application/features/settings/widgets/settings_components.dart';
import 'package:elixr_application/features/splash/splash_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  bool reducedMotion = false,
  FluentThemeData? theme,
}) => FluentApp(
  theme: theme ?? AppTheme.dark,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(1100, 760),
      disableAnimations: reducedMotion,
    ),
    child: child,
  ),
);

void main() {
  testWidgets(
    'entry surfaces retain hierarchy when reduced motion is enabled',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AuthScaffold(
            title: 'Own the pour.',
            formTitle: 'Welcome back',
            formSubtitle: 'Continue your training.',
            child: const Text('Auth form'),
          ),
          reducedMotion: true,
        ),
      );

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Continue your training.'), findsOneWidget);
      expect(find.text('Auth form'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _host(
          SplashScreen(onFinished: () {}, authReady: false),
          reducedMotion: true,
        ),
      );
      await tester.pump();

      expect(find.text('ELIXR'), findsOneWidget);
      expect(find.text('Preparing your session…'), findsOneWidget);
    },
  );

  testWidgets('high contrast entry copy uses semantic colors', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const AuthErrorBanner(message: 'Try again'),
            AuthFooterLink(prompt: 'New?', action: 'Register', onTap: _noop),
          ],
        ),
        theme: AppTheme.highContrastDark,
      ),
    );

    expect(
      tester.widget<Text>(find.text('Try again')).style!.color,
      ElixSemanticColors.highContrastDark.error,
    );
    final footer = tester.widget<RichText>(
      find.descendant(
        of: find.byType(AuthFooterLink),
        matching: find.byType(RichText),
      ),
    );
    final footerSpan = footer.text as TextSpan;
    expect(footerSpan.children!.last.style!.color, Colors.white);

    await tester.pumpWidget(
      _host(
        SplashScreen(onFinished: _noop, authReady: false),
        reducedMotion: true,
        theme: AppTheme.highContrastDark,
      ),
    );
    expect(tester.widget<Text>(find.text('ELIXR')).style!.color, Colors.white);
  });

  testWidgets(
    'auth card keeps intrinsic width and settings motion is reduced',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const AuthScaffold(child: SizedBox(width: 200, child: Text('Form'))),
        ),
      );
      expect(
        tester.getSize(find.byType(AuthFormCard)).width,
        lessThanOrEqualTo(440),
      );

      await tester.pumpWidget(
        _host(
          SettingsNavItem(
            icon: FluentIcons.settings,
            label: 'Settings',
            isSelected: true,
            onTap: _noop,
          ),
          reducedMotion: true,
        ),
      );
      expect(
        tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)),
        everyElement(
          isA<AnimatedContainer>().having(
            (container) => container.duration,
            'duration',
            Duration.zero,
          ),
        ),
      );
    },
  );

  testWidgets(
    'trainee, teacher, and settings headers expose editorial labels',
    (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              const HistoryHeader(loading: false, onRefresh: _noop),
              const SettingsSectionHeader(
                title: 'Appearance',
                description: 'Choose your workspace contrast and theme.',
              ),
            ],
          ),
        ),
      );

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('History'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Appearance'))
            .flagsCollection
            .isHeader,
        isTrue,
      );

      await tester.pumpWidget(
        _host(
          const TeacherScaffoldPage(
            header: ElixEditorialPageHeader(
              heading: 'Dashboard',
              eyebrow: 'TEACHER WORKSPACE',
            ),
            content: Text('Teacher content'),
          ),
        ),
      );

      expect(find.byType(PageHeader), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Dashboard'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
    },
  );
}

void _noop() {}
