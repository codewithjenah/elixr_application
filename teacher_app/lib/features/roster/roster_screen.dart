import 'package:elixr_core/repositories/firebase_teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/teacher_theme.dart';
import '../../core/widgets/teacher_auth_widgets.dart';
import '../auth/teacher_auth_controller.dart';
import 'add_student_sheet.dart';
import 'roster_controller.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key, this.repository, this.controller});

  final TeacherRelationshipRepository? repository;
  final RosterController? controller;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  RosterController? _owned;
  bool _started = false;

  RosterController? get _controller => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null || _owned != null) {
      _startIfNeeded();
      return;
    }
    final user = context.read<TeacherAuthController>().currentUser;
    final userId = user?.id;
    if (userId == null) return;
    TeacherRelationshipRepository repository;
    if (widget.repository != null) {
      repository = widget.repository!;
    } else {
      try {
        repository = context.read<TeacherRelationshipRepository>();
      } on ProviderNotFoundException {
        repository = FirebaseTeacherRelationshipRepository();
      }
    }
    _owned = RosterController(
      repository: repository,
      teacherId: userId,
      teacherDisplayName: user!.fullName,
    );
    _owned!.addListener(_onTick);
    _startIfNeeded();
  }

  void _startIfNeeded() {
    if (_started) return;
    final controller = _controller;
    if (controller == null) return;
    _started = true;
    controller.start();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onTick);
    _owned?.removeListener(_onTick);
    _owned?.dispose();
    super.dispose();
  }

  Future<void> _openAddStudent() async {
    final controller = _controller;
    if (controller == null) return;
    controller.resetAddStudent();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TeacherColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: AddStudentSheet(controller: controller),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();
    final user = auth.currentUser;
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller == null || controller.loading
                ? null
                : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('roster_add_student'),
        onPressed: _openAddStudent,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add student'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TeacherBrandMark(),
              const SizedBox(height: 20),
              if (user != null) ...[
                Text(
                  user.fullName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TeacherColors.textSecondary,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('roster_logout'),
                    onPressed: auth.isBusy ? null : auth.signOut,
                    child: const Text('Logout'),
                  ),
                ),
              ],
              Text(
                'Students appear here only after they approve your request. '
                'Practice sessions and scores are not shared in this version.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TeacherColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (controller?.errorMessage != null)
                TeacherMessageBanner(message: controller!.errorMessage!),
              Expanded(child: _RosterBody(controller: controller)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterBody extends StatelessWidget {
  const _RosterBody({required this.controller});

  final RosterController? controller;

  @override
  Widget build(BuildContext context) {
    final roster = controller;
    if (roster == null || roster.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (roster.pending.isEmpty && roster.approved.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 48,
                color: TeacherColors.primarySoft.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 16),
              Text(
                'No students linked yet',
                key: const Key('roster_empty'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask a Trainee for their coach code, then tap Add student.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TeacherColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (roster.pending.isNotEmpty) ...[
          Text(
            'Pending requests',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final link in roster.pending)
            Card(
              color: TeacherColors.surfaceHigh,
              child: ListTile(
                title: Text(link.traineeDisplayName),
                subtitle: const Text('Waiting for Trainee approval'),
                trailing: TextButton(
                  key: Key('roster_cancel_${link.id}'),
                  onPressed: roster.busy
                      ? null
                      : () => roster.cancelPending(link),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
        Text(
          'Approved students',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (roster.approved.isEmpty)
          Text(
            'No approved students yet.',
            key: const Key('roster_approved_empty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: TeacherColors.textSecondary,
            ),
          )
        else
          for (final link in roster.approved)
            Card(
              color: TeacherColors.surfaceHigh,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.traineeDisplayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Linked. Progress review will be available in the next phase.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TeacherColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
