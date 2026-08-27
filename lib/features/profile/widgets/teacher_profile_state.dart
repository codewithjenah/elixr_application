import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_theme.dart';
import 'profile_section_card.dart';

/// Identity-only body for a teacher-owned public profile.
class TeacherProfileState extends StatelessWidget {
  const TeacherProfileState({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      title: 'Teacher account',
      child: Text(
        'Teacher profiles do not track achievements or completed movements.',
        style: AppTheme.bodySecondary.copyWith(
          color: context.elixTextSecondary,
        ),
      ),
    );
  }
}
