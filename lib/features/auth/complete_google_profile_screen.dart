import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';

class CompleteGoogleProfileScreen extends StatefulWidget {
  const CompleteGoogleProfileScreen({super.key});

  @override
  State<CompleteGoogleProfileScreen> createState() =>
      _CompleteGoogleProfileScreenState();
}

class _CompleteGoogleProfileScreenState
    extends State<CompleteGoogleProfileScreen> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  bool _agreedToLegal = false;
  bool _isSaving = false;
  bool _isCancelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pending = context.read<AuthService>().pendingGoogleProfile;
    _firstNameController = TextEditingController(
      text: pending?.firstName ?? '',
    );
    _middleNameController = TextEditingController(
      text: pending?.middleName ?? '',
    );
    _lastNameController = TextEditingController(text: pending?.lastName ?? '');
    _emailController = TextEditingController(text: pending?.email ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final nameError = validateUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
    if (nameError != null || !_agreedToLegal) {
      setState(() {
        _error =
            nameError ?? 'Accept the Privacy Policy and Terms to continue.';
      });
      return;
    }
    final normalized = normalizeUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().completeGoogleProfile(
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _isCancelling = true);
    try {
      await context.read<AuthService>().cancelGoogleOnboarding();
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Complete your profile',
      subtitle: 'One last step before training',
      formTitle: 'Your ELIXR profile',
      formSubtitle: 'Google verified your email. Add your preferred name.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: _firstNameController,
            label: 'First name',
            placeholder: 'First name',
            icon: FluentIcons.contact,
          ),
          const SizedBox(height: AppSpacing.sm),
          AuthTextField(
            controller: _middleNameController,
            label: 'Middle name (optional)',
            placeholder: 'Middle name (optional)',
            icon: FluentIcons.contact,
          ),
          const SizedBox(height: AppSpacing.sm),
          AuthTextField(
            controller: _lastNameController,
            label: 'Last name',
            placeholder: 'Last name',
            icon: FluentIcons.contact,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Verified Google email'),
          const SizedBox(height: AppSpacing.xs),
          TextBox(
            key: const Key('google_profile_email'),
            controller: _emailController,
            readOnly: true,
            enabled: false,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                key: const Key('google_profile_legal_consent'),
                checked: _agreedToLegal,
                onChanged: (value) =>
                    setState(() => _agreedToLegal = value == true),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Wrap(
                  children: [
                    const Text('I agree to the '),
                    HyperlinkButton(
                      onPressed: () =>
                          context.push(AppRoutePaths.privacyPolicy),
                      child: const Text('Privacy Policy'),
                    ),
                    const Text(' and '),
                    HyperlinkButton(
                      onPressed: () =>
                          context.push(AppRoutePaths.termsOfService),
                      child: const Text('Terms of Service'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          ElixPrimaryButton(
            label: 'Create Trainee Profile',
            isLoading: _isSaving,
            onPressed: _isCancelling ? null : _complete,
          ),
          const SizedBox(height: AppSpacing.xs),
          Button(
            onPressed: _isSaving || _isCancelling ? null : _cancel,
            child: _isCancelling
                ? const ProgressRing(strokeWidth: 2)
                : const Text('Cancel and sign out'),
          ),
        ],
      ),
    );
  }
}
