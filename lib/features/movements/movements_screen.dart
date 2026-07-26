import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../data/models/movement.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

// Neon accent palette shared with the dashboard.
const _purple = AppColors.accent;
const _pink = AppColors.primary;
const _panelColor = AppColors.panelSurface;

const _movementEmojis = <String, String>{
  'Normal Grip': '🍾',
  "Bartender's Grip": '🤏',
  'Reverse Grip': '🖐️',
  'Hand Stall': '✋',
  'Arm Stall': '💪',
  'Elbow Stall': '🦾',
  'Tap': '🥂',
  'Basket': '🧺',
};

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  final _sessionRepo = SessionRepository();
  Map<String, ({int count, double avgScore})> _movementStats = const {};
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
    if (mounted) setState(() => _movementStats = _computeStats(sessions));
  }

  Map<String, ({int count, double avgScore})> _computeStats(
    List<Session> sessions,
  ) {
    final result = <String, ({int count, double avgScore})>{};
    for (final s in sessions) {
      final prev = result[s.movementName];
      if (prev == null) {
        result[s.movementName] = (count: 1, avgScore: s.score.toDouble());
      } else {
        final total = prev.avgScore * prev.count + s.score;
        result[s.movementName] = (
          count: prev.count + 1,
          avgScore: total / (prev.count + 1),
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: AppSpacing.xl),
              _DifficultySection(
                title: 'Easy',
                color: AppColors.success,
                movements: movementsByDifficulty('Easy'),
                stats: _movementStats,
              ),
              const SizedBox(height: AppSpacing.xl),
              _DifficultySection(
                title: 'Medium',
                color: AppColors.warning,
                movements: movementsByDifficulty('Medium'),
                stats: _movementStats,
              ),
              const SizedBox(height: AppSpacing.xl),
              _DifficultySection(
                title: 'Hard',
                color: AppColors.error,
                movements: movementsByDifficulty('Hard'),
                stats: _movementStats,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Movements',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: _pink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Master Easy, Medium, and Hard flair movements.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Difficulty section
// ---------------------------------------------------------------------------

class _DifficultySection extends StatelessWidget {
  const _DifficultySection({
    required this.title,
    required this.color,
    required this.movements,
    required this.stats,
  });

  final String title;
  final Color color;
  final List<Movement> movements;
  final Map<String, ({int count, double avgScore})> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                '${movements.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = AppSpacing.md;
            const minCardWidth = 260.0;
            final columns = (constraints.maxWidth / (minCardWidth + spacing))
                .floor()
                .clamp(1, 3);
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final m in movements)
                  SizedBox(
                    width: cardWidth,
                    child: _MovementCard(
                      movement: m,
                      accentColor: color,
                      sessionCount: stats[m.name]?.count ?? 0,
                      avgScore: stats[m.name]?.avgScore ?? 0,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Movement card
// ---------------------------------------------------------------------------

class _MovementCard extends StatefulWidget {
  const _MovementCard({
    required this.movement,
    required this.accentColor,
    required this.sessionCount,
    required this.avgScore,
  });

  final Movement movement;
  final Color accentColor;
  final int sessionCount;
  final double avgScore;

  @override
  State<_MovementCard> createState() => _MovementCardState();
}

class _MovementCardState extends State<_MovementCard> {
  bool _hovered = false;

  bool get _enabled => widget.movement.enabled;
  bool get _started => widget.sessionCount > 0;

  Future<void> _open() async {
    if (!_enabled) return;
    var prop = 'bottle';
    if (widget.movement.difficulty == 'Medium') {
      final choice = await _showPropPicker(context, widget.movement.name);
      if (choice == null || !mounted) return;
      prop = choice;
    }
    if (!mounted) return;
    final encoded = Uri.encodeComponent(widget.movement.name);
    context.go(
      '/practice?movement=$encoded'
      '&difficulty=${widget.movement.difficulty}'
      '&prop=$prop',
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final hovered = _hovered && _enabled;

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0.0, hovered ? -4.0 : 0.0, 0.0),
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: hovered ? 0.6 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: hovered ? 0.28 : 0.07),
                blurRadius: hovered ? 24 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Opacity(
            opacity: _enabled ? 1.0 : 0.55,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _visualHeader(accent, hovered),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.movement.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _difficultyPill(accent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.movement.description,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.movement.requiresHandsDetection) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          FluentIcons.sprint,
                          size: 11,
                          color: AppColors.primarySoft,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Hands detection required',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primarySoft.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _footer(accent, hovered),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _visualHeader(Color accent, bool hovered) {
    return Container(
      height: 92,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: _started ? 0.28 : 0.14),
            _purple.withValues(alpha: _started ? 0.16 : 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Center(
            child: AnimatedScale(
              scale: hovered ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Opacity(
                opacity: _enabled ? 1 : 0.4,
                child: Text(
                  _movementEmojis[widget.movement.name] ?? '🍾',
                  style: const TextStyle(fontSize: 40),
                ),
              ),
            ),
          ),
          if (_started)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.sessionCount}× played',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _difficultyPill(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        widget.movement.difficulty,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  Widget _footer(Color accent, bool hovered) {
    return Row(
      children: [
        Expanded(
          child: _started
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Best avg ${widget.avgScore.round()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 5,
                        child: Stack(
                          children: [
                            Container(color: AppColors.border),
                            FractionallySizedBox(
                              widthFactor: (widget.avgScore / 100).clamp(
                                0.0,
                                1.0,
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [_pink, _purple],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Text(
                  'Tap to start practicing',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_pink, _purple]),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _pink.withValues(alpha: hovered ? 0.6 : 0.3),
                blurRadius: hovered ? 16 : 8,
              ),
            ],
          ),
          child: const Icon(
            FluentIcons.play_solid,
            size: 14,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Prop picker (bottle vs cocktail shaker) for Medium movements
// ---------------------------------------------------------------------------

Future<String?> _showPropPicker(BuildContext context, String movementName) {
  return showDialog<String>(
    context: context,
    builder: (context) => ContentDialog(
      style: const ContentDialogThemeData(
        decoration: BoxDecoration(
          color: _panelColor,
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      title: Text(
        movementName,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose the prop you want to practice with.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PropOption(
                  emoji: '🍾',
                  label: 'Bottle',
                  onTap: () => Navigator.of(context).pop('bottle'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PropOption(
                  emoji: '🍸',
                  label: 'Cocktail Shaker',
                  onTap: () => Navigator.of(context).pop('shaker'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _PropOption extends StatefulWidget {
  const _PropOption({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PropOption> createState() => _PropOptionState();
}

class _PropOptionState extends State<_PropOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            color: _pink.withValues(alpha: _hovered ? 0.14 : 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pink.withValues(alpha: _hovered ? 0.6 : 0.25),
            ),
            boxShadow: [
              if (_hovered)
                BoxShadow(color: _pink.withValues(alpha: 0.25), blurRadius: 16),
            ],
          ),
          child: Column(
            children: [
              AnimatedScale(
                scale: _hovered ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Text(widget.emoji, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
