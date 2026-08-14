import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/teacher_auth_controller.dart';
import 'student_progress_controller.dart';

class StudentProgressScreen extends StatefulWidget { const StudentProgressScreen({super.key, required this.traineeId}); final String traineeId; @override State<StudentProgressScreen> createState() => _StudentProgressScreenState(); }
class _StudentProgressScreenState extends State<StudentProgressScreen> with WidgetsBindingObserver {
  StudentProgressController? _controller;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override void didChangeDependencies() { super.didChangeDependencies(); _controller ??= StudentProgressController(relationships: context.read<TeacherRelationshipRepository>(), progress: context.read<TeacherProgressRepository>(), teacherId: context.read<TeacherAuthController>().currentUser!.id!, traineeId: widget.traineeId)..start(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
    } else {
      _controller?.start();
    }
  }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _controller?.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _controller!, builder: (context, _) { final c = _controller!; final status = c.state; if (status != StudentProgressState.ready && status != StudentProgressState.empty) return Scaffold(appBar: AppBar(), body: Center(child: Text(_message(status)))); final summary = c.summary; return Scaffold(appBar: AppBar(title: Text(c.link?.traineeDisplayName ?? 'Student')), body: ListView(padding: const EdgeInsets.all(24), children: [Text('Progress access on', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 16), Text('Total practice time: ${summary?.totalDurationSeconds ?? 0} seconds'), Text('Completed movements: ${summary?.completedMovementNames.length ?? 0}'), Wrap(spacing: 8, children: [for (final movement in summary?.completedMovementNames ?? const <String>[]) Chip(label: Text(movement))]), const SizedBox(height: 24), Text('Recent Practice / Assessments', style: Theme.of(context).textTheme.titleLarge), if (c.sessions.isEmpty) const Padding(padding: EdgeInsets.only(top: 16), child: Text('No progress yet.')), for (final session in c.sessions) ListTile(title: Text(session.movementName), subtitle: Text('${session.difficulty} · ${session.durationSeconds}s · ${session.isRubricAssessed ? '${session.rubric!.total}/12 ${session.rubric!.performanceLevel.label}' : 'Legacy assessment: ${session.legacyScore}%'}')), if (c.hasMore) OutlinedButton(onPressed: c.loadingMore ? null : c.loadMore, child: const Text('Load more'))])); });
  String _message(StudentProgressState state) => switch (state) { StudentProgressState.loadingRelationship => 'Checking progress access…', StudentProgressState.waitingForAccess => 'Waiting for progress access from this Trainee.', StudentProgressState.loading => 'Loading progress…', StudentProgressState.withdrawn => 'Progress access was withdrawn.', StudentProgressState.connectionRequired => 'A connection is required to verify progress access.', StudentProgressState.error => 'Could not load progress. Please retry.', _ => '' };
}
