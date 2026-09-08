import 'package:elixr_application/core/constants/app_constants.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/splash/splash_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _SplashHarness extends StatefulWidget {
  const _SplashHarness({
    super.key,
    required this.onFinished,
    required this.authReady,
    this.startupError,
    this.onRetry,
    this.reducedMotion = false,
    this.size = const Size(1100, 760),
  });

  final VoidCallback onFinished;
  final bool authReady;
  final String? startupError;
  final VoidCallback? onRetry;
  final bool reducedMotion;
  final Size size;

  @override
  State<_SplashHarness> createState() => _SplashHarnessState();
}

class _SplashHarnessState extends State<_SplashHarness> {
  late bool authReady = widget.authReady;
  late String? startupError = widget.startupError;

  void setAuthReady(bool value) {
    setState(() => authReady = value);
  }

  void setStartupError(String? value) {
    setState(() => startupError = value);
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQueryData(
      size: widget.size,
      disableAnimations: widget.reducedMotion,
    ),
    child: FluentApp(
      theme: AppTheme.dark,
      home: SplashScreen(
        onFinished: widget.onFinished,
        authReady: authReady,
        startupError: startupError,
        onRetry: widget.onRetry,
      ),
    ),
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
    expect(find.text(AppConstants.appTagline), findsOneWidget);
    expect(find.text('Preparing your session…'), findsOneWidget);
    expect(
      find.image(const AssetImage(AppConstants.appLogoAsset)),
      findsOneWidget,
    );

    key.currentState!.setAuthReady(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(completionCount, 1);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(completionCount, 1);
  });

  testWidgets('replaces a startup failure with a retryable safe state', (
    tester,
  ) async {
    var retryCount = 0;
    final key = GlobalKey<_SplashHarnessState>();
    await tester.pumpWidget(
      _SplashHarness(
        key: key,
        authReady: false,
        startupError:
            "ELIXR couldn't finish preparing your session. Check your connection and try again.",
        onRetry: () {
          retryCount++;
          key.currentState!.setStartupError(null);
        },
        onFinished: () {},
      ),
    );

    await tester.pump(const Duration(milliseconds: 2200));
    expect(find.text('SESSION PREPARATION FAILED'), findsOneWidget);
    expect(find.text('Preparing your session…'), findsNothing);
    expect(find.byKey(const Key('splash_retry_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('splash_retry_button')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(retryCount, 1);
    expect(find.text('Preparing your session…'), findsOneWidget);
    expect(find.text('SESSION PREPARATION FAILED'), findsNothing);
  });

  testWidgets(
    'reduced motion renders the completed composition without an intro wait',
    (tester) async {
      var completionCount = 0;
      await tester.pumpWidget(
        _SplashHarness(
          authReady: true,
          reducedMotion: true,
          onFinished: () => completionCount++,
        ),
      );
      await tester.pump();

      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text(AppConstants.appTagline), findsOneWidget);
      expect(find.text('READY TO TRAIN'), findsOneWidget);
      expect(completionCount, 1);
    },
  );

  testWidgets('keeps the splash composition usable at a compact window size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _SplashHarness(
        authReady: false,
        reducedMotion: true,
        size: const Size(540, 430),
        onFinished: () {},
      ),
    );
    await tester.pump();

    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('Preparing your session…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
