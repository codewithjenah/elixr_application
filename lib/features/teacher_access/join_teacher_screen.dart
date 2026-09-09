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
          return Stack(
            children: [
              const Positioned.fill(child: _ClassroomAmbientWash()),
              ScrollConfiguration(
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
                          const SizedBox(height: AppSpacing.md),
                          if (controller == null)
                            const Center(child: ProgressRing())
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
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClassroomAmbientWash extends StatelessWidget {
  const _ClassroomAmbientWash();

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast) return const SizedBox.shrink();
    final isDark = context.isDarkTheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: isDark ? 0.08 : 0.035),
              AppColors.accent.withValues(alpha: isDark ? 0.04 : 0.02),
              Colors.transparent,
            ],
            stops: const [0, 0.28, 0.72],
          ),
        ),
      ),
    );
  }
}

class _ClassroomPageHeader extends StatelessWidget {
  const _ClassroomPageHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArt = constraints.maxWidth >= 720 && !context.isHighContrast;
        return Stack(
          children: [
            if (showArt)
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _ClassroomHeaderArt(),
              ),
            Padding(
              padding: EdgeInsets.only(right: showArt ? 168 : 0),
              child: ElixEditorialHeader(
                heading: 'Classroom',
                eyebrow: 'CLASSROOM',
                subtitle: 'Join a class with the code shared by your teacher.',
                headingMaxLines: 1,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(
                      alpha: context.isDarkTheme ? 0.16 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Icon(
                    FluentIcons.people,
                    size: 18,
                    color: AppColors.primarySoft,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClassroomHeaderArt extends StatelessWidget {
  const _ClassroomHeaderArt();

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: 168,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              Positioned(
                right: 4,
                top: 2,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(
                          alpha: isDark ? 0.20 : 0.12,
                        ),
                        AppColors.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 54,
                bottom: 6,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accent.withValues(
                        alpha: isDark ? 0.32 : 0.22,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                top: 16,
                child: Icon(
                  FluentIcons.education,
                  size: 48,
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.28 : 0.18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
