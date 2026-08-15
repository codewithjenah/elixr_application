import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_theme.dart';

/// Standard ELIXR page surface with the application-wide ambient background.
///
/// This preserves Fluent's [ScaffoldPage] layout behavior while making its
/// otherwise solid scaffold surface transparent so the ambient decoration is
/// visible behind headers, content, and the bottom bar.
class ElixScaffoldPage extends StatelessWidget {
  const ElixScaffoldPage({
    super.key,
    this.header,
    this.content = const SizedBox.expand(),
    this.bottomBar,
    this.padding,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget? header;
  final Widget content;
  final Widget? bottomBar;
  final EdgeInsets? padding;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DecoratedBox(
      decoration: AppTheme.ambientPageBackground(context),
      child: FluentTheme(
        data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
        child: ScaffoldPage(
          header: header,
          content: content,
          bottomBar: bottomBar,
          padding: padding,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        ),
      ),
    );
  }
}
