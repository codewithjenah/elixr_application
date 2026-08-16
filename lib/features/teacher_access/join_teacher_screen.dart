import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/session_evidence_repository.dart';
import '../../services/auth_service.dart';
import '../../services/join_link_service.dart';
import 'teacher_access_controller.dart';
import 'teacher_access_section.dart';

class JoinTeacherScreen extends StatefulWidget {
  const JoinTeacherScreen({super.key});

  @override
  State<JoinTeacherScreen> createState() => _JoinTeacherScreenState();
}

class _JoinTeacherScreenState extends State<JoinTeacherScreen> {
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
      repository: context.read<TeacherRelationshipRepository>(),
      traineeId: userId,
      traineeDisplayName: user.fullName,
      privateImageSavingEnabled: user.sessionEvidenceEnabled == true,
      reconcileEvidenceAvailability: (id) =>
          SessionEvidenceRepository().reconcilePublicEvidenceAvailability(id),
      onJoinCompleted: () {
        links.clearPendingCode();
        if (mounted) context.go('/dashboard');
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
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Join a Teacher'),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () {
            context.read<JoinLinkService>().clearPendingCode();
            context.go('/dashboard');
          },
        ),
      ),
      content: controller == null
          ? const Center(child: ProgressRing())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: TeacherAccessSection(
                isActive: true,
                controller: controller,
              ),
            ),
    );
  }
}
