import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:elixr_application/data/models/activity_learning_material.dart';
import 'package:elixr_application/data/repositories/activity_learning_material_repository.dart';
import 'package:elixr_application/features/activity_learning_materials/activity_learning_materials_panel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _MaterialsRepository implements ActivityLearningMaterialRepository {
  _MaterialsRepository({this.materials = const []});

  List<ActivityLearningMaterial> materials;
  final List<_BeginCall> beginCalls = [];
  final List<ActivityMaterialUpload> stagedUploads = [];
  final List<String> statusCalls = [];
  final List<_LinkCall> linkCalls = [];
  final List<_RemoveCall> removeCalls = [];
  final List<ActivityLearningMaterial> openCalls = [];
  final Queue<Object> statusResults = Queue<Object>();
  Future<ActivityMaterialUpload>? beginFuture;
  Future<void>? stagedFuture;
  Future<void>? removeFuture;
  Future<File>? openFuture;
  Object? openFailure;
  Object? listFailure;
  Object? removeFailure;
  Object? linkFailure;

  @override
  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
  }) async {
    linkCalls.add(_LinkCall(assignmentId, displayName, url));
    final failure = linkFailure;
    if (failure != null) throw failure;
    return ActivityLearningMaterial(
      id: 'link-${linkCalls.length}',
      assignmentId: assignmentId,
      type: ActivityLearningMaterialType.link,
      displayName: displayName,
      externalUrl: url,
    );
  }

  @override
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  }) {
    beginCalls.add(
      _BeginCall(
        assignmentId,
        type,
        displayName,
        declaredContentType,
        sizeBytes,
      ),
    );
    return beginFuture ?? Future.value(_upload());
  }

  @override
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  }) async {
    statusCalls.add(uploadId);
    final next = statusResults.isEmpty
        ? _status(ActivityMaterialUploadState.validating)
        : statusResults.removeFirst();
    if (next is Future<ActivityMaterialUploadStatus>) return next;
    if (next is ActivityMaterialUploadStatus) return next;
    throw next;
  }

  @override
  Future<List<ActivityLearningMaterial>> list({
    required String assignmentId,
  }) async {
    final failure = listFailure;
    if (failure != null) throw failure;
    return materials;
  }

  @override
  Future<File> openFile(ActivityLearningMaterial material) async {
    openCalls.add(material);
    final failure = openFailure;
    if (failure != null) throw failure;
    final future = openFuture;
    if (future != null) return future;
    throw StateError('No test file');
  }

  @override
  Future<void> remove({
    required String assignmentId,
    required String materialId,
  }) async {
    removeCalls.add(_RemoveCall(assignmentId, materialId));
    final failure = removeFailure;
    if (failure != null) throw failure;
    await removeFuture;
  }

  @override
  Future<void> uploadStagedFile({
    required ActivityMaterialUpload upload,
    required File file,
  }) async {
    stagedUploads.add(upload);
    await stagedFuture;
  }
}

class _BeginCall {
  const _BeginCall(
    this.assignmentId,
    this.type,
    this.displayName,
    this.contentType,
    this.sizeBytes,
  );
  final String assignmentId;
  final ActivityLearningMaterialType type;
  final String displayName;
  final String contentType;
  final int sizeBytes;
}

class _LinkCall {
  const _LinkCall(this.assignmentId, this.displayName, this.url);
  final String assignmentId;
  final String displayName;
  final Uri url;
}

class _RemoveCall {
  const _RemoveCall(this.assignmentId, this.materialId);
  final String assignmentId;
  final String materialId;
}

const _pdf = ActivityLearningMaterial(
  id: 'material-pdf',
  assignmentId: 'assignment-1',
  type: ActivityLearningMaterialType.pdf,
  displayName: 'Safety Guidelines.pdf',
  sizeBytes: 1468006,
  storagePath: 'server-only-path',
);

