import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../services/settings_service.dart';
import 'sections/account_profile_section.dart';
import 'sections/appearance_section.dart';
import 'sections/practice_section.dart';
import 'sections/security_section.dart';
import 'settings_section.dart';
import 'widgets/practice_preferences_controller.dart';
import 'widgets/settings_components.dart';

/// Modern Settings surface replacing the monolithic profile settings dialog.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialSection = SettingsSection.accountProfile,
    this.watchPlayer,
    this.pickProfileImage,
    this.cropProfileImage,
  });

  final SettingsSection initialSection;

  /// Optional override for tests (avoids constructing Firestore).
  /// Stored as a public field so tests can assert injection.
  final Stream<LeaderboardEntry?> Function(String userId)? watchPlayer;

  /// Optional gallery picker override forwarded to [AccountProfileSection].
  final AccountProfileImagePicker? pickProfileImage;

  /// Optional crop-dialog override forwarded to [AccountProfileSection].
  final AccountProfileImageCropper? cropProfileImage;

  static Future<void> show(
    BuildContext context, {
    SettingsSection initialSection = SettingsSection.appearance,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x99000000),
      builder: (_) => SettingsScreen(initialSection: initialSection),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section;
  late final PracticePreferencesController _practiceController;
  final _accountKey = GlobalKey<AccountProfileSectionState>();
  final _securityKey = GlobalKey<SecuritySectionState>();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _practiceController = PracticePreferencesController(
      context.read<SettingsService>(),
    );
  }

  @override
  void dispose() {
    _practiceController.dispose();
    super.dispose();
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    try {
      final accountDirty = _accountKey.currentState?.isDirty ?? false;
      final practiceDirty = _practiceController.isDirty;
      if (accountDirty || practiceDirty) {
        final discard = await SettingsDiscardConfirm.show(
          context,
          message: 'You have unsaved changes. Discard them and close Settings?',
        );
        if (!mounted) return;
        if (!discard) return;
        _accountKey.currentState?.discardChanges();
        _practiceController.discard();
      }
      _securityKey.currentState?.clearPasswordFields();
      if (mounted) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  void _openSection(SettingsSection section) {
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
        final isWide = surfaceWidth >= settingsWideBreakpoint;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _requestClose();
          },
          child: Center(
            child: Container(
              width: surfaceWidth,
              height: surfaceHeight,
              decoration: AppTheme.cardDecoration(context).copyWith(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
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
              child: isWide
                  ? Row(
                      children: [
                        _buildSidebar(),
                        Expanded(child: _buildContent(isWide: true)),
                      ],
                    )
                  : _buildContent(isWide: false),
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
        color: context.elixBackground,
        border: Border(
          right: BorderSide(color: context.elixBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          for (final section in SettingsSection.values)
            SettingsNavItem(
              icon: section.icon,
              label: section.title,
              isSelected: _section == section,
              onTap: () => _openSection(section),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactNav() {
    return ComboBox<SettingsSection>(
      value: _section,
      isExpanded: true,
      items: [
        for (final section in SettingsSection.values)
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
              IconButton(
                icon: const Icon(FluentIcons.cancel, size: 16),
                onPressed: _requestClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section.index,
            children: [
              TickerMode(
                enabled: _section == SettingsSection.accountProfile,
                child: _scrollableSection(
                  isWide: isWide,
                  child: AccountProfileSection(
                    key: _accountKey,
                    watchPlayer: widget.watchPlayer,
                    pickProfileImage: widget.pickProfileImage,
                    cropProfileImage: widget.cropProfileImage,
                  ),
                ),
              ),
              TickerMode(
                enabled: _section == SettingsSection.security,
                child: _scrollableSection(
                  isWide: isWide,
                  child: SecuritySection(key: _securityKey),
                ),
              ),
              TickerMode(
                enabled: _section == SettingsSection.appearance,
                child: _scrollableSection(
                  isWide: isWide,
                  child: const AppearanceSection(),
                ),
              ),
              TickerMode(
                enabled: _section == SettingsSection.practice,
                child: _scrollableSection(
                  isWide: isWide,
                  child: PracticeSection(controller: _practiceController),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
