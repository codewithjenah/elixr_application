import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/custom_movement_save_diagnostics.dart';
import 'package:elixr_application/data/repositories/firebase_custom_movement_repository.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('custom movement image and Firestore commit succeed on Windows', (
    tester,
  ) async {
    final app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.windows,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('127.0.0.1', 9099);
    final user = (await auth.signInAnonymously()).user!;

    final firestore = FirebaseFirestore.instanceFor(app: app);
    firestore.useFirestoreEmulator('127.0.0.1', 8080);
    await _seedTraineeRoleForRulesTest(
      projectId: app.options.projectId,
      userId: user.uid,
    );

    final storage = FirebaseStorage.instanceFor(app: app);
    await storage.useStorageEmulator('127.0.0.1', 9199);

    final imageBytes = await File(
      'test/fixtures/custom_movement_reference_test.jpg',
    ).readAsBytes();
    expect(imageBytes.length, inInclusiveRange(1024, 512 * 1024));
    await _verifyStorageEmulatorOwnerRules(
      app: app,
      user: user,
      imageBytes: imageBytes,
    );

    final template = MovementTemplate.tryFrom({
      'schema_version': 1,
      'capture_version': 1,
      'duration_ms': 1000,
      'reference_count': 2,
      'required_modalities': ['prop_translation'],
      'normalization_metadata': {
        'anchor': 'shoulder_midpoint',
        'scale': 'shoulder_width',
        'mirrored': false,
      },
      'feature_capabilities': {
        'pose': false,
        'hands': false,
        'prop_translation': true,
        'release_catch': false,
        'prop_rotation': false,
      },
      'canonical_sequence': [
        {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
        {'timestamp_ms': 1000, 'pose': <String, dynamic>{}},
      ],
      'variability_metadata': {'duration_std_ms': 0.0},
      'prop_events': <Map<String, dynamic>>[],
    })!;

    final repository = FirebaseCustomMovementRepository(
      firestore: firestore,
      storage: storage,
    );
    late final CustomMovement saved;
    try {
      saved = await repository.createMovement(
        ownerUid: user.uid,
        ownerRole: CustomMovementOwnerRole.trainee,
        name: 'Emulator Save',
        description: 'A test movement saved through the Firebase emulators.',
        difficulty: 'Easy',
        propType: TrainingProp.bottle,
        template: template,
        referenceImageJpegBytes: imageBytes,
      );
    } on CustomMovementSaveException catch (error) {
      emitCustomMovementSaveDiagnostic(
        stage: error.stage,
        error: error.cause,
        stackTrace: error.stackTrace,
      );
      rethrow;
    }

    final persisted = await repository.getOwnedMovement(
      movementId: saved.id,
      ownerUid: user.uid,
    );
    expect(persisted?.activeRevisionId, saved.activeRevisionId);
    expect(saved.referenceImageStoragePath, isNotNull);
    final imageMetadata = await storage
        .ref(saved.referenceImageStoragePath!)
        .getMetadata();
    expect(imageMetadata.contentType, 'image/jpeg');
    expect(imageMetadata.size, imageBytes.length);

    await repository.archiveMovement(movementId: saved.id, ownerUid: user.uid);
    await storage.ref(saved.referenceImageStoragePath!).delete();
    await auth.signOut();
  });
}

Future<void> _verifyStorageEmulatorOwnerRules({
  required FirebaseApp app,
  required User user,
  required List<int> imageBytes,
}) async {
  final bucket = app.options.storageBucket!;
  final objectPath =
      'users/${user.uid}/custom_movement_references/'
      'emulator_probe_${DateTime.now().microsecondsSinceEpoch}_revision.jpg';
  final idToken = (await user.getIdToken())!;
  final client = HttpClient();
  try {
    final uploadRequest = await client.postUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: 9199,
        path: '/v0/b/$bucket/o',
        queryParameters: {'uploadType': 'media', 'name': objectPath},
      ),
    );
    uploadRequest.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken')
      ..contentType = ContentType('image', 'jpeg');
    uploadRequest.add(imageBytes);
    final uploadResponse = await uploadRequest.close();
    final uploadBody = await uploadResponse.transform(utf8.decoder).join();
    expect(
      uploadResponse.statusCode,
      anyOf(HttpStatus.ok, HttpStatus.created),
      reason:
          'The Storage emulator owner rule rejected its REST upload: '
          '${sanitizeCustomMovementDiagnosticText(uploadBody)}',
    );

    final deleteRequest = await client.deleteUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: 9199,
        pathSegments: ['v0', 'b', bucket, 'o', objectPath],
      ),
    );
    deleteRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $idToken',
    );
    final deleteResponse = await deleteRequest.close();
    final deleteBody = await deleteResponse.transform(utf8.decoder).join();
    expect(
      deleteResponse.statusCode,
      anyOf(HttpStatus.ok, HttpStatus.noContent),
      reason:
          'The Storage emulator owner rule rejected its REST cleanup: '
          '${sanitizeCustomMovementDiagnosticText(deleteBody)}',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _seedTraineeRoleForRulesTest({
  required String projectId,
  required String userId,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: 8080,
      path:
          '/v1/projects/$projectId/databases/(default)/documents/users/$userId',
      queryParameters: {'updateMask.fieldPaths': 'role'},
    );
    final request = await client.patchUrl(uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer owner')
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'fields': {
          'role': {'stringValue': 'Trainee'},
        },
      }),
    );
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    expect(
      response.statusCode,
      HttpStatus.ok,
      reason: 'Could not seed the emulator-only Trainee role: $responseBody',
    );
  } finally {
    client.close(force: true);
  }
}
