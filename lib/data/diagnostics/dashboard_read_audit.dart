import 'dart:convert';

import '../../data/models/rubric_assessment.dart';
import '../../data/models/session.dart';
import '../../data/models/training_prop.dart';

/// History sizes used by the ELX-011 dashboard read audit.
class DashboardReadAuditHarness {
  static const historySizes = [10, 100, 1000];

  static const historyScalingOperations = [
    'ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser',
    'ProgressRepository.getStatsForUser.sessionCountByMovement',
    'SessionRepository.getSessionsForUser',
  ];

  static const _movements = [
    'Normal Grip',
    'Reverse Grip',
    'Stall',
    'Around The Head',
  ];

  /// Synthetic sessions for a non-production audit user id.
  static List<Session> seedSessions(int count, {String? userId}) {
    if (!historySizes.contains(count)) {
      throw ArgumentError.value(count, 'count', 'must be 10, 100, or 1000');
    }
    final owner = userId ?? 'elx011-synth-$count';
    return [
      for (var index = 0; index < count; index++)
        _syntheticSession(userId: owner, index: index, total: count),
    ];
  }

  /// Local, no-network plan of the **baseline** dashboard Firestore operations
  /// (ProgressRepository.getStatsForUser plus SessionRepository.getSessionsForUser).
  ///
  /// Billable reads are omitted (`null`) because this path does not execute
  /// Firestore Query Explain. Payload bytes are a deterministic JSON estimate
  /// of the client-mapped session documents.
  ///
  /// The trainee dashboard no longer issues the ProgressRepository queries; the
  /// Progress screen still does. This plan remains the measured baseline.
  static DashboardReadAuditReport measureLocalPlan() {
    final rows = <DashboardReadMeasurement>[];
    for (final size in historySizes) {
      final sessions = seedSessions(size);
      final mappedBytes = estimatedMappedSessionListBytes(sessions);
      final countBytes = utf8.encode(jsonEncode({'count': size})).length;
      rows.addAll([
        DashboardReadMeasurement(
          operationName:
              'ProgressRepository.getStatsForUser.countSessionsForUser',
          datasetSize: size,
          returnedDocumentCount: 1,
          estimatedSerializedPayloadBytes: countBytes,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
        DashboardReadMeasurement(
          operationName:
              'ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser',
          datasetSize: size,
          returnedDocumentCount: size,
          estimatedSerializedPayloadBytes: mappedBytes,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
        DashboardReadMeasurement(
          operationName:
              'ProgressRepository.getStatsForUser.sessionCountByMovement',
          datasetSize: size,
          returnedDocumentCount: size,
          estimatedSerializedPayloadBytes: mappedBytes,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
        DashboardReadMeasurement(
          operationName: 'ProgressRepository.getStatsForUser',
          datasetSize: size,
          returnedDocumentCount: 1 + size + size,
          estimatedSerializedPayloadBytes: countBytes + mappedBytes * 2,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
        DashboardReadMeasurement(
          operationName: 'SessionRepository.getSessionsForUser',
          datasetSize: size,
          returnedDocumentCount: size,
          estimatedSerializedPayloadBytes: mappedBytes,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
        DashboardReadMeasurement(
          operationName: 'dashboard.dataLoad.total',
          datasetSize: size,
          returnedDocumentCount: 1 + size + size + size,
          estimatedSerializedPayloadBytes: countBytes + mappedBytes * 3,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
      ]);
    }

    return DashboardReadAuditReport(
      environment: 'local-plan',
      projectId: null,
      emulatorHost: null,
      coldStart: null,
      historySizes: historySizes,
      rows: rows,
      historyScalingOperations: historyScalingOperations,
    );
  }

  /// Local plan of the current trainee dashboard load: one ordered history get.
  static DashboardReadAuditReport measureCurrentDashboardLocalPlan() {
    final rows = <DashboardReadMeasurement>[];
    for (final size in historySizes) {
      final sessions = seedSessions(size);
      final mappedBytes = estimatedMappedSessionListBytes(sessions);
      rows.addAll([
        DashboardReadMeasurement(
          operationName: 'SessionRepository.getSessionsForUser',
          datasetSize: size,
          returnedDocumentCount: size,
          estimatedSerializedPayloadBytes: mappedBytes,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
        DashboardReadMeasurement(
          operationName: 'dashboard.dataLoad.total',
          datasetSize: size,
          returnedDocumentCount: size,
          estimatedSerializedPayloadBytes: mappedBytes,
          elapsedMicroseconds: 0,
          payloadSource: DashboardReadPayloadSource.deterministicEstimate,
        ),
      ]);
    }

    return DashboardReadAuditReport(
      environment: 'local-plan-current-dashboard',
      projectId: null,
      emulatorHost: null,
      coldStart: null,
      historySizes: historySizes,
      rows: rows,
      historyScalingOperations: const ['SessionRepository.getSessionsForUser'],
    );
  }

  static int estimatedMappedSessionListBytes(List<Session> sessions) {
    return utf8
        .encode(
          jsonEncode([
            for (final session in sessions) mappedSessionPayload(session),
          ]),
        )
        .length;
  }

  static Map<String, dynamic> mappedSessionPayload(Session session) {
    return {
      'id': session.id,
      'user_id': session.userId,
      'movement_name': session.movementName,
      'difficulty': session.difficulty,
      'score': session.legacyScore,
      'duration_seconds': session.durationSeconds,
      'prop_type': session.propType.protocolValue,
      'created_at': session.createdAt,
      'assessment_version': session.assessmentVersion,
      if (session.rubric != null) ...session.rubric!.toFirestoreFields(),
    };
  }

  static Session _syntheticSession({
    required String userId,
    required int index,
    required int total,
  }) {
    final created = DateTime.utc(
      2026,
      9,
      10,
      4,
    ).subtract(Duration(hours: index));
    final movement = _movements[index % _movements.length];
    if (index % 17 == 0) {
      return Session(
        id: 'elx011-$total-$index',
        userId: userId,
        movementName: movement,
        difficulty: 'Easy',
        legacyScore: 70 + (index % 20),
        assessmentVersion: 1,
        durationSeconds: 45 + (index % 30),
        createdAt: created.toIso8601String(),
        propType: TrainingProp.bottle,
      );
    }
    final totalScore = 4 + (index % 9);
    return Session(
      id: 'elx011-$total-$index',
      userId: userId,
      movementName: movement,
      difficulty: 'Easy',
      rubric: _rubric(totalScore),
      assessmentVersion: 2,
      durationSeconds: 45 + (index % 30),
      createdAt: created.toIso8601String(),
      propType: TrainingProp.bottle,
    );
  }

  static RubricAssessment _rubric(int total) {
    final scores = <int>[0, 0, 0, 0];
    var remaining = total.clamp(0, 12);
    for (var i = 0; i < scores.length && remaining > 0; i++) {
      final value = remaining >= 3 ? 3 : remaining;
      scores[i] = value;
      remaining -= value;
    }
    return RubricAssessment(
      technique: scores[0],
      stability: scores[1],
      completion: scores[2],
      propPositioning: scores[3],
    );
  }
}

enum DashboardReadPayloadSource { explain, network, deterministicEstimate }

extension DashboardReadPayloadSourceLabel on DashboardReadPayloadSource {
  String get wireValue => switch (this) {
    DashboardReadPayloadSource.explain => 'explain',
    DashboardReadPayloadSource.network => 'network',
    DashboardReadPayloadSource.deterministicEstimate =>
      'deterministic_serialized_estimate',
  };
}

class DashboardReadMeasurement {
  const DashboardReadMeasurement({
    required this.operationName,
    required this.datasetSize,
    required this.returnedDocumentCount,
    required this.estimatedSerializedPayloadBytes,
    required this.elapsedMicroseconds,
    required this.payloadSource,
    this.billableReads,
    this.indexEntriesScanned,
    this.payloadBytes,
  });

  final String operationName;
  final int datasetSize;
  final int returnedDocumentCount;
  final int? billableReads;
  final int? indexEntriesScanned;
  final int? payloadBytes;
  final int estimatedSerializedPayloadBytes;
  final int elapsedMicroseconds;
  final DashboardReadPayloadSource payloadSource;

  String get payloadSourceLabel => payloadSource.wireValue;
}

class DashboardReadAuditReport {
  const DashboardReadAuditReport({
    required this.environment,
    required this.historySizes,
    required this.rows,
    required this.historyScalingOperations,
    this.projectId,
    this.emulatorHost,
    this.coldStart,
  });

  final String environment;
  final String? projectId;
  final String? emulatorHost;
  final bool? coldStart;
  final List<int> historySizes;
  final List<DashboardReadMeasurement> rows;
  final List<String> historyScalingOperations;

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln(
      '| dataset | operation | returned | billable reads | index entries scanned | payload bytes | estimated serialized bytes | elapsed ms | payload source |',
    );
    buffer.writeln(
      '| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |',
    );
    for (final row in rows) {
      buffer.writeln(
        '| ${row.datasetSize} | `${row.operationName}` | ${row.returnedDocumentCount} | ${row.billableReads ?? 'n/a'} | ${row.indexEntriesScanned ?? 'n/a'} | ${row.payloadBytes ?? 'n/a'} | ${row.estimatedSerializedPayloadBytes} | ${(row.elapsedMicroseconds / 1000).toStringAsFixed(1)} | ${row.payloadSourceLabel} |',
      );
    }
    return buffer.toString();
  }
}
