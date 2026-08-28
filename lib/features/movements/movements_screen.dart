import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import 'movements_presentation.dart';
import 'widgets/movement_difficulty_section.dart';
import 'widgets/movements_header.dart';

const _kMovementsContentMaxWidth = 1280.0;

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  final _sessionRepo = SessionRepository();
  Map<String, MovementStats> _movementStats = const {};
  SessionService? _sessionService;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<SessionService>();
    if (service != _sessionService) {
      _sessionService?.removeListener(_loadStats);
      _sessionService = service..addListener(_loadStats);
    }
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final user = context.read<AuthService>().currentUser;
    if (user?.id == null) return;
    final sessions = await _sessionRepo.getSessionsForUser(user!.id!);
    if (!mounted) return;
    setState(() => _movementStats = _computeStats(sessions));
  }

  /// Aggregates per movement, averaging only Assessment V2 rubric totals.
  Map<String, MovementStats> _computeStats(List<Session> sessions) {
    final counts = <String, int>{};
    final rubricCounts = <String, int>{};
    final rubricSums = <String, int>{};

    for (final s in sessions) {
      counts[s.movementName] = (counts[s.movementName] ?? 0) + 1;
      if (!s.isRubricAssessed) continue;
      rubricCounts[s.movementName] = (rubricCounts[s.movementName] ?? 0) + 1;
      rubricSums[s.movementName] =
          (rubricSums[s.movementName] ?? 0) + s.rubricTotal!;
    }

    return {
      for (final entry in counts.entries)
        entry.key: (
          count: entry.value,
          rubricSessionCount: rubricCounts[entry.key] ?? 0,
          averageRubricTotal: (rubricCounts[entry.key] ?? 0) == 0
              ? null
              : rubricSums[entry.key]! / rubricCounts[entry.key]!,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final summary = computeMovementsSummary(_movementStats);

    return ElixScaffoldPage(
      // The page content owns its spacing. Removing ScaffoldPage's default
      // 24px top inset lets the ambient gradient reach the title bar instead
      // of exposing a strip of the black scaffold background.
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 680
                ? AppSpacing.md
                : AppSpacing.xl;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.pageTopInset,
                horizontalPadding,
                AppSpacing.xxl,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kMovementsContentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MovementsHeader(summary: summary),
                      const SizedBox(height: AppSpacing.xl),
                      MovementDifficultySection(
                        difficulty: 'Easy',
                        movements: movementsByDifficulty('Easy'),
                        stats: _movementStats,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      MovementDifficultySection(
                        difficulty: 'Medium',
                        movements: movementsByDifficulty('Medium'),
                        stats: _movementStats,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      MovementDifficultySection(
                        difficulty: 'Hard',
                        movements: movementsByDifficulty('Hard'),
                        stats: _movementStats,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
