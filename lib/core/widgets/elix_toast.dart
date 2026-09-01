import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// A compact, in-app acknowledgement that floats above page content.
///
/// ELIXR shows one toast at a time. A newer acknowledgement replaces the
/// current one so routine classroom actions cannot build a notification stack.
abstract final class ElixToast {
  static OverlayEntry? _currentEntry;

  static void showSuccess(BuildContext context, {required String message}) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _currentEntry?.remove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ElixToast(
        message: message,
        onDismissed: () {
          if (identical(_currentEntry, entry)) _currentEntry = null;
          entry.remove();
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _ElixToast extends StatefulWidget {
  const _ElixToast({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_ElixToast> createState() => _ElixToastState();
}

class _ElixToastState extends State<_ElixToast>
    with SingleTickerProviderStateMixin {
  static const _displayDuration = Duration(milliseconds: 3600);

  late final AnimationController _animationController;
  Timer? _dismissTimer;
  bool _dismissed = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: ElixMotion.standard,
      reverseDuration: ElixMotion.standard,
    );
    _dismissTimer = Timer(_displayDuration, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _animationController.value = 1;
    } else if (_animationController.value == 0) {
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissed) return;
    _dismissed = true;
    _dismissTimer?.cancel();
    if (!_reducedMotion) await _animationController.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    final success = context.elixColors.success;
    final width = MediaQuery.sizeOf(context).width;
    final toastWidth = (width - (AppSpacing.md * 2))
        .clamp(0.0, 400.0)
        .toDouble();
    final animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned(
      right: AppSpacing.md,
      bottom: AppSpacing.md,
      width: toastWidth,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Success: ${widget.message}',
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: Container(
              key: const Key('elix_toast'),
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: highContrast
                      ? context.elixBorder
                      : success.withValues(alpha: isDark ? 0.5 : 0.38),
                  width: highContrast ? 2 : 1,
                ),
                boxShadow: highContrast
                    ? const []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.32 : 0.12,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      FluentIcons.completed_solid,
                      size: 18,
                      color: success,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: AppTheme.bodySecondary.copyWith(
                        color: context.elixTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Semantics(
                    button: true,
                    label: 'Dismiss notification',
                    child: IconButton(
                      key: const Key('elix_toast_close'),
                      icon: Icon(
                        FluentIcons.chrome_close,
                        size: 12,
                        color: context.elixTextSecondary,
                      ),
                      onPressed: _dismiss,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
