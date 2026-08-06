import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _panelButtonWidth = 338.0;
const _centerTolerance = 1.5;

Widget _wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(content: child),
  );
}

Future<void> pumpButton(
  WidgetTester tester, {
  required GameActionButton button,
  required double width,
}) async {
  await tester.pumpWidget(
    _wrap(
      Center(
        child: SizedBox(width: width, child: button),
      ),
    ),
  );
  await tester.pump();
}

Offset _buttonCenter(WidgetTester tester, Key key) {
  return tester.getRect(find.byKey(key)).center;
}

Offset _iconCenter(WidgetTester tester, Key key) {
  return tester.getCenter(
    find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
  );
}

Offset _labelCenter(WidgetTester tester, String label) {
  return tester.getCenter(find.text(label));
}

void _expectCentered(double actual, double expected, {String? reason}) {
  expect(actual, closeTo(expected, _centerTolerance), reason: reason);
}

GameActionButton _button({
  required Key key,
  required String label,
  required IconData icon,
  VoidCallback? onPressed,
  bool isLoading = false,
  bool danger = false,
}) {
  return GameActionButton(
    key: key,
    label: label,
    icon: icon,
    onPressed: onPressed ?? () {},
    isLoading: isLoading,
    danger: danger,
  );
}

void main() {
  group('GameActionButton layout', () {
    testWidgets('icons share a consistent lane across action variants', (
      tester,
    ) async {
      const variants = <({Key key, String label, IconData icon, bool danger})>[
        (
          key: Key('start'),
          label: 'Start Practice',
          icon: FluentIcons.play_solid,
          danger: false,
        ),
        (
          key: Key('cancel'),
          label: 'Cancel',
          icon: FluentIcons.cancel,
          danger: true,
        ),
        (
          key: Key('retry'),
          label: 'Retry',
          icon: FluentIcons.play_solid,
          danger: false,
        ),
        (
          key: Key('finish'),
          label: 'Finish Session',
          icon: FluentIcons.stop_solid,
          danger: true,
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: _panelButtonWidth,
            child: Column(
              children: [
                for (final variant in variants)
                  _button(
                    key: variant.key,
                    label: variant.label,
                    icon: variant.icon,
                    danger: variant.danger,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final reference = _iconCenter(tester, variants.first.key).dx;
      for (final variant in variants.skip(1)) {
        _expectCentered(
          _iconCenter(tester, variant.key).dx,
          reference,
          reason: 'Icon lane for ${variant.label}',
        );
      }
    });

    testWidgets('labels are centered on the full button width', (tester) async {
      const cases = <({Key key, String label, IconData icon})>[
        (
          key: Key('start'),
          label: 'Start Practice',
          icon: FluentIcons.play_solid,
        ),
        (key: Key('cancel'), label: 'Cancel', icon: FluentIcons.cancel),
        (key: Key('retry'), label: 'Retry', icon: FluentIcons.play_solid),
        (
          key: Key('finish'),
          label: 'Finish Session',
          icon: FluentIcons.stop_solid,
        ),
      ];

      for (final buttonCase in cases) {
        await pumpButton(
          tester,
          width: _panelButtonWidth,
          button: _button(
            key: buttonCase.key,
            label: buttonCase.label,
            icon: buttonCase.icon,
          ),
        );

        final buttonCenter = _buttonCenter(tester, buttonCase.key);
        final labelCenter = _labelCenter(tester, buttonCase.label);
        _expectCentered(
          labelCenter.dx,
          buttonCenter.dx,
          reason: buttonCase.label,
        );
      }
    });

    testWidgets('different icon glyphs do not shift the icon lane', (
      tester,
    ) async {
      const glyphs = <({Key key, IconData icon})>[
        (key: Key('play'), icon: FluentIcons.play_solid),
        (key: Key('cancel'), icon: FluentIcons.cancel),
        (key: Key('stop'), icon: FluentIcons.stop_solid),
      ];

      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: _panelButtonWidth,
            child: Column(
              children: [
                for (final glyph in glyphs)
                  _button(key: glyph.key, label: 'Action', icon: glyph.icon),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final reference = _iconCenter(tester, glyphs.first.key).dx;
      for (final glyph in glyphs.skip(1)) {
        _expectCentered(
          _iconCenter(tester, glyph.key).dx,
          reference,
          reason: glyph.icon.toString(),
        );
      }
    });

    testWidgets('loading spinner stays centered', (tester) async {
      await pumpButton(
        tester,
        width: _panelButtonWidth,
        button: _button(
          key: const Key('loading'),
          label: 'Retry',
          icon: FluentIcons.play_solid,
          isLoading: true,
        ),
      );

      final buttonCenter = _buttonCenter(tester, const Key('loading'));
      final spinnerCenter = tester.getCenter(find.byType(ProgressRing));
      _expectCentered(spinnerCenter.dx, buttonCenter.dx);
      _expectCentered(spinnerCenter.dy, buttonCenter.dy);
    });

    testWidgets('disabled state preserves layout geometry', (tester) async {
      await pumpButton(
        tester,
        width: _panelButtonWidth,
        button: _button(
          key: const Key('disabled'),
          label: 'Start Practice',
          icon: FluentIcons.play_solid,
          onPressed: null,
        ),
      );

      final buttonCenter = _buttonCenter(tester, const Key('disabled'));
      final labelCenter = _labelCenter(tester, 'Start Practice');
      final iconCenter = _iconCenter(tester, const Key('disabled'));

      _expectCentered(labelCenter.dx, buttonCenter.dx);
      expect(iconCenter.dy, closeTo(buttonCenter.dy, _centerTolerance));
    });

    testWidgets('narrow width does not overflow', (tester) async {
      await pumpButton(
        tester,
        width: 240,
        button: _button(
          key: const Key('narrow'),
          label: 'Start Free Practice',
          icon: FluentIcons.play_solid,
        ),
      );

      expect(tester.takeException(), isNull);
      final buttonCenter = _buttonCenter(tester, const Key('narrow'));
      final labelCenter = _labelCenter(tester, 'Start Free Practice');
      _expectCentered(labelCenter.dx, buttonCenter.dx);
    });

    testWidgets('long labels stay centered and ellipsize when needed', (
      tester,
    ) async {
      await pumpButton(
        tester,
        width: 160,
        button: _button(
          key: const Key('ellipsis'),
          label: 'Start Free Practice',
          icon: FluentIcons.play_solid,
        ),
      );

      expect(tester.takeException(), isNull);
      final buttonCenter = _buttonCenter(tester, const Key('ellipsis'));
      final labelCenter = _labelCenter(tester, 'Start Free Practice');
      _expectCentered(labelCenter.dx, buttonCenter.dx);
    });
  });
}
