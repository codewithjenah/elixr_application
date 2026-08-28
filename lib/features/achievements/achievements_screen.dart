import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/achievement.dart';
import '../../data/models/achievement_claim.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/profile_border.dart';
import '../../data/models/session.dart';
import '../../data/repositories/achievement_repository.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import 'widgets/achievement_card.dart';

enum _AchievementFilter { all, claimable, inProgress, claimed, locked }

const _kMaxContentWidth = 1400.0;
const _kAchievementToolbarBreakpoint = 660.0;
const _kAchievementFilterDropdownHeight = 42.0;
const _kAchievementFilterDropdownWidth = 280.0;
const _kAchievementMinCardWidth = 420.0;
const _kAchievementGridGap = 16.0;
const _kAchievementCardExtent = 216.0;

String _achievementFilterDisplayLabel(_AchievementFilter filter) {
  return switch (filter) {
    _AchievementFilter.all => 'All achievements',
    _AchievementFilter.claimable => 'Claimable',
    _AchievementFilter.inProgress => 'In progress',
    _AchievementFilter.claimed => 'Claimed',
    _AchievementFilter.locked => 'Locked',
  };
}

IconData _achievementFilterIcon(_AchievementFilter filter) {
  return switch (filter) {
    _AchievementFilter.all => FluentIcons.view_all,
    _AchievementFilter.claimable => FluentIcons.giftbox_open,
    _AchievementFilter.inProgress => FluentIcons.processing_run,
    _AchievementFilter.claimed => FluentIcons.completed_solid,
    _AchievementFilter.locked => FluentIcons.lock_solid,
  };
}

int _achievementFilterCount(
  _AchievementFilter filter,
  Map<_AchievementFilter, int> counts,
) {
  return counts[filter] ?? 0;
}

