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
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _HeaderSummary(
                  claimedCount: claimedCount,
                  totalCount: achievementCatalog.length,
                  unlockedBorderCount: unlockedBorders.length,
                  totalBorders: profileBorderCatalog.length,
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
                Text(
                  'Achievements',
                  style: AppTheme.headingMedium.copyWith(
                    color: context.elixTextPrimary,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final filter in _AchievementFilter.values)
                      ToggleButton(
                        checked: _filter == filter,
                        onChanged: (_) => setState(() => _filter = filter),
                        child: Text(_filterLabel(filter)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final filtered = _filteredViews;
                    if (filtered.isEmpty) {
                      return Text(
                        'No achievements in this filter.',
                        style: AppTheme.bodySecondary.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      );
                    }
                    if (!wide) {
                      return Column(
                        children: [
                          for (final view in filtered) ...[
                            AchievementCard(
                              view: view,
                              claiming: _claimingId == view.definition.id,
                              onClaim: () => _claim(view.definition.id),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.sm,
                            crossAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 1.35,
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
    );
  }

  static String _filterLabel(_AchievementFilter filter) {
    return switch (filter) {
      _AchievementFilter.all => 'All',
      _AchievementFilter.claimable => 'Claimable',
      _AchievementFilter.inProgress => 'In Progress',
      _AchievementFilter.claimed => 'Claimed',
      _AchievementFilter.locked => 'Locked',
    };
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({
    required this.claimedCount,
    required this.totalCount,
    required this.unlockedBorderCount,
    required this.totalBorders,
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          ProfileAvatarWidget(
            networkImageUrl: networkImageUrl,
            legacyLocalPath: legacyLocalPath,
            initials: initials,
            radius: 36,
            equippedBorderId: equippedBorderId,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Claimed $claimedCount / $totalCount',
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unlocked borders $unlockedBorderCount / $totalBorders',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                if (leaderboardMissing) ...[
                  const SizedBox(height: 6),
                  Text(
                    'No leaderboard profile yet — complete a session to equip borders publicly.',
                    style: AppTheme.caption.copyWith(color: AppColors.warning),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
