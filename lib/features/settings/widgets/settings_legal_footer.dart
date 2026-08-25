import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';

/// Quiet Privacy Policy / Terms links for Teacher Settings (dialog or page).
class SettingsLegalFooter extends StatelessWidget {
  const SettingsLegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            color: context.elixBorder.withValues(alpha: 0.35),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            'LEGAL',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary.withValues(alpha: 0.75),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          const _LegalTextLink(
            label: 'Privacy Policy',
            route: AppRoutePaths.privacyPolicy,
          ),
          const SizedBox(height: 4),
          const _LegalTextLink(
            label: 'Terms of Service',
            route: AppRoutePaths.termsOfService,
          ),
        ],
      ),
    );
  }
}

class _LegalTextLink extends StatefulWidget {
  const _LegalTextLink({required this.label, required this.route});

  final String label;
  final String route;

  @override
  State<_LegalTextLink> createState() => _LegalTextLinkState();
}

class _LegalTextLinkState extends State<_LegalTextLink> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused;
    final color = active ? context.elixTextPrimary : context.elixTextSecondary;

    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            context.push(widget.route);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => context.push(widget.route),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                widget.label,
                style: AppTheme.caption.copyWith(
                  color: color,
                  fontSize: 12,
                  height: 1.3,
                  decoration: active ? TextDecoration.underline : null,
                  decorationColor: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
