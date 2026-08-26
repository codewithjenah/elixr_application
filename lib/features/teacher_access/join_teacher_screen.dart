import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/repositories/session_evidence_repository.dart';
import '../../services/auth_service.dart';
import '../../services/join_code_resolver.dart';
import '../../services/join_link_service.dart';
import 'teacher_access_controller.dart';
import 'teacher_access_section.dart';

class TeacherAccessScreen extends StatefulWidget {
  const TeacherAccessScreen({super.key});

  @override
  State<TeacherAccessScreen> createState() => _TeacherAccessScreenState();
}

/// Compatibility name for callers that still import the old screen symbol.
typedef JoinTeacherScreen = TeacherAccessScreen;

class _TeacherAccessScreenState extends State<TeacherAccessScreen> {
  TeacherAccessController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    final links = context.read<JoinLinkService>();
    _controller = TeacherAccessController(
      relationshipRepository: context.read<TeacherRelationshipRepository>(),
      groupRepository: context.read<GroupRepository>(),
      joinCodeResolver: context.read<JoinCodeResolver>(),
      traineeId: userId,
      traineeDisplayName: user.fullName,
      privateImageSavingEnabled: user.sessionEvidenceEnabled == true,
      reconcileEvidenceAvailability: (id) =>
          SessionEvidenceRepository().reconcilePublicEvidenceAvailability(id),
      onJoinCompleted: () {
        links.clearPendingCode();
      },
    );
    final code = links.pendingCode;
    if (code != null) _controller!.prefillCode(code);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ElixScaffoldPage(
      header: PageHeader(title: const _TeacherAccessPageHeader()),
      content: controller == null
          ? const Center(child: ProgressRing())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.practiceMaxContentWidth,
                  ),
                  child: TeacherAccessSection(
                    isActive: true,
                    controller: controller,
                  ),
                ),
              ),
            ),
    );
  }
}

class _TeacherAccessPageHeader extends StatelessWidget {
  const _TeacherAccessPageHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(
              alpha: context.isDarkTheme ? 0.18 : 0.10,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.28),
            ),
          ),
          child: const Icon(
            FluentIcons.people,
            size: 18,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teacher Access',
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Classroom connections',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
