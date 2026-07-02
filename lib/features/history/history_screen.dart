import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSessions();
    context.read<SessionService>().addListener(_onSessionSaved);
  }

  @override
  void dispose() {
    context.read<SessionService>().removeListener(_onSessionSaved);
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

    return ScaffoldPage(
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('History', style: AppTheme.headingLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Your past training sessions',
                          style: AppTheme.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: _loading ? null : _loadSessions,
                  ),
                ],
              ),
              if (!_loading && _sessions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    _SummaryPill(
                      label: 'Sessions',
                      value: '${_filtered.length}',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _SummaryPill(
                      label: 'Avg Score',
                      value: avgScore.toStringAsFixed(0),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _FilterChips(
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
              Expanded(
                child: _loading
                    ? const Center(child: ProgressRing())
                    : _sessions.isEmpty
                        ? const _EmptyState()
                        : _filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No sessions match this filter.',
                                  style: AppTheme.bodySecondary,
                                ),
                              )
                            : ListView.builder(
                                itemCount: groups.length,
                                itemBuilder: (context, index) {
                                  final label = groups.keys.elementAt(index);
                                  final items = groups[label]!;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpacing.sm,
                                        ),
                                        child: Text(
                                          label,
                                          style: AppTheme.headingMedium
                                              .copyWith(fontSize: 15),
                                        ),
                                      ),
                                      ...items.map(
                                        (s) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: AppSpacing.sm,
                                          ),
                                          child: _SessionTile(session: s),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                    ],
                                  );
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

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppTheme.headingMedium.copyWith(
              color: AppColors.primary,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _options = ['All', 'Easy', 'Medium', 'Hard'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: _options.map((opt) {
        final isAll = opt == 'All';
        final isSelected = isAll
            ? selected == null
            : selected == opt;
        return GestureDetector(
          onTap: () => onSelected(isAll ? null : opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : context.elixBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : context.elixBorder,
              ),
            ),
            child: Text(
              opt,
              style: AppTheme.body.copyWith(
                fontSize: 13,
                color: isSelected ? AppColors.primary : null,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElixCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.history,
                size: 40,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
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
            ElixPrimaryButton(
              label: 'Browse Movements',
              expanded: false,
              onPressed: () => context.go('/movements'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatefulWidget {
  const _SessionTile({required this.session});

  final Session session;

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  final _repo = SessionRepository();
  String? _summary;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (widget.session.id == null) return;
    final feedbacks =
        await _repo.getFeedbacksForSession(widget.session.id!);
    if (!mounted) return;
    setState(() {
      if (feedbacks.isEmpty) {
        _summary = 'No feedback recorded';
      } else {
        _summary = feedbacks.take(3).map((f) => f.message).join(' · ');
      }
    });
  }

  Color _difficultyColor(String d) {
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

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.session.createdAt != null
        ? DateFormat.jm().format(
              DateTime.parse(widget.session.createdAt!).toLocal(),
            )
        : '';
    final diffColor = _difficultyColor(widget.session.difficulty);
    final scoreClr = _scoreColor(widget.session.score);

    return ElixCard(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scoreClr.withValues(alpha: 0.12),
                  border: Border.all(color: scoreClr.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${widget.session.score}',
                  style: AppTheme.headingMedium.copyWith(
                    color: scoreClr,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.movementName,
                      style: AppTheme.headingMedium.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        _DifficultyBadge(
                          label: widget.session.difficulty,
                          color: diffColor,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '$date · ${widget.session.durationSeconds}s',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                _expanded
                    ? FluentIcons.chevron_up
                    : FluentIcons.chevron_down,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
          if (_expanded && _summary != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.elixBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_summary!, style: AppTheme.bodySecondary),
            ),
          ],
        ],
      ),
    );
  }
}

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