int _achievementColumnCount(double availableWidth) {
  if (availableWidth <= 0) return 1;
  const minCard = _kAchievementMinCardWidth;
  const gap = _kAchievementGridGap;
  var columns = ((availableWidth + gap) / (minCard + gap)).floor().clamp(1, 3);
  // Reject borderline 3-column layouts where cards would fall under min width
  // after gaps (padding/constraints can make the raw floor optimistic).
  while (columns > 1) {
    final cardWidth = (availableWidth - gap * (columns - 1)) / columns;
    if (cardWidth >= minCard - 0.5) break;
    columns -= 1;
  }
  return columns;
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    super.key,
    AchievementRepository? achievementRepository,
    LeaderboardRepository? leaderboardRepository,
    SessionRepository? sessionRepository,
  }) : _achievementRepository = achievementRepository,
       _leaderboardRepository = leaderboardRepository,
       _sessionRepository = sessionRepository;

  final AchievementRepository? _achievementRepository;
  final LeaderboardRepository? _leaderboardRepository;
  final SessionRepository? _sessionRepository;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final AchievementRepository _achievementRepo;
  late final LeaderboardRepository _leaderboardRepo;
  late final SessionRepository _sessionRepo;
  bool _reposInitialized = false;

  StreamSubscription<LeaderboardEntry?>? _leaderboardSub;
  StreamSubscription<Set<String>>? _claimsSub;

  String? _userId;
  List<Session> _sessions = const [];
  LeaderboardEntry? _leaderboardEntry;
  Set<String> _claimedIds = const {};
  bool _loadingSessions = true;
  bool _leaderboardMissing = false;
  String? _actionError;
  String? _claimingId;
  _AchievementFilter _filter = _AchievementFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_reposInitialized) {
      _reposInitialized = true;
      final publicProfileRepository = context.read<PublicProfileRepository>();
      _achievementRepo =
          widget._achievementRepository ??
          AchievementRepository(
            publicProfileRepository: publicProfileRepository,
          );
      _leaderboardRepo =
          widget._leaderboardRepository ?? LeaderboardRepository();
      _sessionRepo = widget._sessionRepository ?? SessionRepository();
    }
    final userId = context.watch<AuthService>().currentUser?.id;
    if (userId != _userId) {
      _userId = userId;
      _bindStreams(userId);
      unawaited(_loadSessions(userId));
    }
  }

  @override
  void dispose() {
    _leaderboardSub?.cancel();
    _claimsSub?.cancel();
    super.dispose();
  }

  void _bindStreams(String? userId) {
    _leaderboardSub?.cancel();
    _claimsSub?.cancel();
    _leaderboardSub = null;
    _claimsSub = null;

    if (userId == null) {
      setState(() {
        _leaderboardEntry = null;
        _claimedIds = const {};
        _leaderboardMissing = true;
        _sessions = const [];
        _loadingSessions = false;
      });
      return;
    }

    _leaderboardSub = _leaderboardRepo.watchPlayer(userId).listen((entry) {
      if (!mounted) return;
      setState(() {
        _leaderboardEntry = entry;
        _leaderboardMissing = entry == null;
      });
    });
    _claimsSub = _achievementRepo.watchClaimedAchievementIds(userId).listen((
      ids,
    ) {
      if (!mounted) return;
      setState(() => _claimedIds = ids);
    });
  }

  Future<void> _loadSessions(String? userId) async {
    if (userId == null) return;
    setState(() {
      _loadingSessions = true;
      _actionError = null;
    });
    try {
      final sessions = await _sessionRepo.getSessionsForUser(userId);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loadingSessions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSessions = false;
        _actionError = 'Could not load session history. Tap retry.';
      });
    }
  }

  List<AchievementViewData> get _views {
    return buildAllAchievementViewData(
      sessions: _sessions,
      leaderboardEntry: _leaderboardEntry,
      claimedAchievementIds: _claimedIds,
    );
  }

  int get _unlockedBorderCount {
    var count = 0;
    for (final id in _claimedIds) {
      if (rewardBorderForAchievement(id) != null) count++;
    }
    return count;
  }

  Map<_AchievementFilter, int> get _filterCounts {
    final views = _views;
    return {
      _AchievementFilter.all: views.length,
      _AchievementFilter.claimable: views
          .where((v) => v.state == AchievementState.claimable)
          .length,
      _AchievementFilter.inProgress: views
          .where((v) => v.state == AchievementState.inProgress)
          .length,
      _AchievementFilter.claimed: views
          .where((v) => v.state == AchievementState.claimed)
          .length,
      _AchievementFilter.locked: views
          .where((v) => v.state == AchievementState.locked)
          .length,
    };
  }

  List<AchievementViewData> get _filteredViews {
    final views = _views;
    final filtered = switch (_filter) {
      _AchievementFilter.all => List<AchievementViewData>.of(views),
      _AchievementFilter.claimable =>
        views.where((v) => v.state == AchievementState.claimable).toList(),
      _AchievementFilter.inProgress =>
        views.where((v) => v.state == AchievementState.inProgress).toList(),
      _AchievementFilter.claimed =>
        views.where((v) => v.state == AchievementState.claimed).toList(),
      _AchievementFilter.locked =>
        views.where((v) => v.state == AchievementState.locked).toList(),
    };
    filtered.sort(
      (a, b) => compareAchievementsByProgression(a.definition, b.definition),
    );
    return filtered;
  }

  double get _overallProgress {
    if (achievementCatalog.isEmpty) return 0;
    final claimed = _views
        .where((v) => v.state == AchievementState.claimed)
        .length;
    return claimed / achievementCatalog.length;
  }

  Future<void> _claim(String achievementId) async {
    final userId = _userId;
    if (userId == null || _claimingId != null) return;
    setState(() {
      _claimingId = achievementId;
      _actionError = null;
    });
    try {
      final result = await _achievementRepo.claimAchievement(
        userId: userId,
        achievementId: achievementId,
        sessions: _sessions,
        leaderboardEntry: _leaderboardEntry,
      );
      if (!mounted) return;
      if (result.status == AchievementClaimStatus.notCompleted) {
        setState(() => _actionError = 'Achievement is not complete yet.');
      } else if (result.status == AchievementClaimStatus.invalidAchievement) {
        setState(() => _actionError = 'Unknown achievement.');
      } else if (result.status == AchievementClaimStatus.cosmeticsCorrupt) {
        setState(() => _actionError = 'Cosmetics data looks corrupt.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Claim failed. Please retry.');
    } finally {
      if (mounted) setState(() => _claimingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final views = _views;
    final claimedCount = views
        .where((v) => v.state == AchievementState.claimed)
        .length;
    final initials = userInitials(user?.fullName ?? 'User');
    final filterCounts = _filterCounts;

    return ElixScaffoldPage(
      header: ElixEditorialPageHeader(
        heading: 'Achievements',
        eyebrow: 'MILESTONES',
        subtitle: 'Track your training milestones and earned rewards.',
        leading: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(
              alpha: context.isDarkTheme ? 0.18 : 0.10,
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.26),
            ),
          ),
          child: const Icon(
            FluentIcons.trophy2,
            size: 18,
            color: AppColors.primary,
          ),
        ),
      ),
      content: _loadingSessions
          ? const Center(child: ProgressRing())
          : ListView(
              key: const Key('achievements_page_scroll'),
              padding: EdgeInsets.zero,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kMaxContentWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeaderSummary(
                            claimedCount: claimedCount,
                            totalCount: achievementCatalog.length,
                            unlockedBorderCount: _unlockedBorderCount,
                            totalBorders: profileBorderCatalog.length,
                            overallProgress: _overallProgress,
                            initials: initials,
                            networkImageUrl: user?.profilePictureUrl,
                            legacyLocalPath: user?.profilePicturePath,
                            equippedBorderId:
                                _leaderboardEntry?.equippedBorderId,
                            leaderboardMissing: _leaderboardMissing,
                          ),
                          if (_actionError != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            InfoBar(
                              title: const Text('Something went wrong'),
                              content: Text(_actionError!),
                              severity: InfoBarSeverity.error,
                              isLong: true,
                              action: Button(
                                onPressed: () {
                                  unawaited(_loadSessions(_userId));
                                  setState(() => _actionError = null);
                                },
                                child: const Text('Retry'),
                              ),
                              onClose: () =>
                                  setState(() => _actionError = null),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          _AchievementsSectionToolbar(
                            filter: _filter,
                            filterCounts: filterCounts,
                            onFilterChanged: (filter) =>
                                setState(() => _filter = filter),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final filtered = _filteredViews;
                              if (filtered.isEmpty) {
                                return _EmptyFilterState(filter: _filter);
                              }
                              final columns = _achievementColumnCount(
                                constraints.maxWidth,
                              );
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent: _kAchievementCardExtent,
                                      mainAxisSpacing: _kAchievementGridGap,
                                      crossAxisSpacing: _kAchievementGridGap,
                                    ),
                                itemBuilder: (context, index) {
                                  final view = filtered[index];
                                  return AchievementCard(
                                    view: view,
                                    claiming: _claimingId == view.definition.id,
                                    onClaim: () => _claim(view.definition.id),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AchievementsSectionToolbar extends StatelessWidget {
  const _AchievementsSectionToolbar({
    required this.filter,
    required this.filterCounts,
    required this.onFilterChanged,
  });

  final _AchievementFilter filter;
  final Map<_AchievementFilter, int> filterCounts;
  final ValueChanged<_AchievementFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kAchievementToolbarBreakpoint;
        final titleGroup = const _AchievementsToolbarTitleGroup();
        final dropdown = _AchievementFilterDropdown(
          filter: filter,
          filterCounts: filterCounts,
          onFilterChanged: onFilterChanged,
          isExpanded: !isWide,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleGroup),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: _kAchievementFilterDropdownWidth,
                child: dropdown,
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleGroup,
            const SizedBox(height: AppSpacing.sm),
            dropdown,
          ],
        );
      },
    );
  }
}

class _AchievementsToolbarTitleGroup extends StatelessWidget {
  const _AchievementsToolbarTitleGroup();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(
              alpha: context.isDarkTheme ? 0.16 : 0.10,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            FluentIcons.trophy2,
            size: 15,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Achievements',
                style: AppTheme.headingMedium.copyWith(
                  color: context.elixTextPrimary,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Progression · Easy → Advanced',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Track your progress and equip claimed profile frames in Settings.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AchievementFilterDropdown extends StatelessWidget {
  const _AchievementFilterDropdown({
    required this.filter,
    required this.filterCounts,
    required this.onFilterChanged,
    required this.isExpanded,
  });

  final _AchievementFilter filter;
  final Map<_AchievementFilter, int> filterCounts;
  final ValueChanged<_AchievementFilter> onFilterChanged;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final option in _AchievementFilter.values)
        ComboBoxItem<_AchievementFilter>(
          value: option,
          child: _AchievementFilterOptionRow(
            icon: _achievementFilterIcon(option),
            label: _achievementFilterDisplayLabel(option),
            count: _achievementFilterCount(option, filterCounts),
          ),
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.75)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: _kAchievementFilterDropdownHeight,
          child: ComboBox<_AchievementFilter>(
            value: filter,
            isExpanded: true,
            items: items,
            icon: Icon(
              FluentIcons.chevron_down,
              size: 10,
              color: context.elixTextSecondary,
            ),
            selectedItemBuilder: (context) {
              return [
                for (final option in _AchievementFilter.values)
                  _AchievementFilterOptionRow(
                    icon: _achievementFilterIcon(option),
                    label: _achievementFilterDisplayLabel(option),
                    count: _achievementFilterCount(option, filterCounts),
                  ),
              ];
            },
            onChanged: (value) {
              if (value != null) onFilterChanged(value);
            },
          ),
        ),
      ),
    );
  }
}

