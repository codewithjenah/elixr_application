import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../features/calendar/utils/calendar_metrics.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import 'history_format.dart';
import 'widgets/history_date_group.dart';
import 'widgets/history_empty_state.dart';
import 'widgets/history_filter_bar.dart';
import 'widgets/history_header.dart';
import 'widgets/history_summary_section.dart';

typedef HistorySessionsLoader = Future<List<Session>> Function(String userId);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.embedded = false,
    this.initialDate,
    this.sessionsLoader,
  });

  /// When true, render session review without a page scaffold or heading.
  final bool embedded;

  /// Optional `YYYY-MM-DD` focus date from `/training?view=history&date=`.
  final String? initialDate;

  /// Test seam for loading sessions without Firebase.
  final HistorySessionsLoader? sessionsLoader;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  SessionRepository? _repo;
  List<Session> _sessions = [];
  List<Session> _filtered = [];
  bool _loading = true;
  String? _difficultyFilter;
  String _searchQuery = '';
  HistorySortMode _sortMode = HistorySortMode.mostRecent;
  DateTime? _dateFilter;
  SessionService? _sessionService;

  bool get _hasActiveFilters =>
      _difficultyFilter != null ||
      _searchQuery.trim().isNotEmpty ||
      _sortMode != HistorySortMode.mostRecent ||
      _dateFilter != null;

  bool get _hasResultFilter =>
      _difficultyFilter != null ||
      _searchQuery.trim().isNotEmpty ||
      _dateFilter != null;

  @override
  void initState() {
    super.initState();
    _dateFilter = parseCalendarQueryDate(widget.initialDate);
    _loadSessions();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate == oldWidget.initialDate) return;
    setState(() {
      _dateFilter = parseCalendarQueryDate(widget.initialDate);
      _applyFiltersAndSort();
    });
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

  void _applyFiltersAndSort() {
    var list = List<Session>.from(_sessions);

    final difficulty = _difficultyFilter;
    if (difficulty != null) {
      list = list.where((s) => s.difficulty == difficulty).toList();
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((s) => s.movementName.toLowerCase().contains(query))
          .toList();
    }

    final dateFilter = _dateFilter;
    if (dateFilter != null) {
      list = list.where((s) => sessionMatchesFocusDate(s, dateFilter)).toList();
    }

    list.sort(_compareSessions);
    _filtered = list;
  }

  int _compareSessions(Session a, Session b) {
    switch (_sortMode) {
      case HistorySortMode.mostRecent:
        return _compareCreatedAt(a, b, ascending: false);
      case HistorySortMode.oldest:
        return _compareCreatedAt(a, b, ascending: true);
      case HistorySortMode.highestScore:
        return _compareResult(a, b, descending: true);
      case HistorySortMode.lowestScore:
        return _compareResult(a, b, descending: false);
      case HistorySortMode.longestSession:
        return b.durationSeconds.compareTo(a.durationSeconds);
    }
  }

  /// Orders mixed assessment scales by normalized percentage while preserving
  /// each session's native persisted score.
  int _compareResult(Session a, Session b, {required bool descending}) {
    final aValue = a.isRubricAssessed
        ? a.rubricTotal! / 12 * 100
        : (a.legacyScore ?? 0).toDouble();
    final bValue = b.isRubricAssessed
        ? b.rubricTotal! / 12 * 100
        : (b.legacyScore ?? 0).toDouble();
    final cmp = aValue.compareTo(bValue);
    return descending ? -cmp : cmp;
  }

  int _compareCreatedAt(Session a, Session b, {required bool ascending}) {
    final aAt = a.createdAt;
    final bAt = b.createdAt;
    if (aAt == null && bAt == null) return 0;
    if (aAt == null) return 1;
    if (bAt == null) return -1;
    final cmp = aAt.compareTo(bAt);
    return ascending ? cmp : -cmp;
  }

  Future<void> _loadSessions() async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;

    setState(() => _loading = true);
    final loader =
        widget.sessionsLoader ??
        (_repo ??= SessionRepository()).getSessionsForUser;
    final sessions = await loader(userId);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _applyFiltersAndSort();
        _loading = false;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _difficultyFilter = null;
      _searchQuery = '';
      _sortMode = HistorySortMode.mostRecent;
      _dateFilter = null;
      _applyFiltersAndSort();
    });
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

  static double? _average(List<int> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static int? _best(List<int> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate();

    // Assessment cohorts are aggregated separately: rubric totals are 0..12 and
    // legacy scores are 0..100.
    final rubricTotals = <int>[
      for (final s in _sessions)
        if (s.isRubricAssessed) s.rubricTotal!,
    ];
    final legacyScores = <int>[
      for (final s in _sessions)
        if (!s.isRubricAssessed && s.legacyScore != null) s.legacyScore!,
    ];

    final totalDurationSeconds = _sessions.fold<int>(
      0,
      (sum, s) => sum + s.durationSeconds,
    );

    final hasSessions = _sessions.isNotEmpty;
    final dateFilterLabel = _dateFilter == null
        ? null
        : DateFormat.yMMMMd().format(_dateFilter!);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            widget.embedded ? 0 : AppSpacing.pageTopInset,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HistoryHeader(
                loading: _loading,
                onRefresh: _loadSessions,
                showTitle: !widget.embedded,
              ),
              if (hasSessions) ...[
                SizedBox(
                  height: widget.embedded ? AppSpacing.sm : AppSpacing.lg,
                ),
                HistorySummarySection(
                  totalSessions: _sessions.length,
                  rubricSessionCount: rubricTotals.length,
                  averageRubricTotal: _average(rubricTotals),
                  bestRubricTotal: _best(rubricTotals),
                  legacySessionCount: legacyScores.length,
                  averageLegacyScore: _average(legacyScores),
                  bestLegacyScore: _best(legacyScores),
                  totalDurationSeconds: totalDurationSeconds,
                  matchingCount: _hasResultFilter ? _filtered.length : null,
                ),
                const SizedBox(height: AppSpacing.md),
                HistoryFilterBar(
                  difficultyFilter: _difficultyFilter,
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  dateFilterLabel: dateFilterLabel,
                  hasActiveFilters: _hasActiveFilters,
                  onDifficultyChanged: (v) {
                    setState(() {
                      _difficultyFilter = v;
                      _applyFiltersAndSort();
                    });
                  },
                  onSearchChanged: (v) {
                    setState(() {
                      _searchQuery = v;
                      _applyFiltersAndSort();
                    });
                  },
                  onSortChanged: (v) {
                    setState(() {
                      _sortMode = v;
                      _applyFiltersAndSort();
                    });
                  },
                  onClearFilters: _clearFilters,
                  onDateFilterCleared: () {
                    setState(() {
                      _dateFilter = null;
                      _applyFiltersAndSort();
                    });
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
        Expanded(
          child: _loading && _sessions.isEmpty
              ? const HistoryLoadingSkeleton(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                )
              : _sessions.isEmpty
              ? const HistoryEmptyState()
              : _filtered.isEmpty
              ? HistoryNoResultsState(onClearFilters: _clearFilters)
              : ListView.builder(
                  key: const Key('history_page_scroll'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final label = groups.keys.elementAt(index);
                    final items = groups[label]!;
                    return HistoryDateGroup(label: label, sessions: items);
                  },
                ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(child: body),
    );
  }
}
