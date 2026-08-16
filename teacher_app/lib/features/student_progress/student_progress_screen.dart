import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/teacher_routes.dart';
import '../auth/teacher_auth_controller.dart';
import '../coaching_notes/coaching_notes_controller.dart';
import '../coaching_notes/coaching_notes_section.dart';
import 'student_progress_controller.dart';
import 'student_progress_formatters.dart';
import 'student_progress_session_card.dart';

class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({
    super.key,
    required this.traineeId,
    this.controller,
  });
  final String traineeId;
  final StudentProgressController? controller;

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen>
    with WidgetsBindingObserver {
  StudentProgressController? _owned;
  TeacherCoachingNotesController? _coaching;
  StudentProgressController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null) return;
    _owned ??= StudentProgressController(
      relationships: context.read<TeacherRelationshipRepository>(),
      progress: context.read<TeacherProgressRepository>(),
      teacherId: context.read<TeacherAuthController>().currentUser!.id!,
      traineeId: widget.traineeId,
      ranking: _rankingRepository(context),
    )..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.start();
    } else {
      _controller.pause();
      _coaching?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _owned?.dispose();
    _coaching?.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(TeacherRoutes.roster);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final controller = _controller;
        final title = controller.link?.traineeDisplayName ?? 'Student progress';
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to roster',
              onPressed: _back,
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _body(context, controller),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, StudentProgressController c) {
    if (!c.hasVerifiedApprovedRelationship) {
      _coaching?.pause();
      final retry =
          c.state == StudentProgressState.connectionRequired ||
          c.state == StudentProgressState.error;
      final revoked = c.state == StudentProgressState.relationshipRevoked;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!revoked &&
                  c.state != StudentProgressState.waitingForAccess &&
                  c.state != StudentProgressState.accessWithdrawn)
                const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_message(c.state), textAlign: TextAlign.center),
              if (retry) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: c.retry, child: const Text('Retry')),
              ],
              if (revoked) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _back,
                  child: const Text('Back to roster'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    _coaching ??= TeacherCoachingNotesController(
      repository: context.read<CoachingNoteRepository>(),
      teacherId: context.read<TeacherAuthController>().currentUser!.id!,
      traineeId: widget.traineeId,
    )..start();
    final summary = c.summary;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.link?.traineeDisplayName ?? 'Student',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      foregroundImage: c.identity?.profilePictureUrl == null
                          ? null
                          : NetworkImage(c.identity!.profilePictureUrl!),
                      child: Text(_initials(c.link?.traineeDisplayName ?? '')),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 6,
                        children: [
                          Text(
                            'Roster rank: ${c.identity?.rosterRank == null ? '—' : '#${c.identity!.rosterRank}'}',
                          ),
                          Text(
                            'Global rank: ${c.globalRankUnavailable
                                ? 'Unavailable'
                                : !c.globalRankLoaded
                                ? '…'
                                : c.globalRank == null
                                ? 'Unranked'
                                : '#${c.globalRank}'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Progress Overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (c.state != StudentProgressState.ready &&
                    c.state != StudentProgressState.empty) ...[
                  const SizedBox(height: 8),
                  Text(_message(c.state)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _overview(
                      context,
                      'Practice time',
                      formatPracticeDuration(
                        summary?.totalDurationSeconds ?? 0,
                      ),
                    ),
                    _overview(
                      context,
                      'Completed movements',
                      '${summary?.completedMovementNames.length ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Completed Movements',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final movement
                        in summary?.completedMovementNames ?? const <String>[])
                      Chip(label: Text(movement)),
                  ],
                ),
                const SizedBox(height: 24),
                CoachingNotesSection(controller: _coaching!),
                const SizedBox(height: 24),
                Text(
                  'Recent Practice / Assessments',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (c.sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('No progress yet.'),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList.builder(
            itemCount: c.sessions.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StudentProgressSessionCard(
                session: c.sessions[index],
                traineeId: widget.traineeId,
                evidenceAllowed: c.link?.hasEffectiveEvidenceAccess == true,
                evidenceRepository: _evidenceRepository(context),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: c.paginationError != null
                ? OutlinedButton(
                    onPressed: c.retryLoadMore,
                    child: const Text('Try loading again'),
                  )
                : c.hasMore
                ? OutlinedButton(
                    onPressed: c.loadingMore ? null : c.loadMore,
                    child: Text(c.loadingMore ? 'Loading…' : 'Load more'),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _overview(BuildContext context, String label, String value) =>
      SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ),
      );

  String _message(StudentProgressState state) => switch (state) {
    StudentProgressState.loadingRelationship => 'Checking progress access…',
    StudentProgressState.waitingForAccess =>
      'Waiting for progress access from this Trainee.',
    StudentProgressState.loading => 'Loading progress…',
    StudentProgressState.accessWithdrawn =>
      'This Trainee stopped sharing progress.',
    StudentProgressState.relationshipRevoked =>
      'This relationship is no longer available.',
    StudentProgressState.connectionRequired =>
      'A connection is required to verify progress access.',
    StudentProgressState.error => 'Could not load progress. Please retry.',
    _ => '',
  };

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();

  RosterLeaderboardRepository _rankingRepository(BuildContext context) {
    try {
      return context.read<RosterLeaderboardRepository>();
    } on ProviderNotFoundException {
      return FirebaseRosterLeaderboardRepository();
    }
  }

  TeacherEvidenceRepository _evidenceRepository(BuildContext context) {
    try {
      return context.read<TeacherEvidenceRepository>();
    } on ProviderNotFoundException {
      return FirebaseTeacherEvidenceRepository();
    }
  }
}