class _AchievementFilterOptionRow extends StatelessWidget {
  const _AchievementFilterOptionRow({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 13, color: context.elixTextSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodySecondary.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(minWidth: 22),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: context.elixBorder.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: AppTheme.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: context.elixTextSecondary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.filter});

  final _AchievementFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      _AchievementFilter.all => 'No achievements available.',
      _AchievementFilter.claimable =>
        'No claimable achievements right now. Keep practicing!',
      _AchievementFilter.inProgress =>
        'No achievements in progress. Start a session to begin.',
      _AchievementFilter.claimed =>
        'No claimed achievements yet. Complete and claim your first one.',
      _AchievementFilter.locked => 'No locked achievements in this view.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.filter,
            size: 28,
            color: context.elixTextSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({
    required this.claimedCount,
    required this.totalCount,
    required this.unlockedBorderCount,
    required this.totalBorders,
    required this.overallProgress,
    required this.initials,
    required this.networkImageUrl,
    required this.legacyLocalPath,
    required this.equippedBorderId,
    required this.leaderboardMissing,
  });

  final int claimedCount;
  final int totalCount;
  final int unlockedBorderCount;
  final int totalBorders;
  final double overallProgress;
  final String initials;
  final String? networkImageUrl;
  final String? legacyLocalPath;
  final String? equippedBorderId;
  final bool leaderboardMissing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatarWidget(
                networkImageUrl: networkImageUrl,
                legacyLocalPath: legacyLocalPath,
                initials: initials,
                radius: 32,
                equippedBorderId: equippedBorderId,
                animateBorder: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _StatBlock(
                      label: 'Claimed',
                      value: '$claimedCount / $totalCount',
                      icon: FluentIcons.trophy2,
                      color: context.elixColors.milestone,
                    ),
                    _StatBlock(
                      label: 'Frames',
                      value: '$unlockedBorderCount / $totalBorders',
                      icon: FluentIcons.contact,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Overall progress',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(
                          color: context.elixBorder.withValues(alpha: 0.45),
                        ),
                        FractionallySizedBox(
                          widthFactor: overallProgress.clamp(0.0, 1.0),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary, AppColors.accent],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(overallProgress * 100).round()}%',
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
              ),
            ],
          ),
          if (leaderboardMissing) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FluentIcons.warning, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No leaderboard profile yet — complete a session to show '
                    'your equipped frame publicly.',
                    style: AppTheme.caption.copyWith(
                      color: AppColors.warning,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkTheme ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTheme.caption.copyWith(
                  fontSize: 10,
                  color: context.elixTextSecondary,
                ),
              ),
              Text(
                value,
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
