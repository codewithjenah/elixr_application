import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
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
    PublicProfileRepository? publicProfileRepository;
    try {
      assignmentRepository = context.read<ClassroomAssignmentRepository>();
    } on ProviderNotFoundException {
      assignmentRepository = null;
    }
    try {
      publicProfileRepository = context.read<PublicProfileRepository>();
    } on ProviderNotFoundException {
      publicProfileRepository = null;
    }
    _controller = TeacherAccessController(
      groupRepository: context.read<GroupRepository>(),
      joinCodeResolver: context.read<JoinCodeResolver>(),
      traineeId: userId,
      traineeDisplayName: user.fullName,
      onJoinCompleted: () {
        links.clearPendingCode();
      },
      assignmentRepository: assignmentRepository,
      publicProfileRepository: publicProfileRepository,
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
      padding: EdgeInsets.zero,
      content: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 680
              ? AppSpacing.md
              : AppSpacing.xl;
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.pageTopInset,
                horizontalPadding,
                AppSpacing.xl,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.practiceMaxContentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ClassroomPageHeader(),
                      const SizedBox(height: AppSpacing.lg),
                      if (controller == null)
                        const ElixStatusPanel(
                          isLoading: true,
                          icon: FluentIcons.people,
                          title: 'Loading classroom',
                          message: 'Preparing your classrooms.',
                        )
                      else
                        TeacherAccessSection(
                          isActive: true,
                          controller: controller,
                          onOpenClass: (groupId) => context.push(
                            AppRoutePaths.teacherAccessClass(groupId),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClassroomPageHeader extends StatelessWidget {
  const _ClassroomPageHeader();

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return ElixEditorialHeader(
      heading: 'Classrooms',
      eyebrow: 'CLASSROOM',
      subtitle:
          'Join with a teacher code, then open a class to see classwork '
          'and assignments.',
      variant: ElixEditorialHeaderVariant.compact,
      headingMaxLines: 1,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: highContrast
              ? context.elixCardSurface
              : AppColors.primary.withValues(
                  alpha: context.isDarkTheme ? 0.16 : 0.10,
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highContrast
                ? context.elixBorder
                : AppColors.primary.withValues(alpha: 0.28),
            width: highContrast ? 2 : 1,
          ),
        ),
        child: Icon(
          FluentIcons.people,
          size: 18,
          color: highContrast ? context.elixTextPrimary : AppColors.primarySoft,
        ),
      ),
    );
  }
}
