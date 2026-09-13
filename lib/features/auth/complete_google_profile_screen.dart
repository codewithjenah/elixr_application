import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;
import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/repositories/auth_repository.dart';

import '../../core/auth/teacher_auth_messages.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_form_chrome.dart';
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
  late final TextEditingController _accessCodeController;
  GoogleOnboardingIntent? _selectedIntent;
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
    _accessCodeController = TextEditingController(
      text: pending?.teacherAccessCode ?? '',
    );
    _selectedIntent = switch (pending?.intent) {
      GoogleOnboardingIntent.trainee => GoogleOnboardingIntent.trainee,
      GoogleOnboardingIntent.teacher => GoogleOnboardingIntent.teacher,
      _ => null,
    };
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _accessCodeController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_isSaving || _isCancelling) return;
    final nameError = validateUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
    final selectedIntent = _selectedIntent;
    final teacherCode = CoachCode.tryNormalize(_accessCodeController.text);
    if (selectedIntent == null) {
      setState(() => _error = 'Choose Trainee or Teacher to continue.');
      return;
    }
    if (nameError != null || !_agreedToLegal) {
      setState(() {
        _error = nameError ?? TeacherAuthMessages.legalConsentRequired;
      });
      return;
    }
    if (selectedIntent == GoogleOnboardingIntent.teacher &&
        teacherCode == null) {
      setState(() => _error = TeacherAuthMessages.accessCodeInvalid);
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
      final auth = context.read<AuthService>();
      if (selectedIntent == GoogleOnboardingIntent.teacher) {
        await auth.completeGoogleTeacherProfile(
          firstName: normalized.firstName,
          middleName: normalized.middleName,
          lastName: normalized.lastName,
          teacherAccessCode: teacherCode!,
          legalConsent: RegistrationLegalConsent.current(),
        );
      } else {
        await auth.completeGoogleProfile(
          firstName: normalized.firstName,
          middleName: normalized.middleName,
          lastName: normalized.lastName,
          legalConsent: RegistrationLegalConsent.current(),
        );
      }
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
    if (_isSaving || _isCancelling) return;
    setState(() => _isCancelling = true);
    try {
      await context.read<AuthService>().cancelGoogleOnboarding();
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIntent = _selectedIntent;
    final choosingRole = selectedIntent == null;
    final isTeacher = selectedIntent == GoogleOnboardingIntent.teacher;
    final pending = context.read<AuthService>().pendingGoogleProfile;
    final isGoogle =
        pending?.identityProvider == ProfileIdentityProvider.google;
    return AuthScaffold(
      title: isTeacher
          ? 'Create your Teacher profile'
          : 'Complete your profile',
      subtitle: choosingRole
          ? 'Choose how to finish this Google sign-in'
          : isTeacher
          ? 'One last step before your Teacher dashboard'
          : 'One last step before training',
      formTitle: choosingRole ? 'Choose your ELIXR role' : 'Your ELIXR profile',
      formSubtitle: choosingRole
          ? 'This Google sign-in has no saved role selection. Teacher registration requires a new access code.'
          : isTeacher
          ? 'Google verified your email. Confirm your name and access code.'
          : isGoogle
          ? 'Google verified your email. Add your preferred name.'
          : 'Your sign-in is valid. Finish the missing ELIXR profile.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (choosingRole) ...[
            _GoogleRoleSelector(
              selectedIntent: selectedIntent,
              onChanged: (intent) => setState(() => _selectedIntent = intent),
            ),
            if (selectedIntent == null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Select a role to continue. Your Google account will not be converted between roles.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
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
          Text(isGoogle ? 'Verified Google email' : 'Account email'),
          const SizedBox(height: AppSpacing.xs),
          _ReadOnlyEmailField(controller: _emailController),
          if (isTeacher) ...[
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              key: const Key('google_profile_teacher_access_code'),
              controller: _accessCodeController,
              label: 'Teacher access code',
              placeholder: 'XXXX-XXXX-XXXX',
              icon: FluentIcons.permissions,
              helperText:
                  'The code is consumed only when this profile is created.',
              validationText:
                  _accessCodeController.text.isEmpty ||
                      CoachCode.tryNormalize(_accessCodeController.text) != null
                  ? null
                  : TeacherAuthMessages.accessCodeInvalid,
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AuthLegalConsent(
            checkboxKey: const Key('google_profile_legal_consent'),
            agreed: _agreedToLegal,
            onChanged: (agreed) => setState(() => _agreedToLegal = agreed),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          ElixPrimaryButton(
            label: choosingRole
                ? 'Choose a role'
                : isTeacher
                ? 'Create Teacher Profile'
                : 'Create Trainee Profile',
            isLoading: _isSaving,
            onPressed: _isCancelling ? null : _complete,
          ),
          const SizedBox(height: AppSpacing.xs),
          _GoogleSecondaryButton(
            onPressed: _isSaving || _isCancelling ? null : _cancel,
            child: _isCancelling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Text('Cancel and sign out'),
          ),
        ],
      ),
    );
  }
}

class _GoogleRoleSelector extends StatelessWidget {
  const _GoogleRoleSelector({
    required this.selectedIntent,
    required this.onChanged,
  });

  final GoogleOnboardingIntent? selectedIntent;
  final ValueChanged<GoogleOnboardingIntent> onChanged;

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioButton(
            key: const Key('google_profile_trainee_role'),
            checked: selectedIntent == GoogleOnboardingIntent.trainee,
            onChanged: (checked) {
              if (checked) onChanged(GoogleOnboardingIntent.trainee);
            },
            content: const Text(
              'Trainee — Practice movements and track progress.',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          RadioButton(
            key: const Key('google_profile_teacher_role'),
            checked: selectedIntent == GoogleOnboardingIntent.teacher,
            onChanged: (checked) {
              if (checked) onChanged(GoogleOnboardingIntent.teacher);
            },
            content: const Text('Teacher — Manage classrooms and assignments.'),
          ),
        ],
      );
    }
    return shad.ShadRadioGroup<GoogleOnboardingIntent>(
      initialValue: selectedIntent,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      items: const [
        shad.ShadRadio(
          key: Key('google_profile_trainee_role'),
          value: GoogleOnboardingIntent.trainee,
          label: Text('Trainee — Practice movements and track progress.'),
        ),
        shad.ShadRadio(
          key: Key('google_profile_teacher_role'),
          value: GoogleOnboardingIntent.teacher,
          label: Text('Teacher — Manage classrooms and assignments.'),
        ),
      ],
    );
  }
}

class _ReadOnlyEmailField extends StatelessWidget {
  const _ReadOnlyEmailField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return TextBox(
        key: const Key('google_profile_email'),
        controller: controller,
        readOnly: true,
        enabled: false,
      );
    }
    return shad.ShadInput(
      key: const Key('google_profile_email'),
      controller: controller,
      readOnly: true,
      enabled: false,
    );
  }
}

class _GoogleSecondaryButton extends StatelessWidget {
  const _GoogleSecondaryButton({required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? Button(onPressed: onPressed, child: child)
      : shad.ShadButton.ghost(onPressed: onPressed, child: child);
}
