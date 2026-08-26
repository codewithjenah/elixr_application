import 'package:elixr_core/legal/legal_documents.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/legal/privacy_policy_screen.dart';
import 'package:elixr_application/features/legal/terms_of_service_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

Future<void> pumpLegal(
  WidgetTester tester, {
  required String location,
  required Widget screen,
  Size size = const Size(1280, 900),
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: location, builder: (context, state) => screen),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            const ScaffoldPage(content: Center(child: Text('Register'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    FluentApp.router(
      theme: AppTheme.dark,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      routeInformationProvider: router.routeInformationProvider,
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
}

Finder containing(String text) {
  return find.textContaining(text, skipOffstage: false);
}

Finder tocFor(ElixrLegalSection section) {
  return find.byKey(ValueKey('legal_toc_${section.id}'));
}

Future<void> walkSections(
  WidgetTester tester,
  List<ElixrLegalSection> sections,
) async {
  for (var i = 0; i < sections.length; i++) {
    if (i > 0) {
      await tester.tap(tocFor(sections[i]));
      await tester.pumpAndSettle();
    }
    for (final paragraph in sections[i].paragraphs) {
      expect(containing(paragraph), findsOneWidget);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows privacy policy covers every section', (tester) async {
    await pumpLegal(
      tester,
      location: '/privacy-policy',
      screen: const PrivacyPolicyScreen(),
    );

    final sections = ElixrLegalDocuments.privacyPolicySectionsFor(
      ElixrLegalClient.traineeWindows,
    );
    expect(containing('Last updated September 2026'), findsOneWidget);
    expect(
      containing(
        'Version ${RegistrationLegalConsent.currentPrivacyPolicyVersion}',
      ),
      findsOneWidget,
    );
    await walkSections(tester, sections);
    expect(containing('not yet active'), findsNothing);
  });

  testWidgets('Windows terms cover every section', (tester) async {
    await pumpLegal(
      tester,
      location: '/terms-of-service',
      screen: const TermsOfServiceScreen(),
    );

    final sections = ElixrLegalDocuments.termsOfServiceSectionsFor(
      ElixrLegalClient.traineeWindows,
    );
    expect(containing('Last updated September 2026'), findsOneWidget);
    expect(
      containing(
        'Version ${RegistrationLegalConsent.currentTermsOfServiceVersion}',
      ),
      findsOneWidget,
    );
    await walkSections(tester, sections);
    expect(containing('not yet active'), findsNothing);
  });

  testWidgets('arrow keys move between legal sections', (tester) async {
    await pumpLegal(
      tester,
      location: '/terms-of-service',
      screen: const TermsOfServiceScreen(),
    );

    final sections = ElixrLegalDocuments.termsOfServiceSectionsFor(
      ElixrLegalClient.traineeWindows,
    );
    await tester.tap(tocFor(sections.first));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(containing(sections[1].paragraphs.single), findsOneWidget);
    expect(containing(sections.first.paragraphs.single), findsNothing);
  });

  testWidgets('wide reader fits the current 1024 by 600 viewport', (
    tester,
  ) async {
    await pumpLegal(
      tester,
      location: '/privacy-policy',
      screen: const PrivacyPolicyScreen(),
      size: const Size(1024, 600),
    );

    final sections = ElixrLegalDocuments.privacyPolicySectionsFor(
      ElixrLegalClient.traineeWindows,
    );
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) {
        await tester.tap(tocFor(sections[i]));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull, reason: 'section ${i + 1}');
    }
  });

  testWidgets('narrow reader uses a horizontal section chip row', (
    tester,
  ) async {
    await pumpLegal(
      tester,
      location: '/terms-of-service',
      screen: const TermsOfServiceScreen(),
      size: const Size(800, 600),
    );

    final sections = ElixrLegalDocuments.termsOfServiceSectionsFor(
      ElixrLegalClient.traineeWindows,
    );
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      find.byKey(ValueKey('legal_toc_${sections.first.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
