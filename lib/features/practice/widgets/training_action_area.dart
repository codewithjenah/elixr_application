import 'package:fluent_ui/fluent_ui.dart';

import '../practice_game_widgets.dart';

enum TrainingActionKind { start, cancel, finish, retry }

/// Presentation for Start / Cancel / Finish / Retry. Pinning is owned by the panel.
class TrainingActionArea extends StatelessWidget {
  const TrainingActionArea({
    super.key,
    required this.kind,
    required this.startLabel,
    this.onPressed,
    this.isLoading = false,
  });

  final TrainingActionKind kind;

  /// e.g. "Start Session" or "Start Free Practice"
  final String startLabel;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final button = switch (kind) {
      TrainingActionKind.finish => GameActionButton(
        label: 'Finish Session',
        icon: FluentIcons.stop_solid,
        danger: true,
        onPressed: onPressed,
      ),
      TrainingActionKind.cancel => GameActionButton(
        label: 'Cancel',
        icon: FluentIcons.cancel,
        danger: true,
        onPressed: onPressed,
      ),
      TrainingActionKind.retry => GameActionButton(
        label: 'Retry',
        icon: FluentIcons.play_solid,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
      TrainingActionKind.start => GameActionButton(
        label: startLabel,
        icon: FluentIcons.play_solid,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
    };

    return KeyedSubtree(
      key: const ValueKey('practice-primary-action'),
      child: button,
    );
  }
}
