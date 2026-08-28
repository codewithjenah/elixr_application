import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/assigned_movements/assigned_practice_screen.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/widgets/training_session_header.dart';
import 'package:elixr_application/features/practice/widgets/training_session_panel.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

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

TrainingSessionHeader _header() {
  return TrainingSessionHeader(
    onBack: () {},
    title: 'Hand Stall',
    statusPill: 'Easy',
    instruction: 'Balance the bottle on your palm and hold it steady.',
    connectionState: WebSocketConnectionState.connected,
    wideLayout: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'practice session header uses compact editorial type at desktop width',
    (tester) async {
      await _setSurface(tester, const Size(1100, 800));
      await tester.pumpWidget(_app(_header()));
      await tester.pump();

      expect(find.byType(ElixEditorialHeader), findsOneWidget);
      final editorial = tester.widget<ElixEditorialHeader>(
        find.byType(ElixEditorialHeader),
      );
      expect(editorial.variant, ElixEditorialHeaderVariant.compact);
      expect(editorial.headingColor, AppColors.textPrimary);

      final title = tester.widget<Text>(find.text('Hand Stall'));
      expect(title.style!.fontSize, 24);
      expect(title.style!.fontFamily, ElixTypography.fontFamily);
      expect(title.style!.fontFamily, isNot(AppTheme.brandFontFamily));
      expect(title.style!.color, AppColors.textPrimary);

      expect(
        find.text('Balance the bottle on your palm and hold it steady.'),
        findsOneWidget,
      );
      expect(find.text('Easy'), findsOneWidget);
    },
  );

  testWidgets('practice session header compact breakpoint uses 22px title', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 640));
    await tester.pumpWidget(_app(_header(), size: const Size(800, 640)));
    await tester.pump();

    final title = tester.widget<Text>(find.text('Hand Stall'));
    expect(title.style!.fontSize, 22);
    expect(
      find.text('Balance the bottle on your palm and hold it steady.'),
      findsOneWidget,
    );
  });

  testWidgets('guided session elapsed metric uses compact section title', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const SessionMetricTiles(
          elapsedDisplay: '00:42',
          rubricChild: Text('—'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ELAPSED'), findsOneWidget);
    final elapsed = tester.widget<Text>(find.text('00:42'));
    expect(elapsed.style!.fontSize, 24);
    expect(elapsed.style!.fontFamily, ElixTypography.fontFamily);
  });

  testWidgets('guided session elapsed metric compact breakpoint uses 22px', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 640));
    await tester.pumpWidget(
      _app(
        const SessionMetricTiles(
          elapsedDisplay: '00:42',
          rubricChild: Text('—'),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.pump();

    expect(tester.widget<Text>(find.text('00:42')).style!.fontSize, 22);
  });

  testWidgets('mastered rank badge uses milestone gold', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    late Color milestone;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            milestone = context.elixColors.milestone;
            return RankBadge(level: PerformanceLevel.mastered);
          },
        ),
      ),
    );
    await tester.pump();

    final label = tester.widget<Text>(
      find.text(PerformanceLevel.mastered.shortLabel),
    );
    expect(label.style!.color, milestone);
  });

  testWidgets('rank badge drops glow in high contrast', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        RankBadge(level: PerformanceLevel.proficient),
        theme: AppTheme.highContrastDark,
      ),
    );
    await tester.pump();

    final badge = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.boxShadow, isEmpty);
  });

  testWidgets('assigned practice prop picker uses compact editorial heading', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        AssignedPracticePropPicker(
          movementName: 'Hand Stall',
          selectedProp: TrainingProp.bottle,
          supportedProps: const [TrainingProp.bottle, TrainingProp.shaker],
          onPropChanged: (_) {},
          onStart: () {},
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ElixEditorialHeader), findsOneWidget);
    final editorial = tester.widget<ElixEditorialHeader>(
      find.byType(ElixEditorialHeader),
    );
    expect(editorial.variant, ElixEditorialHeaderVariant.compact);

    final heading = tester.widget<Text>(find.text('Hand Stall'));
    expect(heading.style!.fontSize, 24);
    expect(heading.style!.fontFamily, ElixTypography.fontFamily);

    expect(find.text('Training prop'), findsOneWidget);
    expect(find.text('Start guided practice'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('live practice elapsed readout uses metric type scale', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(const LivePracticeElapsedMetric(elapsedDisplay: '01:05')),
    );
    await tester.pump();

    expect(find.text('ELAPSED'), findsOneWidget);
    final elapsed = tester.widget<Text>(find.text('01:05'));
    expect(elapsed.style!.fontSize, 44);
    expect(elapsed.style!.fontFamily, ElixTypography.fontFamily);
    expect(elapsed.style!.fontFamily, isNot(AppTheme.brandFontFamily));
  });

  testWidgets('live practice elapsed readout compact breakpoint uses 36px', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 640));
    await tester.pumpWidget(
      _app(
        const LivePracticeElapsedMetric(elapsedDisplay: '01:05'),
        size: const Size(800, 640),
      ),
    );
    await tester.pump();

    expect(tester.widget<Text>(find.text('01:05')).style!.fontSize, 36);
  });
}
