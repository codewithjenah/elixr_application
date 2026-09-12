import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps ELIXR light semantic colors into the Shadcn theme', () {
    final theme = AppTheme.shadTheme(
      ElixSemanticColors.light,
      brightness: Brightness.light,
    );

    expect(theme.colorScheme.primary, ElixSemanticColors.light.brandPrimary);
    expect(theme.colorScheme.card, ElixSemanticColors.light.surfaceRaised);
    expect(theme.colorScheme.ring, ElixSemanticColors.light.focusRing);
    expect(theme.textTheme.family, 'Manrope');
  });

  test('maps ELIXR high-contrast colors without changing brightness', () {
    final theme = AppTheme.shadTheme(
      ElixSemanticColors.highContrastDark,
      brightness: Brightness.dark,
    );

    expect(theme.brightness, Brightness.dark);
    expect(
      theme.colorScheme.border,
      ElixSemanticColors.highContrastDark.borderSubtle,
    );
  });
}
