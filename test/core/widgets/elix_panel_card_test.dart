import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('accent bar supports LayoutBuilder content', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 480,
          child: ElixPanelCard(
            accent: AppColors.primary,
            showAccentBar: true,
            child: LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: constraints.maxWidth > 0 ? 80 : 0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
