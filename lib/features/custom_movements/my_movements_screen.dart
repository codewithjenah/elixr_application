import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/custom_movement.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../services/auth_service.dart';
import 'custom_movement_builder_dialog.dart';

class MyMovementsScreen extends StatelessWidget {
  const MyMovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    return ElixScaffoldPage(
      header: PageHeader(
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
                        'Record three references, then practice against your own template.',
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
              return GridView.builder(
                shrinkWrap: embedded,
                physics: embedded
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                padding: embedded
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(AppSpacing.lg),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 380,
                  mainAxisExtent: 235,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                ),
                itemCount: movements.length,
                itemBuilder: (context, index) => _MovementCard(
                  movement: movements[index],
                  ownerUid: uid,
                  repository: repository,
                ),
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
  await CustomMovementBuilderDialog.show(
    context,
    ownerUid: uid,
    ownerRole: CustomMovementOwnerRole.trainee,
    repository: context.read<CustomMovementRepository>(),
  );
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.movement,
    required this.ownerUid,
    required this.repository,
  });

  final CustomMovement movement;
  final String ownerUid;
  final CustomMovementRepository repository;

  Future<void> _edit(BuildContext context) async {
    final revision = await repository.getRevision(
      movementId: movement.id,
      revisionId: movement.activeRevisionId,
    );
    if (!context.mounted || revision == null) return;
    await CustomMovementBuilderDialog.show(
      context,
      ownerUid: ownerUid,
      ownerRole: movement.ownerRole,
      repository: repository,
      existing: movement,
      existingRevision: revision,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              movement.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 6),
            Text('${movement.difficulty} · ${movement.propType.displayLabel}'),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                movement.description.isEmpty
                    ? 'Personal automatic movement'
                    : movement.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: ValueKey('my-movement-practice-${movement.id}'),
                    onPressed: () => context.go(
                      AppRoutePaths.myMovementPractice(movement.id),
                    ),
                    child: const Text('Practice'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Button(
                    key: ValueKey('my-movement-edit-${movement.id}'),
                    onPressed: () => _edit(context),
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Archive ${movement.name}',
                  child: IconButton(
                    key: ValueKey('my-movement-archive-${movement.id}'),
                    icon: const Icon(FluentIcons.archive),
                    onPressed: () => repository.archiveMovement(
                      movementId: movement.id,
                      ownerUid: ownerUid,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
