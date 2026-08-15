import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import 'history_format.dart';
import 'widgets/history_date_group.dart';
import 'widgets/history_empty_state.dart';
import 'widgets/history_filter_bar.dart';
import 'widgets/history_header.dart';
import 'widgets/history_summary_section.dart';

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
  String _searchQuery = '';
  HistorySortMode _sortMode = HistorySortMode.mostRecent;
  SessionService? _sessionService;

  bool get _hasActiveFilters =>
      _difficultyFilter != null ||
      _searchQuery.trim().isNotEmpty ||
      _sortMode != HistorySortMode.mostRecent;

  bool get _hasResultFilter =>
      _difficultyFilter != null || _searchQuery.trim().isNotEmpty;

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

  /// Orders by assessment result within a cohort.
  ///
  /// Rubric totals (0..12) are never compared against legacy percentages
  /// (0..100), so Assessment V2 sessions form the leading cohort and legacy
  /// sessions are ordered among themselves after them.
  int _compareResult(Session a, Session b, {required bool descending}) {
    final aRubric = a.isRubricAssessed;
    final bRubric = b.isRubricAssessed;
    if (aRubric != bRubric) return aRubric ? -1 : 1;

    final aValue = aRubric ? a.rubricTotal! : (a.legacyScore ?? 0);
    final bValue = bRubric ? b.rubricTotal! : (b.legacyScore ?? 0);
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
    final sessions = await _repo.getSessionsForUser(userId);
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

    return ElixScaffoldPage(
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
              HistoryHeader(loading: _loading, onRefresh: _loadSessions),
              if (hasSessions) ...[
                const SizedBox(height: AppSpacing.lg),
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
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: _loading && _sessions.isEmpty
                    ? const HistoryLoadingSkeleton()
                    : _sessions.isEmpty
                    ? const HistoryEmptyState()
                    : _filtered.isEmpty
                    ? HistoryNoResultsState(onClearFilters: _clearFilters)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final label = groups.keys.elementAt(index);
                          final items = groups[label]!;
                          return HistoryDateGroup(
                            label: label,
                            sessions: items,
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
