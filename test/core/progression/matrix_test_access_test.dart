import 'package:elixr_application/core/progression/matrix_test_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enables only for a matching configured UID in a debug build', () {
    expect(
      MatrixTestAccessPolicy.isEnabled(
        isDebugBuild: true,
        configuredUid: ' matrix-uid ',
        signedInUid: ' matrix-uid ',
      ),
      isTrue,
    );
  });

  test('rejects a different signed-in UID', () {
    expect(
      MatrixTestAccessPolicy.isEnabled(
        isDebugBuild: true,
        configuredUid: 'matrix-uid',
        signedInUid: 'other-uid',
      ),
      isFalse,
    );
  });

  test('fails closed for absent or empty UIDs', () {
    for (final configuredUid in <String?>[null, '', '   ']) {
      expect(
        MatrixTestAccessPolicy.isEnabled(
          isDebugBuild: true,
          configuredUid: configuredUid,
          signedInUid: 'matrix-uid',
        ),
        isFalse,
      );
    }
    for (final signedInUid in <String?>[null, '', '   ']) {
      expect(
        MatrixTestAccessPolicy.isEnabled(
          isDebugBuild: true,
          configuredUid: 'matrix-uid',
          signedInUid: signedInUid,
        ),
        isFalse,
      );
    }
  });

  test('rejects a matching UID outside a debug build', () {
    expect(
      MatrixTestAccessPolicy.isEnabled(
        isDebugBuild: false,
        configuredUid: 'matrix-uid',
        signedInUid: 'matrix-uid',
      ),
      isFalse,
    );
  });
}
