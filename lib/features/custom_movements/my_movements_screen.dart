import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_colors.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_toast.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/custom_movement_reference_image.dart';
import '../../data/models/custom_movement.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../services/auth_service.dart';
import 'custom_movement_authoring_screen.dart';

class MyMovementsScreen extends StatelessWidget {
  const MyMovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    return ElixScaffoldPage(
      header: PageHeader(
        leading: ElixBackButton(
          key: const ValueKey('my-movements-back'),
          label: 'Movements',
          tooltip: 'Back to Movements',
          semanticLabel: 'Back to Movements',
          onPressed: () => context.go(AppRoutePaths.movements),
        ),
        title: const Text('My Movements'),
        commandBar: FilledButton(
          key: const ValueKey('my-movements-create'),
          onPressed: user == null
              ? null
              : () => _createTraineeMovement(context, user),
          child: const Text('Create Movement'),
        ),
      ),
      content: const MyMovementsLibrary(),
    );
  }
}

/// The trainee-owned custom movement library shared by the legacy deep-link
/// screen and the main Movements destination.
class MyMovementsLibrary extends StatelessWidget {
  const MyMovementsLibrary({super.key, this.embedded = false});

  /// Embedded libraries participate in the parent page's scroll view instead
  /// of creating a competing nested scroll area.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final uid = user?.id;
    final repository = context.read<CustomMovementRepository>();
    final library = uid == null
        ? const Center(child: Text('Sign in to view your movements.'))
        : StreamBuilder<List<CustomMovement>>(
            stream: repository.watchOwnedMovements(ownerUid: uid),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Could not load your movements. Try again.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: ProgressRing());
              }
              final movements = snapshot.data!
                  .where(
                    (movement) =>
                        movement.isActive &&
                        movement.isOwnedBy(uid) &&
                        movement.ownerRole == CustomMovementOwnerRole.trainee,
                  )
                  .toList(growable: false);
              if (movements.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.more_sports, size: 42),
                      const SizedBox(height: 12),
                      const Text('Create your first movement'),
                      const SizedBox(height: 6),
                      const Text(
                        'Record the movement at least twice, then practice with feedback from your own examples.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: user == null
                            ? null
                            : () => _createTraineeMovement(context, user),
                        child: const Text('Create Movement'),
                      ),
                    ],
                  ),
                );
              }
              return StreamBuilder<List<CustomMovementResult>>(
                stream: repository.watchPersonalResults(ownerUid: uid),
                builder: (context, resultsSnapshot) {
                  final results = resultsSnapshot.data ?? const [];
                  final resultsByMovement =
                      <String, List<CustomMovementResult>>{};
                  for (final result in results) {
                    resultsByMovement
                        .putIfAbsent(result.movementId, () => [])
                        .add(result);
                  }
                  return GridView.builder(
                    shrinkWrap: embedded,
                    physics: embedded
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    padding: embedded
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(AppSpacing.lg),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 380,
                          mainAxisExtent: 250,
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisSpacing: AppSpacing.md,
                        ),
                    itemCount: movements.length,
                    itemBuilder: (context, index) {
                      final movement = movements[index];
                      final movementResults =
                          resultsByMovement[movement.id] ?? const [];
                      final bestScore = movementResults.isEmpty
                          ? null
                          : movementResults
                                .map((result) => result.totalScore)
                                .reduce((a, b) => a > b ? a : b);
                      return _MovementCard(
                        movement: movement,
                        ownerUid: uid,
                        repository: repository,
                        practiceCount: resultsSnapshot.hasData
                            ? movementResults.length
                            : null,
                        progressUnavailable: resultsSnapshot.hasError,
                        bestScorePercent: bestScore,
                      );
                    },
                  );
                },
              );
            },
          );

    if (!embedded) return library;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmbeddedLibraryHeader(user: user),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 240),
          child: library,
        ),
      ],
    );
  }
}

class _EmbeddedLibraryHeader extends StatelessWidget {
  const _EmbeddedLibraryHeader({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Movements',
              style: FluentTheme.of(context).typography.title,
            ),
            const SizedBox(height: 4),
            const Text(
              'Create and practice automatic movements from your own reference demonstrations.',
            ),
          ],
        );
        final create = FilledButton(
          key: const ValueKey('my-movements-create'),
          onPressed: user == null
              ? null
              : () => _createTraineeMovement(context, user!),
          child: const Text('Create Movement'),
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpacing.md),
              create,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            const SizedBox(width: AppSpacing.lg),
            create,
          ],
        );
      },
    );
  }
}

Future<void> _createTraineeMovement(BuildContext context, User user) async {
  final uid = user.id;
  if (uid == null) return;
  await CustomMovementAuthoringScreen.show(
    context,
    ownerUid: uid,
    ownerRole: CustomMovementOwnerRole.trainee,
    repository: context.read<CustomMovementRepository>(),
  );
}

class _MovementCard extends StatefulWidget {
  const _MovementCard({
    required this.movement,
    required this.ownerUid,
    required this.repository,
    required this.practiceCount,
    required this.progressUnavailable,
    required this.bestScorePercent,
  });

