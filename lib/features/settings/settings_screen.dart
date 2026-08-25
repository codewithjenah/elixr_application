import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../teacher/teacher_privacy_section.dart';
import '../teacher_access/teacher_access_section.dart';
import 'sections/account_profile_section.dart';
import 'sections/appearance_section.dart';
import 'sections/practice_section.dart';
import 'sections/privacy_section.dart';
import 'sections/security_section.dart';
import 'settings_section.dart';
import 'widgets/practice_preferences_controller.dart';
import 'widgets/settings_components.dart';
import 'widgets/settings_legal_footer.dart';

export 'sections/account_profile_section.dart' show SettingsAccountHooks;

/// Modern Settings surface replacing the monolithic profile settings dialog.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialSection = SettingsSection.accountProfile,
    this.audience = SettingsAudience.trainee,
    this.embedded = false,
    this.onClose,
    this.watchPlayer,
    this.watchUserCosmetics,
    this.equipBorder,
    this.pickProfileImage,
    this.cropProfileImage,
    this.publicProfileRepository,
    this.teacherRelationshipRepository,
    this.embeddedFooter,
  });

  final SettingsSection initialSection;

  /// Trainee sees all panes; teacher omits Practice and Teacher Access.
  final SettingsAudience audience;

  /// When true, fill the parent with no dialog card, header, or close button.
  final bool embedded;

  /// Page-hosted close (`/teacher/settings` deep link). Overlay hosts omit
  /// this and pop the dialog instead.
  final VoidCallback? onClose;

  /// Optional override for tests (avoids constructing Firestore).
  /// Stored as a public field so tests can assert injection.
  final Stream<LeaderboardEntry?> Function(String userId)? watchPlayer;

  /// Optional cosmetics stream override forwarded to [AccountProfileSection].
  final AccountProfileWatchCosmetics? watchUserCosmetics;

  /// Optional equip override forwarded to [AccountProfileSection].
  final AccountProfileEquipBorder? equipBorder;

  /// Optional gallery picker override forwarded to [AccountProfileSection].
  final AccountProfileImagePicker? pickProfileImage;

  /// Optional crop-dialog override forwarded to [AccountProfileSection].
  final AccountProfileImageCropper? cropProfileImage;

  /// Optional public profile repository override for [PrivacySection].
  final PublicProfileRepository? publicProfileRepository;

  /// Optional relationship repository override for [TeacherAccessSection].
  final TeacherRelationshipRepository? teacherRelationshipRepository;

  /// Optional rail/page footer (Legal links on the teacher host).
  final Widget? embeddedFooter;

  static T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  static Future<void> show(
    BuildContext context, {
    SettingsSection initialSection = SettingsSection.appearance,
  }) {
    final isTeacher =
        context.read<AuthService>().currentUser?.isTeacher == true;
    final publicProfileRepository = _maybeRead<PublicProfileRepository>(
      context,
    );
    final teacherRelationshipRepository =
        _maybeRead<TeacherRelationshipRepository>(context);
    final accountHooks = _maybeRead<SettingsAccountHooks>(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x99000000),
      builder: (_) => SettingsScreen(
        initialSection: initialSection,
        audience: isTeacher
            ? SettingsAudience.teacher
            : SettingsAudience.trainee,
        publicProfileRepository: publicProfileRepository,
        teacherRelationshipRepository: teacherRelationshipRepository,
        watchPlayer: accountHooks?.watchPlayer,
        watchUserCosmetics: accountHooks?.watchUserCosmetics,
        equipBorder: accountHooks?.equipBorder,
        embeddedFooter: isTeacher ? const SettingsLegalFooter() : null,
      ),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section;
  PracticePreferencesController? _practiceController;
  final _accountKey = GlobalKey<AccountProfileSectionState>();
  final _securityKey = GlobalKey<SecuritySectionState>();
  bool _closing = false;

  List<SettingsSection> get _visibleSections =>
      settingsSectionsFor(widget.audience);

  @override
  void initState() {
    super.initState();
    _section = resolveSettingsSection(
      audience: widget.audience,
      requested: widget.initialSection,
    );
    if (widget.audience == SettingsAudience.trainee) {
      _practiceController = PracticePreferencesController(
        context.read<SettingsService>(),
      );
    }
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.audience != widget.audience) {
      _section = resolveSettingsSection(
        audience: widget.audience,
        requested: widget.initialSection,
      );
    }
  }

  @override
  void dispose() {
    _practiceController?.dispose();
    super.dispose();
  }

  Future<void> _requestClose() async {
    if (widget.embedded) return;
    if (_closing) return;
    _closing = true;
    try {
      final accountDirty = _accountKey.currentState?.isDirty ?? false;
      final practiceDirty = _practiceController?.isDirty ?? false;
      if (accountDirty || practiceDirty) {
        final discard = await SettingsDiscardConfirm.show(
          context,
          message: 'You have unsaved changes. Discard them and close Settings?',
        );
        if (!mounted) return;
        if (!discard) return;
        _accountKey.currentState?.discardChanges();
        _practiceController?.discard();
      }
      _securityKey.currentState?.clearPasswordFields();
      if (!mounted) return;
      final onClose = widget.onClose;
      if (onClose != null) {
        onClose();
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      _closing = false;
    }
  }

  void _openSection(SettingsSection section) {
    if (!_visibleSections.contains(section)) return;
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Prefer finite parent constraints (embedded/page) but fall back to the
    // window size for dialog overlays with loose constraints.
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0 &&
                constraints.maxWidth < double.infinity
            ? constraints.maxWidth
            : screen.width;
        final surfaceWidth = (availableWidth - 32).clamp(
          0.0,
          settingsMaxSurfaceWidth,
        );
        final surfaceHeight = (screen.height - 48).clamp(420.0, 780.0);
        final layoutWidth = widget.embedded
            ? (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : screen.width)
            : surfaceWidth;
        final isWide = layoutWidth >= settingsWideBreakpoint;
        final body = isWide
            ? Row(
                children: [
                  _buildSidebar(),
                  Expanded(child: _buildContent(isWide: true)),
                ],
              )
            : _buildContent(isWide: false);

        if (widget.embedded) {
          final embedWidth =
              constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : layoutWidth;
          final embedHeight =
              constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : surfaceHeight;
          return SizedBox(
            width: embedWidth,
            height: embedHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: body),
                if (!isWide && widget.embeddedFooter != null)
                  widget.embeddedFooter!,
              ],
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _requestClose();
          },
          child: Center(
            child: SizedBox(
              width: surfaceWidth,
              height: surfaceHeight,
              child: _decorateSurface(child: body),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    const sidebarWidth = 220.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: widget.embedded
            ? const Color(0x00000000)
            : context.elixPanelSurface,
        border: Border(
          right: BorderSide(
            color: context.elixBorder.withValues(
              alpha: widget.embedded ? 0.35 : 0.5,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.embedded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(settingsRadiusSm),
                    ),
                    child: const Icon(
                      FluentIcons.settings,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: AppTheme.headingMedium.copyWith(
                            fontSize: 20,
                            color: context.elixTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Manage your Elixr experience',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ] else
            const SizedBox(height: AppSpacing.md),
          for (final section in _visibleSections)
            SettingsNavItem(
              icon: section.icon,
              label: section.title,
              isSelected: _section == section,
              onTap: () => _openSection(section),
            ),
          if (widget.embeddedFooter != null) ...[
            const Spacer(),
            widget.embeddedFooter!,
          ],
        ],
      ),
    );
  }

  Widget _buildCompactNav() {
    return ComboBox<SettingsSection>(
      value: _section,
      isExpanded: true,
      items: [
        for (final section in _visibleSections)
          ComboBoxItem<SettingsSection>(
            value: section,
            child: Row(
              children: [
                Icon(section.icon, size: 14),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(section.title)),
              ],
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) _openSection(value);
      },
    );
  }

  Widget _scrollableSection({required bool isWide, required Widget child}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isWide ? AppSpacing.xl : AppSpacing.lg,
        AppSpacing.lg,
        isWide ? AppSpacing.xl : AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: child,
    );
  }

  Widget _buildContent({required bool isWide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            isWide ? AppSpacing.xl : AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.elixBorder.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isWide) ...[
                      _buildCompactNav(),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    SettingsSectionHeader(
                      title: _section.title,
                      description: _section.description,
                    ),
                  ],
                ),
              ),
              if (!widget.embedded)
                IconButton(
                  icon: const Icon(FluentIcons.cancel, size: 16),
                  onPressed: _requestClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _stackIndex,
            children: [
              for (final section in _visibleSections)
                TickerMode(
                  enabled: _section == section,
                  child: _scrollableSection(
                    isWide: isWide,
                    child: _sectionBody(section),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  int get _stackIndex {
    final index = _visibleSections.indexOf(_section);
    return index < 0 ? 0 : index;
  }

  Widget _decorateSurface({required Widget child}) {
    return Container(
      decoration: AppTheme.cardDecoration(context).copyWith(
        borderRadius: BorderRadius.circular(20),
        boxShadow: widget.embedded
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDarkTheme ? 0.5 : 0.12,
                  ),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _sectionBody(SettingsSection section) {
    switch (section) {
      case SettingsSection.accountProfile:
        return AccountProfileSection(
          key: _accountKey,
          watchPlayer: widget.watchPlayer,
          watchUserCosmetics: widget.watchUserCosmetics,
          equipBorder: widget.equipBorder,
          pickProfileImage: widget.pickProfileImage,
          cropProfileImage: widget.cropProfileImage,
          showAvatarFrames: widget.audience == SettingsAudience.trainee,
        );
      case SettingsSection.security:
        return SecuritySection(key: _securityKey);
      case SettingsSection.appearance:
        return const AppearanceSection();
      case SettingsSection.practice:
        final controller = _practiceController;
        if (controller == null) return const SizedBox.shrink();
        return PracticeSection(controller: controller);
      case SettingsSection.privacy:
        if (widget.audience == SettingsAudience.teacher) {
          return TeacherPrivacySection(
            publicProfileRepository: widget.publicProfileRepository,
          );
        }
        return PrivacySection(
          isActive: _section == SettingsSection.privacy,
          publicProfileRepository: widget.publicProfileRepository,
        );
      case SettingsSection.teacherAccess:
        return TeacherAccessSection(
          isActive: _section == SettingsSection.teacherAccess,
          repository: widget.teacherRelationshipRepository,
        );
    }
  }
}
