import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

/// Returns through the real navigation history when a drill-down page was
/// opened from another screen. Direct links fall back to a safe destination.
void popOrGo(BuildContext context, String fallbackLocation) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackLocation);
  }
}
