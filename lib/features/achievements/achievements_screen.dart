import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/achievement.dart';
import '../../data/models/achievement_claim.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/profile_border.dart';
import '../../data/models/session.dart';
import '../../data/models/user_cosmetics.dart';
import '../../data/repositories/achievement_repository.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import 'widgets/achievement_card.dart';
import 'widgets/profile_border_picker.dart';

enum _AchievementFilter { all, claimable, inProgress, claimed, locked }

const _kMaxContentWidth = 1120.0;
const _kAchievementCardExtent = 168.0;
const _kAchievementMaxCrossExtent = 380.0;

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

  StreamSubscription<LeaderboardEntry?>? _leaderboardSub;
  StreamSubscription<Set<String>>? _claimsSub;
  StreamSubscription<UserCosmetics?>? _cosmeticsSub;

  String? _userId;
  List<Session> _sessions = const [];
  LeaderboardEntry? _leaderboardEntry;
  Set<String> _claimedIds = const {};
  UserCosmetics? _cosmetics;
  bool _loadingSessions = true;
  bool _leaderboardMissing = false;
  String? _actionError;
  String? _claimingId;
  String? _equippingId;
  bool _unequipping = false;
  _AchievementFilter _filter = _AchievementFilter.all;

  @override
  void initState() {
    super.initState();
    _achievementRepo = widget._achievementRepository ?? AchievementRepository();
    _leaderboardRepo = widget._leaderboardRepository ?? LeaderboardRepository();
    _sessionRepo = widget._sessionRepository ?? SessionRepository();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _cosmeticsSub?.cancel();
    super.dispose();
  }

  void _bindStreams(String? userId) {
    _leaderboardSub?.cancel();
    _claimsSub?.cancel();
    _cosmeticsSub?.cancel();
    _leaderboardSub = null;
    _claimsSub = null;
    _cosmeticsSub = null;

    if (userId == null) {
      setState(() {
        _leaderboardEntry = null;
        _claimedIds = const {};
        _cosmetics = null;
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
    _cosmeticsSub = _achievementRepo.watchUserCosmetics(userId).listen((
      cosmetics,
    ) {
      if (!mounted) return;
      setState(() => _cosmetics = cosmetics);
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
    return switch (_filter) {
      _AchievementFilter.all => views,
      _AchievementFilter.claimable =>
        views.where((v) => v.state == AchievementState.claimable).toList(),
      _AchievementFilter.inProgress =>
        views.where((v) => v.state == AchievementState.inProgress).toList(),
      _AchievementFilter.claimed =>
        views.where((v) => v.state == AchievementState.claimed).toList(),
      _AchievementFilter.locked =>
        views.where((v) => v.state == AchievementState.locked).toList(),
    };
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

  Future<void> _equip(String borderId) async {
    final userId = _userId;
    if (userId == null || _equippingId != null || _unequipping) return;
    setState(() {
      _equippingId = borderId;
      _actionError = null;
    });
    try {
      final result = await _achievementRepo.equipBorder(
        userId: userId,
        borderId: borderId,
      );
      if (!mounted) return;
      setState(() {
        _actionError = switch (result.status) {
          EquipBorderStatus.equipped ||
          EquipBorderStatus.alreadyEquipped => null,
          EquipBorderStatus.invalidBorder => 'Unknown border.',
          EquipBorderStatus.borderLocked => 'Unlock this border first.',
          EquipBorderStatus.cosmeticsMissing =>
            'Claim an achievement to unlock cosmetics.',
          EquipBorderStatus.leaderboardMissing =>
            'Complete a session to create your leaderboard profile first.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Equip failed. Please retry.');
    } finally {
      if (mounted) setState(() => _equippingId = null);
    }
  }

  Future<void> _unequip() async {
    final userId = _userId;
    if (userId == null || _unequipping || _equippingId != null) return;
    setState(() {
      _unequipping = true;
      _actionError = null;
    });
    try {
      final result = await _achievementRepo.equipBorder(
        userId: userId,
        borderId: '',
      );
      if (!mounted) return;
      if (result.status == EquipBorderStatus.leaderboardMissing) {
        setState(
          () => _actionError =
              'Complete a session to create your leaderboard profile first.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Unequip failed. Please retry.');
    } finally {
      if (mounted) setState(() => _unequipping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final views = _views;
    final claimedCount = views
        .where((v) => v.state == AchievementState.claimed)
        .length;
    final unlockedBorders = _cosmetics?.unlockedBorderIds.toSet() ?? {};
    final initials = _initials(user?.fullName ?? 'User');
    final filterCounts = _filterCounts;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          'Achievements',
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
      ),
      content: _loadingSessions
          ? const Center(child: ProgressRing())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _HeaderSummary(
                      claimedCount: claimedCount,
                      totalCount: achievementCatalog.length,
                      unlockedBorderCount: unlockedBorders.length,
                      totalBorders: profileBorderCatalog.length,
                      overallProgress: _overallProgress,
                      initials: initials,
                      networkImageUrl: user?.profilePictureUrl,
                      legacyLocalPath: user?.profilePicturePath,
                      equippedBorderId: _leaderboardEntry?.equippedBorderId,
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
                        onClose: () => setState(() => _actionError = null),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _SectionHeader(
                      icon: FluentIcons.trophy2,
                      title: 'Achievements',
                      accent: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final filter in _AchievementFilter.values)
                          _FilterChip(
                            label: _filterLabel(filter, filterCounts[filter]!),
                            selected: _filter == filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Builder(
                      builder: (context) {
                        final filtered = _filteredViews;
                        if (filtered.isEmpty) {
                          return _EmptyFilterState(filter: _filter);
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: _kAchievementMaxCrossExtent,
                                mainAxisExtent: _kAchievementCardExtent,
                                mainAxisSpacing: AppSpacing.sm,
                                crossAxisSpacing: AppSpacing.sm,
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
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Profile Borders',
                            style: AppTheme.headingMedium.copyWith(
                              color: context.elixTextPrimary,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        UnequipBorderButton(
                          enabled: (_leaderboardEntry?.equippedBorderId ?? '')
                              .isNotEmpty,
                          busy: _unequipping,
                          onPressed: _unequip,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Achievements unlock cosmetic borders only — no XP.',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ProfileBorderPicker(
                      unlockedBorderIds: unlockedBorders,
                      equippedBorderId: _leaderboardEntry?.equippedBorderId,
                      busyBorderId: _equippingId,
                      onEquip: _equip,
                      onUnequip: _unequip,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  static String _filterLabel(_AchievementFilter filter, int count) {
    final name = switch (filter) {
      _AchievementFilter.all => 'All',
      _AchievementFilter.claimable => 'Claimable',
      _AchievementFilter.inProgress => 'In Progress',
      _AchievementFilter.claimed => 'Claimed',
      _AchievementFilter.locked => 'Locked',
    };
    return '$name $count';
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final active = widget.selected || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.12)
                : _hovered
                ? context.elixBorder.withValues(alpha: 0.35)
                : context.elixCardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : active
                  ? context.elixBorder
                  : context.elixBorder.withValues(alpha: 0.65),
            ),
          ),
          child: Text(
            widget.label,
            style: AppTheme.caption.copyWith(
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600,
              color: widget.selected
                  ? AppColors.primary
                  : context.elixTextSecondary,
            ),
          ),
        ),
      ),
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
                      color: AppColors.primary,
                    ),
                    _StatBlock(
                      label: 'Borders',
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
                    'No leaderboard profile yet — complete a session to equip borders publicly.',
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
                  color: context.elixTextPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
