import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

// Neon accent palette shared with the dashboard.
const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _amber = AppColors.warning;
const _panelColor = AppColors.panelSurface;
const _panelSoft = Color(0xFF1B1626);

const _movementEmojis = <String, String>{
  'Normal Grip': '🍾',
  "Bartender's Grip": '🤏',
  'Reverse Grip': '🖐️',
  'Hand Stall': '✋',
  'Arm Stall': '💪',
  'Elbow Stall': '🦾',
  'Upper Forearm Stall': '🆙',
  'Shoulder Stall': '🧍',
  'Hand-to-Hand Bottle Exchange': '🔄',
  // Legacy Hard movements kept only for historical session display.
  'Tap': '🥂',
  'Basket': '🧺',
};

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repo = SessionRepository();
  List<Session> _sessions = [];
  List<Session> _filtered = [];
  bool _loading = true;
  String? _difficultyFilter;
  SessionService? _sessionService;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<SessionService>();
    if (service != _sessionService) {
      _sessionService?.removeListener(_onSessionSaved);
      _sessionService = service..addListener(_onSessionSaved);
    }
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_onSessionSaved);
    super.dispose();
  }

  void _onSessionSaved() => _loadSessions();

  void _applyFilter() {
    if (_difficultyFilter == null) {
      _filtered = List.from(_sessions);
    } else {
      _filtered = _sessions
          .where((s) => s.difficulty == _difficultyFilter)
          .toList();
    }
  }

  Future<void> _loadSessions() async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;

    setState(() => _loading = true);
    final sessions = await _repo.getSessionsForUser(userId);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _applyFilter();
        _loading = false;
      });
    }
  }

  Map<String, List<Session>> _groupByDate() {
    final groups = <String, List<Session>>{};
    for (final session in _filtered) {
      final label = _dateLabel(session.createdAt);
      groups.putIfAbsent(label, () => []).add(session);
    }
    return groups;
  }

  String _dateLabel(String? createdAt) {
    if (createdAt == null) return 'Unknown';
    final date = DateTime.parse(createdAt).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(date.year, date.month, date.day);
    if (sessionDay == today) return 'Today';
    if (sessionDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return DateFormat.yMMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate();
    final totalScore = _filtered.fold<int>(0, (sum, s) => sum + s.score);
    final avgScore = _filtered.isEmpty ? 0 : totalScore / _filtered.length;
    final bestScore = _filtered.isEmpty
        ? 0
        : _filtered.map((s) => s.score).reduce((a, b) => a > b ? a : b);
    final totalMinutes =
        _filtered.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/ 60;

    final hasSessions = !_loading && _sessions.isNotEmpty;

    return ScaffoldPage(
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _purple.withValues(alpha: 0.3),
                          _pink.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _purple.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      FluentIcons.history,
                      size: 20,
                      color: _violet,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'History',
                          style: AppTheme.headingLarge.copyWith(color: _pink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your past training sessions',
                          style: AppTheme.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  _RefreshButton(loading: _loading, onPressed: _loadSessions),
                ],
              ),

              // ── Summary + Filters ────────────────────────────────────────
              if (hasSessions) ...[
                const SizedBox(height: AppSpacing.lg),
                _SummaryBar(
                  sessions: _filtered.length,
                  avgScore: avgScore.round(),
                  bestScore: bestScore,
                  minutes: totalMinutes,
                ),
                const SizedBox(height: AppSpacing.md),
                _SegmentedFilter(
                  selected: _difficultyFilter,
                  onSelected: (v) {
                    setState(() {
                      _difficultyFilter = v;
                      _applyFilter();
                    });
                  },
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // ── Content ──────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: ProgressRing())
                    : _sessions.isEmpty
                    ? const _EmptyState()
                    : _filtered.isEmpty
                    ? const _NoMatchState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final label = groups.keys.elementAt(index);
                          final items = groups[label]!;
                          return _SessionGroup(label: label, sessions: items);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary bar ──────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.sessions,
    required this.avgScore,
    required this.bestScore,
    required this.minutes,
  });

  final int sessions;
  final int avgScore;
  final int bestScore;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_panelSoft, _panelColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _SummaryStat(
            icon: FluentIcons.history,
            value: '$sessions',
            label: 'Sessions',
            color: _violet,
          ),
          _divider(),
          _SummaryStat(
            icon: FluentIcons.chart_template,
            value: '$avgScore',
            label: 'Avg Score',
            color: _pink,
          ),
          _divider(),
          _SummaryStat(
            icon: FluentIcons.trophy2_solid,
            value: '$bestScore',
            label: 'Best',
            color: _amber,
          ),
          _divider(),
          _SummaryStat(
            icon: FluentIcons.clock,
            value: '${minutes}m',
            label: 'Trained',
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 34,
    color: AppColors.border,
    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
  );
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Segmented filter control ─────────────────────────────────────────────────

class _SegmentedFilter extends StatelessWidget {
  const _SegmentedFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _options = ['All', 'Easy', 'Medium', 'Hard'];

  static Color _color(String opt) {
    switch (opt) {
      case 'Easy':
        return AppColors.success;
      case 'Medium':
        return AppColors.warning;
      case 'Hard':
        return AppColors.error;
      default:
        return _purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: _options.map((opt) {
          final isAll = opt == 'All';
          final isSelected = isAll ? selected == null : selected == opt;
          final color = _color(opt);
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(isAll ? null : opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.9),
                            color.withValues(alpha: 0.6),
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF120A18)
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Refresh button ─────────────────────────────────────────────────────────────

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _purple.withValues(alpha: _hovered ? 0.55 : 0.25),
            ),
          ),
          child: AnimatedRotation(
            turns: widget.loading ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: Icon(
              FluentIcons.refresh,
              size: 16,
              color: widget.loading ? AppColors.textSecondary : _violet,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Session group (date header + card grid) ────────────────────────────────────

class _SessionGroup extends StatelessWidget {
  const _SessionGroup({required this.label, required this.sessions});

  final String label;
  final List<Session> sessions;

  static Color _difficultyColor(String d) {
    switch (d) {
      case 'Easy':
        return AppColors.success;
      case 'Medium':
        return AppColors.warning;
      case 'Hard':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_pink, _purple],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  letterSpacing: 0.3,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _purple.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${sessions.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _violet,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _purple.withValues(alpha: 0.3),
                        AppColors.border.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Card grid — 2 columns on wide screens, 1 on narrow
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 720;
            if (!twoColumns) {
              return Column(
                children: [
                  for (final s in sessions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _SessionCard(
                        session: s,
                        accent: _difficultyColor(s.difficulty),
                      ),
                    ),
                ],
              );
            }
            final rows = <Widget>[];
            for (var i = 0; i < sessions.length; i += 2) {
              rows.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SessionCard(
                          session: sessions[i],
                          accent: _difficultyColor(sessions[i].difficulty),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: i + 1 < sessions.length
                            ? _SessionCard(
                                session: sessions[i + 1],
                                accent: _difficultyColor(
                                  sessions[i + 1].difficulty,
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(children: rows);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

// ── Session card ───────────────────────────────────────────────────────────────

class _SessionCard extends StatefulWidget {
  const _SessionCard({required this.session, required this.accent});

  final Session session;
  final Color accent;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  final _repo = SessionRepository();
  String? _summary;
  bool _expanded = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (widget.session.id == null) return;
    final feedbacks = await _repo.getFeedbacksForSession(widget.session.id!);
    if (!mounted) return;
    setState(() {
      if (feedbacks.isEmpty) {
        _summary = 'No feedback recorded';
      } else {
        _summary = feedbacks.take(3).map((f) => f.message).join(' · ');
      }
    });
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final date = s.createdAt != null
        ? DateFormat.jm().format(DateTime.parse(s.createdAt!).toLocal())
        : '';
    final scoreClr = _scoreColor(s.score);
    final emoji = _movementEmojis[s.movementName] ?? '🍾';
    final active = _expanded || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_panelSoft, _panelColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? widget.accent.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: active ? 0.2 : 0.05),
                blurRadius: active ? 26 : 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Accent stripe on the left edge
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.accent,
                          widget.accent.withValues(alpha: 0.25),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Emoji avatar
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  _purple.withValues(alpha: 0.32),
                                  _pink.withValues(alpha: 0.12),
                                ],
                              ),
                              border: Border.all(
                                color: _purple.withValues(alpha: 0.3),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 27),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.movementName,
                                  style: AppTheme.headingMedium.copyWith(
                                    fontSize: 17,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _DifficultyBadge(
                                      label: s.difficulty,
                                      color: widget.accent,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Icon(
                                      FluentIcons.clock,
                                      size: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '$date · ${s.durationSeconds}s',
                                        style: AppTheme.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          // Score ring
                          SizedBox(
                            width: 58,
                            height: 58,
                            child: CustomPaint(
                              painter: _ScoreRingPainter(
                                progress: s.score / 100,
                                color: scoreClr,
                              ),
                              child: Center(
                                child: Text(
                                  '${s.score}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: scoreClr,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              FluentIcons.chevron_down,
                              color: active
                                  ? widget.accent
                                  : AppColors.textSecondary,
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Score progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 5,
                          child: Stack(
                            children: [
                              Container(color: AppColors.border),
                              FractionallySizedBox(
                                widthFactor: (s.score / 100).clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        scoreClr,
                                        scoreClr.withValues(alpha: 0.55),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildExpandedSummary(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedSummary() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: (_expanded && _summary != null)
          ? Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(FluentIcons.comment, size: 13, color: _violet),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _summary!,
                        style: AppTheme.bodySecondary.copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

// ── Score ring painter ───────────────────────────────────────────────────────

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;
    const stroke = 4.0;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    canvas.drawCircle(center, radius, bg);

    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Difficulty badge ───────────────────────────────────────────────────────────

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Empty / no-match states ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_panelSoft, _panelColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _purple.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _purple.withValues(alpha: 0.25),
                    _pink.withValues(alpha: 0.12),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(FluentIcons.history, size: 40, color: _violet),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No sessions yet', style: AppTheme.headingMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Complete a practice session to see your history here.',
              style: AppTheme.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            _HeroButton(
              label: 'Browse Movements',
              icon: FluentIcons.grid_view_medium,
              onPressed: () => context.go('/movements'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.filter,
            size: 32,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('No sessions match this filter.', style: AppTheme.bodySecondary),
        ],
      ),
    );
  }
}

// ── Gradient action button ───────────────────────────────────────────────────

class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: _hovered
                  ? const [AppColors.primarySoft, _violet]
                  : const [_pink, _purple],
            ),
            boxShadow: [
              BoxShadow(
                color: _pink.withValues(alpha: _hovered ? 0.5 : 0.35),
                blurRadius: _hovered ? 22 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
