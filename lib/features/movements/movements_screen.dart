import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
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
  const MovementsScreen({super.key, this.sessionRepository, this.userId});

  final SessionRepository? sessionRepository;

  /// Test-only override for the authenticated Trainee's UID. Production reads
  /// the current account from [AuthService].
  final String? userId;

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  late final SessionRepository _sessionRepo =
      widget.sessionRepository ?? SessionRepository();
  Map<String, MovementStats> _movementStats = const {};
  Map<String, MovementStats> _variantStats = const {};
  Set<String> _practicedVariants = const {};
  SessionService? _sessionService;
  int _statsRequestGeneration = 0;

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
    final userId = widget.userId ?? context.read<AuthService>().currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    final requestGeneration = ++_statsRequestGeneration;
    List<Session> sessions;
    try {
      sessions = await _sessionRepo.getSessionsForUser(userId);
    } catch (_) {
      // Remote history is a visual summary only. Offline failure must not
      // prevent the catalog (whose access is local progression/tutorial state)
      // from rendering.
      if (kDebugMode) debugPrint('Movement history load failed for $userId');
      return;
    }
    if (!mounted) return;
    final activeUserId =
        widget.userId ?? context.read<AuthService>().currentUser?.id;
    if (requestGeneration != _statsRequestGeneration ||
        activeUserId != userId) {
      return;
    }
    setState(() {
      _movementStats = aggregateMovementStats(sessions);
      _variantStats = aggregatePracticeVariantStats(sessions);
      _practicedVariants = _variantStats.keys.toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = computeMovementsSummary(
      _movementStats,
      practicedVariants: _practicedVariants,
    );

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
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
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
                          practiceSteps: practiceStepsForDifficulty('Easy'),
                          stats: _variantStats,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        MovementDifficultySection(
                          difficulty: 'Medium',
                          practiceSteps: practiceStepsForDifficulty('Medium'),
                          stats: _variantStats,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        MovementDifficultySection(
                          difficulty: 'Hard',
                          practiceSteps: practiceStepsForDifficulty('Hard'),
                          stats: _variantStats,
                        ),
                      ],
                    ),
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
