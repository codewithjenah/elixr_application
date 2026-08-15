import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/splash/splash_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _SplashHarness extends StatefulWidget {
  const _SplashHarness({
    super.key,
    required this.onFinished,
    required this.authReady,
  });

  final VoidCallback onFinished;
  final bool authReady;

  @override
  State<_SplashHarness> createState() => _SplashHarnessState();
}

class _SplashHarnessState extends State<_SplashHarness> {
  late bool authReady = widget.authReady;

  void setAuthReady(bool value) {
    setState(() => authReady = value);
  }

  @override
  Widget build(BuildContext context) => FluentApp(
    theme: AppTheme.dark,
    home: SplashScreen(onFinished: widget.onFinished, authReady: authReady),
  );
}

void main() {
  testWidgets('waits for both the brand sequence and auth readiness once', (
    tester,
  ) async {
    var completionCount = 0;
    final key = GlobalKey<_SplashHarnessState>();
    await tester.pumpWidget(
      _SplashHarness(
        key: key,
        authReady: false,
        onFinished: () => completionCount++,
      ),
    );

    await tester.pump(const Duration(milliseconds: 2200));
    expect(completionCount, 0);
    expect(find.text('Preparing your session…'), findsOneWidget);

    key.currentState!.setAuthReady(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(completionCount, 1);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(completionCount, 1);
  });
}
