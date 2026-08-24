import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/repositories/auth_repository.dart';

import '../../core/auth/teacher_auth_messages.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
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
            RadioButton(
              key: const Key('google_profile_trainee_role'),
              checked: selectedIntent == GoogleOnboardingIntent.trainee,
              onChanged: (checked) {
                if (checked) {
                  setState(
                    () => _selectedIntent = GoogleOnboardingIntent.trainee,
                  );
                }
              },
              content: const Text('Trainee'),
            ),
            const SizedBox(height: AppSpacing.xs),
            RadioButton(
              key: const Key('google_profile_teacher_role'),
              checked: selectedIntent == GoogleOnboardingIntent.teacher,
              onChanged: (checked) {
                if (checked) {
                  setState(
                    () => _selectedIntent = GoogleOnboardingIntent.teacher,
                  );
                }
              },
              content: const Text('Teacher'),
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
          TextBox(
            key: const Key('google_profile_email'),
            controller: _emailController,
            readOnly: true,
            enabled: false,
          ),
          if (isTeacher) ...[
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              key: const Key('google_profile_teacher_access_code'),
              controller: _accessCodeController,
              label: 'Teacher access code',
              placeholder: '7KPM-XR4D-Q2WT',
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
            label: choosingRole
                ? 'Choose a role'
                : isTeacher
                ? 'Create Teacher Profile'
                : 'Create Trainee Profile',
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