ActivityMaterialUpload _upload() => ActivityMaterialUpload(
  uploadId: 'upload-1',
  materialId: _pdf.id,
  stagingPath: 'staging/path',
  declaredContentType: 'application/pdf',
  expiresAt: DateTime.utc(2030),
);

ActivityMaterialUploadStatus _status(
  ActivityMaterialUploadState state, {
  ActivityMaterialUploadRejectionReason? rejectionReason,
  ActivityLearningMaterial? material,
}) => ActivityMaterialUploadStatus(
  uploadId: 'upload-1',
  materialId: _pdf.id,
  state: state,
  rejectionReason: rejectionReason,
  material: material,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(content: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  Future<File> testPdf() async {
    final directory = Directory.systemTemp.createTempSync(
      'elixr-material-test-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final file = File(
      '${directory.path}${Platform.pathSeparator}safety-guidelines.pdf',
    );
    file.writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);
    return file;
  }

  Future<void> choosePdf(WidgetTester tester) async {
    await tester.tap(find.text('Add material'));
    await tester.pump();
    await tester.tap(find.text('PDF').last);
    await tester.pump();
  }

  Future<void> flush(WidgetTester tester, {int frames = 8}) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var frame = 0; frame < frames; frame++) {
      // Fluent UI buttons retain a 100 ms hover-exit timer after taps.
      await tester.pump(const Duration(milliseconds: 101));
    }
  }

  ActivityLearningMaterialsPanel teacherPanel(
    _MaterialsRepository repository, {
    ActivityLearningMaterialFilePicker? picker,
    int polls = 20,
  }) => ActivityLearningMaterialsPanel(
    assignmentId: 'assignment-1',
    repository: repository,
    filePicker: picker ?? ({required acceptedTypeGroups}) async => null,
    pollingInterval: const Duration(milliseconds: 1),
    maximumPollCount: polls,
  );

  testWidgets('teacher manager shows existing canonical materials', (
    tester,
  ) async {
    await pump(tester, teacherPanel(_MaterialsRepository(materials: [_pdf])));
    expect(find.text('Learning materials'), findsOneWidget);
    expect(find.text('Add material'), findsOneWidget);
    expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
    expect(find.text('PDF · 1.4 MB'), findsOneWidget);
  });

  testWidgets('file upload reaches ready only after authoritative status', (
    tester,
  ) async {
    final repository = _MaterialsRepository()
      ..statusResults.addAll([
        _status(ActivityMaterialUploadState.staging),
        _status(ActivityMaterialUploadState.ready, material: _pdf),
      ]);
    final file = await testPdf();
    await pump(
      tester,
      teacherPanel(
        repository,
        picker: ({required acceptedTypeGroups}) async =>
            XFile(file.path, name: 'Safety.pdf'),
      ),
    );
    await choosePdf(tester);
    await flush(tester);
    expect(repository.beginCalls, hasLength(1));
    expect(repository.stagedUploads, hasLength(1));
    expect(repository.statusCalls, ['upload-1', 'upload-1']);
    expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
    expect(find.text('Processing'), findsNothing);
  });

  testWidgets(
    'rejected uploads use safe rejection messages and never add material',
    (tester) async {
      final repository = _MaterialsRepository()
        ..statusResults.add(
          _status(
            ActivityMaterialUploadState.rejected,
            rejectionReason:
                ActivityMaterialUploadRejectionReason.invalidContent,
          ),
        );
      final file = await testPdf();
      expect(file.existsSync(), isTrue);
      await pump(
        tester,
        teacherPanel(
          repository,
          picker: ({required acceptedTypeGroups}) async =>
              XFile(file.path, name: 'not-really-pdf.pdf'),
        ),
      );
      await choosePdf(tester);
      await flush(tester);
      expect(repository.beginCalls, hasLength(1));
      expect(repository.statusCalls, ['upload-1']);
      expect(
        find.text('The selected file is not a valid supported file.'),
        findsOneWidget,
      );
      expect(find.text('Safety Guidelines.pdf'), findsNothing);
      expect(find.textContaining('internal'), findsNothing);
    },
  );

  testWidgets(
    'processing polls are bounded and manual recheck can publish later',
    (tester) async {
      final repository = _MaterialsRepository()
        ..statusResults.addAll([
          _status(ActivityMaterialUploadState.validating),
          _status(ActivityMaterialUploadState.staging),
          _status(ActivityMaterialUploadState.ready, material: _pdf),
        ]);
      final file = await testPdf();
      await pump(
        tester,
        teacherPanel(
          repository,
          polls: 2,
          picker: ({required acceptedTypeGroups}) async =>
              XFile(file.path, name: 'Safety.pdf'),
        ),
      );
      await choosePdf(tester);
      await flush(tester);
      expect(repository.statusCalls, hasLength(2));
      expect(
        find.text('Still processing. Check again shortly.'),
        findsOneWidget,
      );
      expect(find.text('Check status'), findsOneWidget);
      await tester.tap(find.text('Check status'));
      await flush(tester);
      expect(repository.statusCalls, hasLength(3));
      expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
    },
  );

  testWidgets('manual status checks do not overlap', (tester) async {
    final pendingCheck = Completer<ActivityMaterialUploadStatus>();
    final repository = _MaterialsRepository()
      ..statusResults.add(_status(ActivityMaterialUploadState.validating))
      ..statusResults.add(pendingCheck.future);
    final file = await testPdf();
    await pump(
      tester,
      teacherPanel(
        repository,
        polls: 1,
        picker: ({required acceptedTypeGroups}) async =>
            XFile(file.path, name: 'Safety.pdf'),
      ),
    );
    await choosePdf(tester);
    await flush(tester);
    await tester.tap(find.text('Check status'));
    await tester.pump();
    final checkStatus = find.ancestor(
      of: find.text('Check status'),
      matching: find.byType(Button),
    );
    expect(tester.widget<Button>(checkStatus).onPressed, isNull);
    await tester.tap(checkStatus);
    await tester.pump();
    expect(repository.statusCalls, hasLength(2));
    pendingCheck.complete(
      _status(ActivityMaterialUploadState.ready, material: _pdf),
    );
    await flush(tester);
    expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
  });

  testWidgets('cancelling before reservation then after it is safe', (
    tester,
  ) async {
    final beginGate = Completer<ActivityMaterialUpload>();
    final repository = _MaterialsRepository()..beginFuture = beginGate.future;
    final file = await testPdf();
    await pump(
      tester,
      teacherPanel(
        repository,
        picker: ({required acceptedTypeGroups}) async =>
            XFile(file.path, name: 'Safety.pdf'),
      ),
    );
    await choosePdf(tester);
    await flush(tester, frames: 1);
    await tester.tap(find.byIcon(FluentIcons.cancel));
    await tester.pump();
    expect(repository.removeCalls, isEmpty);
    beginGate.complete(_upload());
    await flush(tester);
    expect(repository.removeCalls.single.materialId, _pdf.id);
    expect(repository.statusCalls, isEmpty);
  });

  testWidgets('cancelling after reservation prevents late publication', (
    tester,
  ) async {
    final uploadGate = Completer<void>();
    final repository = _MaterialsRepository()..stagedFuture = uploadGate.future;
    final file = await testPdf();
    await pump(
      tester,
      teacherPanel(
        repository,
        picker: ({required acceptedTypeGroups}) async =>
            XFile(file.path, name: 'Safety.pdf'),
      ),
    );
    await choosePdf(tester);
    await flush(tester, frames: 1);
    await tester.tap(find.byIcon(FluentIcons.cancel));
    await tester.pump();
    expect(repository.removeCalls.single.materialId, _pdf.id);
    uploadGate.complete();
    await flush(tester);
    expect(repository.statusCalls, isEmpty);
    expect(find.text('Safety Guidelines.pdf'), findsNothing);
  });

  testWidgets('disposing while a status request completes is safe', (
    tester,
  ) async {
    final statusGate = Completer<ActivityMaterialUploadStatus>();
    final repository = _MaterialsRepository()
      ..statusResults.add(statusGate.future);
    final file = await testPdf();
    await pump(
      tester,
      teacherPanel(
        repository,
        polls: 1,
        picker: ({required acceptedTypeGroups}) async =>
            XFile(file.path, name: 'Safety.pdf'),
      ),
    );
    await choosePdf(tester);
    await tester.pump();
    await tester.pumpWidget(const FluentApp(home: SizedBox.shrink()));
    statusGate.complete(
      _status(ActivityMaterialUploadState.ready, material: _pdf),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removal is single-flight and removes canonical material on success',
    (tester) async {
      final removalGate = Completer<void>();
      final repository = _MaterialsRepository(materials: [_pdf])
        ..removeFuture = removalGate.future;
      await pump(tester, teacherPanel(repository));
      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pump();
      expect(repository.removeCalls, hasLength(1));
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      removalGate.complete();
      await flush(tester);
      expect(find.text('Safety Guidelines.pdf'), findsNothing);
    },
  );

  testWidgets('failed removal preserves material and allows retry', (
    tester,
  ) async {
    final repository = _MaterialsRepository(materials: [_pdf])
      ..removeFailure = StateError('network');
    await pump(tester, teacherPanel(repository));
    await tester.tap(find.byIcon(FluentIcons.delete));
    await flush(tester);
    expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
    expect(
      find.text('The material could not be removed. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('link composer rejects unsafe URLs and accepts HTTP(S)', (
    tester,
  ) async {
    final repository = _MaterialsRepository();
    await pump(tester, teacherPanel(repository));
    for (final value in [
      '',
      'not a url',
      'file:///tmp/x',
      'javascript:alert(1)',
      'data:text/plain,x',
      'https://user:pass@example.com',
    ]) {
      await tester.tap(find.text('Add material'));
      await tester.pump();
      await tester.tap(find.text('Link').last);
      await tester.pump();
      await tester.enterText(find.byType(TextBox).at(0), 'Reference');
      await tester.enterText(find.byType(TextBox).at(1), value);
      await tester.tap(find.widgetWithText(FilledButton, 'Add link'));
      await tester.pump();
      expect(
        find.text('Enter a name and an HTTP or HTTPS URL.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
    }
    for (final value in [
      'https://example.com/reference',
      'http://example.com/reference',
    ]) {
      await tester.tap(find.text('Add material'));
      await tester.pump();
      await tester.tap(find.text('Link').last);
      await tester.pump();
      await tester.enterText(find.byType(TextBox).at(0), 'Reference');
      await tester.enterText(find.byType(TextBox).at(1), value);
      await tester.tap(find.widgetWithText(FilledButton, 'Add link'));
      await flush(tester);
    }
    expect(repository.linkCalls.map((call) => call.url.scheme), [
      'https',
      'http',
    ]);
    expect(find.text('Reference'), findsNWidgets(2));
  });

  testWidgets('trainee renders every material type with friendly actions', (
    tester,
  ) async {
    const image = ActivityLearningMaterial(
      id: 'image',
      assignmentId: 'assignment-1',
      type: ActivityLearningMaterialType.image,
      displayName:
          'A very long demonstration image name that should gracefully truncate in the card.png',
      storagePath: 'image',
    );
    const video = ActivityLearningMaterial(
      id: 'video',
      assignmentId: 'assignment-1',
      type: ActivityLearningMaterialType.video,
      displayName: 'Demo.mp4',
      storagePath: 'video',
    );
    final link = ActivityLearningMaterial(
      id: 'link',
      assignmentId: 'assignment-1',
      type: ActivityLearningMaterialType.link,
      displayName: 'Reference',
      externalUrl: Uri(scheme: 'https', host: 'example.com'),
    );
    await pump(
      tester,
      ActivityLearningMaterialsTraineeSection(
        assignmentId: 'assignment-1',
        repository: _MaterialsRepository(materials: [_pdf, image, video, link]),
      ),
    );
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Open link'), findsOneWidget);
    expect(find.textContaining('Start'), findsNothing);
    expect(
      tester.widget<Text>(find.text(image.displayName)).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets(
    'trainee discards a file open result from a previous assignment',
    (tester) async {
      const imageA = ActivityLearningMaterial(
        id: 'image-a',
        assignmentId: 'assignment-a',
        type: ActivityLearningMaterialType.image,
        displayName: 'A demonstration.png',
        storagePath: 'image-a',
      );
      const pdfB = ActivityLearningMaterial(
        id: 'pdf-b',
        assignmentId: 'assignment-b',
        type: ActivityLearningMaterialType.pdf,
        displayName: 'B safety guide.pdf',
        storagePath: 'pdf-b',
      );
      final openAGate = Completer<File>();
      final openBGate = Completer<File>();
      final repositoryA = _MaterialsRepository(materials: [imageA])
        ..openFuture = openAGate.future;
      final repositoryB = _MaterialsRepository(materials: [pdfB])
        ..openFuture = openBGate.future;

      await pump(
        tester,
        ActivityLearningMaterialsTraineeSection(
          assignmentId: 'assignment-a',
          repository: repositoryA,
        ),
      );
      await tester.tap(find.text('View'));
      await tester.pump();
      expect(repositoryA.openCalls, [imageA]);

      await pump(
        tester,
        ActivityLearningMaterialsTraineeSection(
          assignmentId: 'assignment-b',
          repository: repositoryB,
        ),
      );
      expect(find.text(pdfB.displayName), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(repositoryB.openCalls, [pdfB]);
      expect(find.byType(ProgressRing), findsOneWidget);

      openAGate.complete(File('stale-a.png'));
      await tester.pump();
      await flush(tester, frames: 1);

      expect(find.text(imageA.displayName), findsNothing);
      expect(
        find.text(
          'This material is no longer available or could not be opened.',
        ),
        findsNothing,
      );
      expect(find.text(pdfB.displayName), findsOneWidget);
      expect(find.byType(ProgressRing), findsOneWidget);
    },
  );

  testWidgets(
    'trainee hidden empty state and retry error state are controlled',
    (tester) async {
      final repository = _MaterialsRepository()
        ..listFailure = StateError('offline');
      await pump(
        tester,
        ActivityLearningMaterialsTraineeSection(
          assignmentId: 'assignment-1',
          repository: repository,
        ),
      );
      await tester.pump();
      expect(
        find.text('Learning materials could not be loaded.'),
        findsOneWidget,
      );
      repository.listFailure = null;
      repository.materials = [_pdf];
      await tester.tap(find.text('Retry'));
      await flush(tester);
      expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
      await pump(
        tester,
        ActivityLearningMaterialsTraineeSection(
          assignmentId: 'assignment-1',
          repository: _MaterialsRepository(),
        ),
      );
      expect(find.text('Learning materials'), findsNothing);
    },
  );

  testWidgets(
    'trainee open failures stay controlled and only use material repository',
    (tester) async {
      final repository = _MaterialsRepository(materials: [_pdf])
        ..openFailure = StateError('missing');
      await pump(
        tester,
        ActivityLearningMaterialsTraineeSection(
          assignmentId: 'assignment-1',
          repository: repository,
        ),
      );
      await tester.tap(find.text('Open'));
      await flush(tester);
      expect(repository.openCalls, [_pdf]);
      expect(
        find.text(
          'This material is no longer available or could not be opened.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