  final CustomMovement movement;
  final String ownerUid;
  final CustomMovementRepository repository;
  final int? practiceCount;
  final bool progressUnavailable;
  final double? bestScorePercent;

  @override
  State<_MovementCard> createState() => _MovementCardState();
}

class _MovementCardState extends State<_MovementCard> {
  Future<void> _edit(BuildContext context) async {
    final revision = await widget.repository.getRevision(
      movementId: widget.movement.id,
      revisionId: widget.movement.activeRevisionId,
    );
    if (!context.mounted || revision == null) return;
    await CustomMovementAuthoringScreen.show(
      context,
      ownerUid: widget.ownerUid,
      ownerRole: widget.movement.ownerRole,
      repository: widget.repository,
      existing: widget.movement,
      existingRevision: revision,
    );
  }

  Future<void> _delete() async {
    final deleted = await _DeleteMovementDialog.show(
      context,
      movement: widget.movement,
      ownerUid: widget.ownerUid,
      repository: widget.repository,
    );
    if (!mounted || !deleted) return;
    ElixToast.showSuccess(
      context,
      message: '${widget.movement.name} was deleted from My Movements.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Card(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 76,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(
                    alpha: context.isDarkTheme ? 0.15 : 0.09,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      CustomMovementReferenceImage(
                        movementName: widget.movement.name,
                        prop: widget.movement.propType,
                        size: 62,
                        storagePath: widget.movement.referenceImageStoragePath,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.movement.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'CUSTOM',
                          style: AppTheme.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      children: [
                        _MovementMetadataChip(
                          icon: FluentIcons.speed_high,
                          label: widget.movement.difficulty,
                        ),
                        _MovementMetadataChip(
                          icon: FluentIcons.diet_plan_notebook,
                          label: widget.movement.propType.displayLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          FluentIcons.chart,
                          size: 12,
                          color: context.elixTextSecondary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.progressUnavailable
                                ? 'Progress unavailable'
                                : widget.practiceCount == null
                                ? 'Progress loading'
                                : widget.bestScorePercent == null
                                ? '${widget.practiceCount} ${widget.practiceCount == 1 ? 'practice' : 'practices'}'
                                : '${widget.practiceCount} ${widget.practiceCount == 1 ? 'practice' : 'practices'} · Best ${widget.bestScorePercent!.round()}%',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        widget.movement.description.isEmpty
                            ? 'Personal automatic movement'
                            : widget.movement.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySecondary.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: FilledButton(
                            key: ValueKey(
                              'my-movement-practice-${widget.movement.id}',
                            ),
                            onPressed: () => context.go(
                              AppRoutePaths.movementsMyMovementPractice(
                                widget.movement.id,
                              ),
                            ),
                            child: const Text('Practice'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: Button(
                            key: ValueKey(
                              'my-movement-edit-${widget.movement.id}',
                            ),
                            onPressed: () => _edit(context),
                            child: const Text('Edit'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Delete movement',
                          child: IconButton(
                            key: ValueKey(
                              'my-movement-delete-${widget.movement.id}',
                            ),
                            icon: Icon(
                              FluentIcons.delete,
                              color: colors.textSecondary,
                            ),
                            onPressed: _delete,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementMetadataChip extends StatelessWidget {
  const _MovementMetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: context.elixCardSurface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.elixBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: context.elixTextSecondary),
        const SizedBox(width: 5),
        Text(label, style: AppTheme.caption),
      ],
    ),
  );
}

class _DeleteMovementDialog extends StatefulWidget {
  const _DeleteMovementDialog({
    required this.movement,
    required this.ownerUid,
    required this.repository,
  });

  final CustomMovement movement;
  final String ownerUid;
  final CustomMovementRepository repository;

  static Future<bool> show(
    BuildContext context, {
    required CustomMovement movement,
    required String ownerUid,
    required CustomMovementRepository repository,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteMovementDialog(
        movement: movement,
        ownerUid: ownerUid,
        repository: repository,
      ),
    );
    return result == true;
  }

  @override
  State<_DeleteMovementDialog> createState() => _DeleteMovementDialogState();
}

class _DeleteMovementDialogState extends State<_DeleteMovementDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.repository.deleteOwnedMovement(
        movementId: widget.movement.id,
        ownerUid: widget.ownerUid,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Could not delete this movement. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElixDialog(
      title: 'Delete movement?',
      icon: FluentIcons.delete,
      iconColor: context.elixColors.error,
      headerAccentColor: context.elixColors.error,
      showCloseButton: !_deleting,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete ${widget.movement.name}? This movement will be removed from My Movements. This action cannot be undone.',
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: const Text('Could not delete movement'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
          ],
        ],
      ),
      actions: [
        ElixPrimaryButton(
          key: const ValueKey('my-movement-delete-cancel'),
          label: 'Cancel',
          expanded: false,
          variant: ElixButtonVariant.secondary,
          onPressed: _deleting
              ? null
              : () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        ElixPrimaryButton(
          key: const ValueKey('my-movement-delete-confirm'),
          label: _deleting ? 'Deleting…' : 'Delete',
          expanded: false,
          isLoading: _deleting,
          variant: ElixButtonVariant.destructive,
          onPressed: _deleting ? null : _delete,
        ),
      ],
    );
  }
}
