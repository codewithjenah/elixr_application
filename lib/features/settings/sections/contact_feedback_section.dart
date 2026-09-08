import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../widgets/settings_components.dart';

typedef ContactEmailLauncher = Future<bool> Function(Uri uri);
typedef ContactClipboardWriter = Future<void> Function(String text);

/// Mail and clipboard actions used by [ContactFeedbackSection].
///
/// Keeping URI construction and platform calls here makes the user-facing
/// actions testable without attempting to start a Windows mail client.
abstract final class ContactFeedbackActions {
  static const email = 'elixr.org@gmail.com';
  static const bugReportSubject = 'ELIXR Bug Report';
  static const feedbackSubject = 'ELIXR Feedback';

  static Uri get bugReportUri => _emailUri(bugReportSubject);
  static Uri get feedbackUri => _emailUri(feedbackSubject);

  static Uri _emailUri(String subject) =>
      Uri(scheme: 'mailto', path: email, queryParameters: {'subject': subject});

  static Future<bool> launchEmail(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<void> copyEmail(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// Support actions shared by Trainee and Teacher Settings.
class ContactFeedbackSection extends StatefulWidget {
  const ContactFeedbackSection({
    super.key,
    this.launchEmail = ContactFeedbackActions.launchEmail,
    this.copyToClipboard = ContactFeedbackActions.copyEmail,
  });

  final ContactEmailLauncher launchEmail;
  final ContactClipboardWriter copyToClipboard;

  @override
  State<ContactFeedbackSection> createState() => _ContactFeedbackSectionState();
}

class _ContactFeedbackSectionState extends State<ContactFeedbackSection> {
  bool _launching = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _prepareEmail(Uri uri) async {
    if (_launching) return;
    setState(() {
      _launching = true;
      _status = null;
    });
    try {
      final launched = await widget.launchEmail(uri);
      if (!mounted) return;
      setState(() {
        _status = launched
            ? 'Your email application is ready.'
            : 'Could not open an email application. You can copy the email address instead.';
        _statusIsError = !launched;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status =
            'Could not open an email application. You can copy the email address instead.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _copyEmail() async {
    try {
      await widget.copyToClipboard(ContactFeedbackActions.email);
      if (!mounted) return;
      setState(() {
        _status = 'Email copied';
        _statusIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not copy the email address. Please try again.';
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONTACT & FEEDBACK',
            style: AppTheme.eyebrow(color: context.elixColors.brandPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ElixPanelCard(
            accent: context.elixColors.brandPrimary,
            showAccentBar: true,
            variant: ElixPanelVariant.hero,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ContactIcon(icon: FluentIcons.mail),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'We’d like to hear from you',
                        style: AppTheme.headingMedium.copyWith(
                          color: context.elixTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Found a bug or have feedback? Tell us what happened or how '
                  'we can improve ELIXR.',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    height: 1.45,
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support email',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  ContactFeedbackActions.email,
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 18,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Button(
                  key: const Key('contact_feedback_copy_email'),
                  onPressed: _copyEmail,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.copy, size: 16),
                      SizedBox(width: AppSpacing.sm),
                      Text('Copy email address'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ContactActionCard(
            icon: FluentIcons.bug,
            title: 'Report a bug',
            description: 'Tell us about an error or unexpected behavior.',
            buttonLabel: 'Report a bug',
            loading: _launching,
            onPressed: () => _prepareEmail(ContactFeedbackActions.bugReportUri),
          ),
          const SizedBox(height: AppSpacing.md),
          _ContactActionCard(
            icon: FluentIcons.feedback,
            title: 'Send feedback',
            description:
                'Share suggestions or comments about your ELIXR experience.',
            buttonLabel: 'Send feedback',
            loading: _launching,
            onPressed: () => _prepareEmail(ContactFeedbackActions.feedbackUri),
          ),
          if (_status != null)
            SettingsStatusBanner(
              message: _status!,
              isError: _statusIsError,
              isSuccess: !_statusIsError,
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _ContactIcon extends StatelessWidget {
  const _ContactIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixColors.brandPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: context.elixColors.brandPrimary),
    );
  }
}

class _ContactActionCard extends StatelessWidget {
  const _ContactActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.loading,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 410;
          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ContactIcon(icon: icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final button = ElixPrimaryButton(
            label: buttonLabel,
            icon: icon,
            expanded: compact,
            dense: true,
            isLoading: loading,
            onPressed: loading ? null : onPressed,
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: AppSpacing.md),
                    button,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: AppSpacing.md),
                    button,
                  ],
                );
        },
      ),
    );
  }
}
