import 'package:elixr_application/core/router/navigation_helpers.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('drill-down Back returns through real navigation history', (
    tester,
  ) async {
    final router = _router('/origin');
    addTearDown(router.dispose);
    await tester.pumpWidget(FluentApp.router(routerConfig: router));

    await tester.tap(find.byKey(const Key('push_detail')));
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail_back')));
    await tester.pumpAndSettle();
    expect(find.text('Origin'), findsOneWidget);
  });

  testWidgets('direct detail link uses its canonical fallback', (tester) async {
    final router = _router('/detail');
    addTearDown(router.dispose);
    await tester.pumpWidget(FluentApp.router(routerConfig: router));

    await tester.tap(find.byKey(const Key('detail_back')));
    await tester.pumpAndSettle();
    expect(find.text('Fallback'), findsOneWidget);
  });

  testWidgets('destination replacement does not create an unwanted stack', (
    tester,
  ) async {
    final router = _router('/origin');
    addTearDown(router.dispose);
    await tester.pumpWidget(FluentApp.router(routerConfig: router));

    await tester.tap(find.byKey(const Key('replace_detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail_back')));
    await tester.pumpAndSettle();

    expect(find.text('Fallback'), findsOneWidget);
    expect(find.text('Origin'), findsNothing);
  });
}

GoRouter _router(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/origin',
      builder: (context, state) => NavigationView(
        content: Column(
          children: [
            const Text('Origin'),
            Button(
              key: const Key('push_detail'),
              onPressed: () => context.push('/detail'),
              child: const Text('Open detail'),
            ),
            Button(
              key: const Key('replace_detail'),
              onPressed: () => context.go('/detail'),
              child: const Text('Replace destination'),
            ),
          ],
        ),
      ),
    ),
    GoRoute(
      path: '/detail',
      builder: (context, state) => NavigationView(
        content: Column(
          children: [
            const Text('Detail'),
            Button(
              key: const Key('detail_back'),
              onPressed: () => popOrGo(context, '/fallback'),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    ),
    GoRoute(
      path: '/fallback',
      builder: (context, state) =>
          const NavigationView(content: Text('Fallback')),
    ),
  ],
);
