import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_border_frame.dart';
import 'package:elixr_application/core/widgets/profile_border_painter.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(
  Widget child, {
  bool disableAnimations = false,
  bool tickerEnabled = true,
}) {
  return FluentApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ScaffoldPage(
        content: TickerMode(
          enabled: tickerEnabled,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('known border renders decorative painter', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'starter_glow',
          child: const ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(paints.any((p) => p.painter is ProfileBorderPainter), isTrue);
  });

  testWidgets('unknown border uses neutral fallback', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'not_a_real_border',
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );

    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(paints.any((p) => p.painter is NeutralProfileBorderPainter), isTrue);
    expect(paints.any((p) => p.painter is ProfileBorderPainter), isFalse);
  });

  testWidgets('showBorder false renders no decorative painter', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'starter_glow',
          showBorder: false,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );

    final paints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(ProfileBorderFrame),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paints, isEmpty);
    final box = tester.getSize(
      find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 64 && w.height == 64,
      ),
    );
    expect(box, const Size(64, 64));
  });

  testWidgets('static mode creates no continuously ticking animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: false,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    expect(state.debugAnimationController, isNull);
    expect(state.debugIsAnimating, isFalse);
  });

  testWidgets('animated mode advances when TickerMode is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    expect(state.debugAnimationController, isNotNull);
    expect(state.debugIsAnimating, isTrue);

    final before = state.debugAnimationController!.value;
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.debugAnimationController!.value, isNot(equals(before)));
  });

  testWidgets('animation stops when TickerMode is disabled', (tester) async {
    await tester.pumpWidget(
      wrap(
        tickerEnabled: false,
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'gold_mastery',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    expect(state.debugAnimationController, isNull);
    expect(state.debugIsAnimating, isFalse);
  });

  testWidgets('reduced-motion mode does not continuously animate', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        disableAnimations: true,
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'tin_specialist',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    expect(state.debugAnimationController, isNull);
    expect(state.debugIsAnimating, isFalse);
  });

  testWidgets('child avatar remains centered with stable diameter', (
    tester,
  ) async {
    const childKey = Key('avatar-child');
    await tester.pumpWidget(
      wrap(
        ProfileBorderFrame(
          size: 80,
          equippedBorderId: 'perfect_serve',
          child: const ColoredBox(key: childKey, color: Color(0xFF333333)),
        ),
      ),
    );

    final childSize = tester.getSize(find.byKey(childKey));
    expect(childSize, const Size(80, 80));

    final frameSize = tester.getSize(find.byType(ProfileBorderFrame));
    final padding = profileBorderById('perfect_serve')!.ornamentExtent;
    expect(frameSize.width, closeTo(80 + padding * 2, 0.1));
    expect(frameSize.height, closeTo(80 + padding * 2, 0.1));

    final frameCenter = tester.getCenter(find.byType(ProfileBorderFrame));
    final childCenter = tester.getCenter(find.byKey(childKey));
    expect(childCenter.dx, closeTo(frameCenter.dx, 0.5));
    expect(childCenter.dy, closeTo(frameCenter.dy, 0.5));
  });

  testWidgets('ornamental layout stays within allocated widget bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 200,
          height: 200,
          child: Center(
            child: ProfileBorderFrame(
              size: 72,
              equippedBorderId: 'tin_specialist',
              animate: true,
              child: const ColoredBox(color: Color(0xFF222222)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final frame = tester.getRect(find.byType(ProfileBorderFrame));
    expect(frame.width, lessThanOrEqualTo(200));
    expect(frame.height, lessThanOrEqualTo(200));
  });

  testWidgets('highlight accent and cosmetic frame can coexist', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'week_warrior',
          highlightAccent: const Color(0xFFFFC107),
          child: const ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );

    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    final painter = paints
        .map((p) => p.painter)
        .whereType<ProfileBorderPainter>()
        .first;
    expect(painter.highlightAccent, const Color(0xFFFFC107));
  });

  testWidgets('animate true creates and runs a single controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    expect(state.debugAnimationController, isNotNull);
    expect(state.debugIsAnimating, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animate true→false→true reuses the same controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    final first = state.debugAnimationController;
    expect(first, isNotNull);
    expect(state.debugIsAnimating, isTrue);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: false,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equippedBorderId known→null→known reuses one controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    final first = state.debugAnimationController;
    expect(first, isNotNull);
    expect(state.debugIsAnimating, isTrue);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: null,
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'gold_mastery',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showBorder true→false→true reuses the same controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'starter_glow',
          animate: true,
          showBorder: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    final first = state.debugAnimationController;
    expect(first, isNotNull);
    expect(state.debugIsAnimating, isTrue);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'starter_glow',
          animate: true,
          showBorder: false,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'starter_glow',
          animate: true,
          showBorder: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode enabled→disabled→enabled reuses one controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        tickerEnabled: true,
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    final first = state.debugAnimationController;
    expect(first, isNotNull);
    expect(state.debugIsAnimating, isTrue);

    await tester.pumpWidget(
      wrap(
        tickerEnabled: false,
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(
        tickerEnabled: true,
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();
    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugIsAnimating, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'MediaQuery.disableAnimations false→true→false reuses one controller',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          disableAnimations: false,
          const ProfileBorderFrame(
            size: 64,
            equippedBorderId: 'gold_mastery',
            animate: true,
            child: ColoredBox(color: Color(0xFF222222)),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<ProfileBorderFrameState>(
        find.byType(ProfileBorderFrame),
      );
      final first = state.debugAnimationController;
      expect(first, isNotNull);
      expect(state.debugIsAnimating, isTrue);

      await tester.pumpWidget(
        wrap(
          disableAnimations: true,
          const ProfileBorderFrame(
            size: 64,
            equippedBorderId: 'gold_mastery',
            animate: true,
            child: ColoredBox(color: Color(0xFF222222)),
          ),
        ),
      );
      await tester.pump();
      expect(identical(state.debugAnimationController, first), isTrue);
      expect(state.debugIsAnimating, isFalse);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        wrap(
          disableAnimations: false,
          const ProfileBorderFrame(
            size: 64,
            equippedBorderId: 'gold_mastery',
            animate: true,
            child: ColoredBox(color: Color(0xFF222222)),
          ),
        ),
      );
      await tester.pump();
      expect(identical(state.debugAnimationController, first), isTrue);
      expect(state.debugIsAnimating, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching known borders updates duration on same controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'cyan_orbit',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<ProfileBorderFrameState>(
      find.byType(ProfileBorderFrame),
    );
    final first = state.debugAnimationController!;
    final cyanDuration = Duration(
      milliseconds: profileBorderById('cyan_orbit')!.animationDurationMs,
    );
    final goldDuration = Duration(
      milliseconds: profileBorderById('gold_mastery')!.animationDurationMs,
    );
    expect(cyanDuration, isNot(equals(goldDuration)));
    expect(first.duration, cyanDuration);

    await tester.pumpWidget(
      wrap(
        const ProfileBorderFrame(
          size: 64,
          equippedBorderId: 'gold_mastery',
          animate: true,
          child: ColoredBox(color: Color(0xFF222222)),
        ),
      ),
    );
    await tester.pump();

    expect(identical(state.debugAnimationController, first), isTrue);
    expect(state.debugAnimationController!.duration, goldDuration);
    expect(state.debugIsAnimating, isTrue);
    expect(tester.takeException(), isNull);
  });
}
