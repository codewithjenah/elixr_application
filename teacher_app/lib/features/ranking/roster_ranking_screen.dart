import 'package:elixr_core/repositories/roster_leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/teacher_routes.dart';
import '../auth/teacher_auth_controller.dart';
import 'roster_ranking_controller.dart';

class RosterRankingScreen extends StatefulWidget {
  const RosterRankingScreen({super.key, this.controller});
  final RosterRankingController? controller;

  @override
  State<RosterRankingScreen> createState() => _RosterRankingScreenState();
}

class _RosterRankingScreenState extends State<RosterRankingScreen> {
  RosterRankingController? _owned;
  RosterRankingController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    widget.controller?.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null || _owned != null) return;
    _owned = RosterRankingController(
      repository: context.read<RosterLeaderboardRepository>(),
      teacherId: context.read<TeacherAuthController>().currentUser!.id!,
    )..load();
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Roster ranking'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _controller.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: switch (_controller.state) {
          RosterRankingState.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          RosterRankingState.empty => const Center(
            child: Text('No approved students to rank yet.'),
          ),
          RosterRankingState.error => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load roster ranking.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _controller.load,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          RosterRankingState.ready => RefreshIndicator(
            onRefresh: _controller.load,
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _controller.entries.length,
              itemBuilder: (context, index) {
                final entry = _controller.entries[index];
                return Card(
                  child: ListTile(
                    key: Key('roster_rank_${entry.userId}'),
                    onTap: () =>
                        context.push(TeacherRoutes.student(entry.userId)),
                    leading: CircleAvatar(
                      foregroundImage: entry.profilePictureUrl == null
                          ? null
                          : NetworkImage(entry.profilePictureUrl!),
                      child: Text(_initials(entry.displayName)),
                    ),
                    title: Text('#${entry.rosterRank}  ${entry.displayName}'),
                    subtitle: Text(
                      '${entry.totalXp} lifetime XP · '
                      '${entry.sessionsCompleted} sessions',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
          ),
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).where((part) => part.isNotEmpty).map((part) {
      return part.characters.first.toUpperCase();
    }).join();
  }
}
