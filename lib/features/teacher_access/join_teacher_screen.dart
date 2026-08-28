import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
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
    ClassroomAssignmentRepository? assignmentRepository;
    try {
      assignmentRepository = context.read<ClassroomAssignmentRepository>();
    } on ProviderNotFoundException {
      assignmentRepository = null;
    }
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
      assignmentRepository: assignmentRepository,
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
      header: const ElixEditorialPageHeader(
        heading: 'Teacher Access',
        eyebrow: 'CLASSROOM',
        subtitle: 'Join a class with the code shared by your teacher.',
        leading: Icon(FluentIcons.people, color: AppColors.primary),
      ),
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
                    onOpenClass: (groupId) =>
                        context.go(AppRoutePaths.teacherAccessClass(groupId)),
                  ),
                ),
              ),
            ),
    );
  }
}
