import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enabled catalog names match the 12 official identity mappings', () {
    final enabled = movementCatalog
        .where((movement) => movement.enabled)
        .map((movement) => movement.name)
        .toSet();
    expect(enabled, unorderedEquals(officialElixrMovementNames));
    expect(
      officialElixrMovementIdentities.map((identity) => identity.catalogName),
      unorderedEquals(enabled),
    );
    expect(enabled.contains('Arm Stall'), isFalse);
    expect(enabled.contains('Free Practice'), isFalse);
  });
}
