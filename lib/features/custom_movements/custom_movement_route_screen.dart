import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/custom_movement.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../services/auth_service.dart';
import 'custom_movement_practice_screen.dart';

class CustomMovementRouteScreen extends StatefulWidget {
  const CustomMovementRouteScreen({
    super.key,
    required this.movementId,
    this.onExit,
  });
  final String movementId;

  /// Route-specific return behavior. Assignment and legacy routes retain the
  /// practice screen's normal pop behavior when this is omitted.
  final VoidCallback? onExit;

  @override
  State<CustomMovementRouteScreen> createState() =>
      _CustomMovementRouteScreenState();
}

class _CustomMovementRouteScreenState extends State<CustomMovementRouteScreen> {
  Future<(CustomMovement, CustomMovementRevision)?>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= _loadOwned();
  }

  Future<(CustomMovement, CustomMovementRevision)?> _loadOwned() async {
    final uid = context.read<AuthService>().currentUser?.id;
    if (uid == null) return null;
    final repository = context.read<CustomMovementRepository>();
    final movement = await repository.getOwnedMovement(
      movementId: widget.movementId,
      ownerUid: uid,
    );
    if (movement == null || !movement.isActive) return null;
    final revision = await repository.getRevision(
      movementId: movement.id,
      revisionId: movement.activeRevisionId,
    );
    return revision == null ? null : (movement, revision);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(CustomMovement, CustomMovementRevision)?>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ElixScaffoldPage(content: Center(child: ProgressRing()));
        }
        final value = snapshot.data;
        if (value == null) {
          return const ElixScaffoldPage(
            content: Center(
              child: Text('This movement is not available to your account.'),
            ),
          );
        }
        return CustomMovementPracticeScreen(
          movement: value.$1,
          revision: value.$2,
          repository: context.read<CustomMovementRepository>(),
          onExit: widget.onExit,
        );
      },
    );
  }
}
