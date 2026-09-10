import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/data/diagnostics/dashboard_read_audit.dart';
import 'package:elixr_application/data/models/session.dart';

/// Measures the **baseline** dashboard query shapes against the Firestore emulator:
/// `count` + two unordered session gets + one ordered session get.
///
/// Invoke with `ELIXR_FIRESTORE_EMULATOR=1`. Never called from production UI.
class DashboardFirestoreEmulatorAudit {
  DashboardFirestoreEmulatorAudit({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.projectId = 'demo-elixr-011',
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final String host;
  final int port;
  final String projectId;
  final HttpClient _httpClient;

  Uri get _root => Uri.parse(
    'http://$host:$port/v1/projects/$projectId/databases/(default)',
  );

  void close() => _httpClient.close(force: true);

  Future<DashboardReadAuditReport> measure({bool coldStart = true}) async {
    final rows = <DashboardReadMeasurement>[];
    for (final size in DashboardReadAuditHarness.historySizes) {
      final userId = 'elx011-synth-$size';
      await _deleteUserSessions(userId);
      final sessions = DashboardReadAuditHarness.seedSessions(size);
      await _seedSessions(sessions);
      rows.addAll(await _measureUser(userId: userId, sessions: sessions));
    }
    return DashboardReadAuditReport(
      environment: 'firestore-emulator',
      projectId: projectId,
      emulatorHost: '$host:$port',
      coldStart: coldStart,
      historySizes: DashboardReadAuditHarness.historySizes,
      rows: rows,
      historyScalingOperations:
          DashboardReadAuditHarness.historyScalingOperations,
    );
  }

  Future<List<DashboardReadMeasurement>> _measureUser({
    required String userId,
    required List<Session> sessions,
  }) async {
    final size = sessions.length;
    final estimated = DashboardReadAuditHarness.estimatedMappedSessionListBytes(
      sessions,
    );
    final countEstimate = utf8.encode(jsonEncode({'count': size})).length;

    final count = await _timed(() {
      return _runAggregationQuery(userId: userId, explain: true);
    });
    final unorderedA = await _timed(() {
      return _runQuery(
        userId: userId,
        orderByCreatedAtDesc: false,
        explain: true,
      );
    });
    final unorderedB = await _timed(() {
      return _runQuery(
        userId: userId,
        orderByCreatedAtDesc: false,
        explain: true,
      );
    });
    final ordered = await _timed(() {
      return _runQuery(
        userId: userId,
        orderByCreatedAtDesc: true,
        explain: true,
      );
    });

    DashboardReadMeasurement row({
      required String name,
      required _TimedQuery result,
      required int returned,
      required int estimatedBytes,
    }) {
      return DashboardReadMeasurement(
        operationName: name,
        datasetSize: size,
        returnedDocumentCount: result.returnedDocuments ?? returned,
        billableReads: result.readOperations,
        indexEntriesScanned: result.indexEntriesScanned,
        payloadBytes: result.payloadBytes,
        estimatedSerializedPayloadBytes: estimatedBytes,
        elapsedMicroseconds: result.elapsedMicroseconds,
        payloadSource: result.payloadBytes == null
            ? DashboardReadPayloadSource.deterministicEstimate
            : DashboardReadPayloadSource.network,
      );
    }

    final statsElapsed =
        count.elapsedMicroseconds +
        unorderedA.elapsedMicroseconds +
        unorderedB.elapsedMicroseconds;
    final totalElapsed = statsElapsed + ordered.elapsedMicroseconds;

    return [
      row(
        name: 'ProgressRepository.getStatsForUser.countSessionsForUser',
        result: count,
        returned: 1,
        estimatedBytes: countEstimate,
      ),
      row(
        name:
            'ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser',
        result: unorderedA,
        returned: size,
        estimatedBytes: estimated,
      ),
      row(
        name: 'ProgressRepository.getStatsForUser.sessionCountByMovement',
        result: unorderedB,
        returned: size,
        estimatedBytes: estimated,
      ),
      DashboardReadMeasurement(
        operationName: 'ProgressRepository.getStatsForUser',
        datasetSize: size,
        returnedDocumentCount:
            (count.returnedDocuments ?? 1) +
            (unorderedA.returnedDocuments ?? size) +
            (unorderedB.returnedDocuments ?? size),
        billableReads: _sum([
          count.readOperations,
          unorderedA.readOperations,
          unorderedB.readOperations,
        ]),
        indexEntriesScanned: _sum([
          count.indexEntriesScanned,
          unorderedA.indexEntriesScanned,
          unorderedB.indexEntriesScanned,
        ]),
        payloadBytes: _sum([
          count.payloadBytes,
          unorderedA.payloadBytes,
          unorderedB.payloadBytes,
        ]),
        estimatedSerializedPayloadBytes: countEstimate + estimated * 2,
        elapsedMicroseconds: statsElapsed,
        payloadSource: unorderedA.payloadBytes == null
            ? DashboardReadPayloadSource.deterministicEstimate
            : DashboardReadPayloadSource.network,
      ),
      row(
        name: 'SessionRepository.getSessionsForUser',
        result: ordered,
        returned: size,
        estimatedBytes: estimated,
      ),
      DashboardReadMeasurement(
        operationName: 'dashboard.dataLoad.total',
        datasetSize: size,
        returnedDocumentCount:
            (count.returnedDocuments ?? 1) +
            (unorderedA.returnedDocuments ?? size) +
            (unorderedB.returnedDocuments ?? size) +
            (ordered.returnedDocuments ?? size),
        billableReads: _sum([
          count.readOperations,
          unorderedA.readOperations,
          unorderedB.readOperations,
          ordered.readOperations,
        ]),
        indexEntriesScanned: _sum([
          count.indexEntriesScanned,
          unorderedA.indexEntriesScanned,
          unorderedB.indexEntriesScanned,
          ordered.indexEntriesScanned,
        ]),
        payloadBytes: _sum([
          count.payloadBytes,
          unorderedA.payloadBytes,
          unorderedB.payloadBytes,
          ordered.payloadBytes,
        ]),
        estimatedSerializedPayloadBytes: countEstimate + estimated * 3,
        elapsedMicroseconds: totalElapsed,
        payloadSource: ordered.payloadBytes == null
            ? DashboardReadPayloadSource.deterministicEstimate
            : DashboardReadPayloadSource.network,
      ),
    ];
  }

  int? _sum(List<int?> values) {
    if (values.any((value) => value == null)) return null;
    return values.fold<int>(0, (sum, value) => sum + value!);
  }

  Future<_TimedQuery> _timed(Future<_QueryResult> Function() run) async {
    final watch = Stopwatch()..start();
    final result = await run();
    watch.stop();
    return _TimedQuery(
      elapsedMicroseconds: watch.elapsedMicroseconds,
      returnedDocuments: result.returnedDocuments,
      readOperations: result.readOperations,
      indexEntriesScanned: result.indexEntriesScanned,
      payloadBytes: result.payloadBytes,
    );
  }

  Future<void> _seedSessions(List<Session> sessions) async {
    for (var offset = 0; offset < sessions.length; offset += 500) {
      final chunk = sessions.skip(offset).take(500).toList();
      await _post('/documents:batchWrite', {
        'writes': [
          for (final session in chunk)
            {
              'update': {
                'name':
                    'projects/$projectId/databases/(default)/documents/sessions/${session.id}',
                'fields': _sessionFields(session),
              },
            },
        ],
      });
    }
  }

  Future<void> _deleteUserSessions(String userId) async {
    final existing = await _runQuery(
      userId: userId,
      orderByCreatedAtDesc: false,
      explain: false,
    );
    final names = existing.documentNames;
    for (var offset = 0; offset < names.length; offset += 500) {
      final chunk = names.skip(offset).take(500);
      await _post('/documents:batchWrite', {
        'writes': [
          for (final name in chunk) {'delete': name},
        ],
      });
    }
  }

  Future<_QueryResult> _runQuery({
    required String userId,
    required bool orderByCreatedAtDesc,
    required bool explain,
  }) async {
    final query = <String, dynamic>{
      'from': [
        {'collectionId': 'sessions'},
      ],
      'where': _userFilter(userId),
      if (orderByCreatedAtDesc)
        'orderBy': [
          {
            'field': {'fieldPath': 'created_at'},
            'direction': 'DESCENDING',
          },
        ],
    };
    final body = <String, dynamic>{
      'structuredQuery': query,
      if (explain) 'explainOptions': {'analyze': true},
    };
    final decoded = await _post('/documents:runQuery', body);
    return _parseQueryResponse(decoded);
  }

  Future<_QueryResult> _runAggregationQuery({
    required String userId,
    required bool explain,
  }) async {
    final body = <String, dynamic>{
      'structuredAggregationQuery': {
        'structuredQuery': {
          'from': [
            {'collectionId': 'sessions'},
          ],
          'where': _userFilter(userId),
        },
        'aggregations': [
          {'alias': 'count', 'count': <String, dynamic>{}},
        ],
      },
      if (explain) 'explainOptions': {'analyze': true},
    };
    final decoded = await _post('/documents:runAggregationQuery', body);
    return _parseQueryResponse(decoded, aggregation: true);
  }

  Map<String, dynamic> _userFilter(String userId) {
    return {
      'fieldFilter': {
        'field': {'fieldPath': 'user_id'},
        'op': 'EQUAL',
        'value': {'stringValue': userId},
      },
    };
  }

  _QueryResult _parseQueryResponse(
    Object? decoded, {
    bool aggregation = false,
  }) {
    final documents = <Map<String, dynamic>>[];
    final names = <String>[];
    Map<String, dynamic>? explainMetrics;
    var payloadBytes = utf8.encode(jsonEncode(decoded)).length;

    void consume(Map<String, dynamic> item) {
      final document = item['document'];
      if (document is Map<String, dynamic>) {
        documents.add(document);
        final name = document['name'];
        if (name is String) names.add(name);
      }
      final metrics = item['explainMetrics'];
      if (metrics is Map<String, dynamic>) {
        explainMetrics = metrics;
      }
      final result = item['result'];
      if (aggregation && result is Map<String, dynamic>) {
        documents.add(result);
      }
    }

    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) consume(item);
      }
    } else if (decoded is Map<String, dynamic>) {
      consume(decoded);
      final results = decoded['results'] ?? decoded['result'];
      if (results is List) {
        for (final item in results) {
          if (item is Map<String, dynamic>) consume(item);
        }
      }
    }

    final execution = explainMetrics?['executionStats'];
    int? readOperations;
    int? indexEntriesScanned;
    int? resultsReturned;
    if (execution is Map<String, dynamic>) {
      readOperations = _asInt(execution['readOperations']);
      resultsReturned = _asInt(execution['resultsReturned']);
      final debugStats = execution['debugStats'];
      if (debugStats is Map<String, dynamic>) {
        indexEntriesScanned =
            _asInt(debugStats['indexEntriesScanned']) ??
            _asInt(debugStats['documentsScanned']);
      }
    }

    return _QueryResult(
      returnedDocuments: resultsReturned ?? documents.length,
      readOperations: readOperations,
      indexEntriesScanned: indexEntriesScanned,
      payloadBytes: payloadBytes,
      documentNames: names,
    );
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> _sessionFields(Session session) {
    final created =
        DateTime.tryParse(session.createdAt ?? '') ?? DateTime.utc(2026, 9, 10);
    final fields = <String, dynamic>{
      'user_id': {'stringValue': session.userId},
      'movement_name': {'stringValue': session.movementName},
      'difficulty': {'stringValue': session.difficulty},
      'duration_seconds': {'integerValue': '${session.durationSeconds}'},
      'prop_type': {'stringValue': session.propType.protocolValue},
      'created_at': {'timestampValue': created.toUtc().toIso8601String()},
    };
    if (session.isRubricAssessed && session.rubric != null) {
      final rubric = session.rubric!;
      fields['assessment_version'] = {'integerValue': '2'};
      fields['rubric_total'] = {'integerValue': '${rubric.total}'};
      fields['performance_level'] = {
        'stringValue': rubric.performanceLevel.wireValue,
      };
      fields['rubric'] = {
        'mapValue': {
          'fields': {
            'technique': {'integerValue': '${rubric.technique}'},
            'stability': {'integerValue': '${rubric.stability}'},
            'completion': {'integerValue': '${rubric.completion}'},
            'prop_positioning': {'integerValue': '${rubric.propPositioning}'},
          },
        },
      };
    } else {
      fields['assessment_version'] = {'integerValue': '1'};
      fields['score'] = {'integerValue': '${session.legacyScore ?? 0}'};
    }
    return fields;
  }

  Future<Object?> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_root$path');
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Firestore emulator ${response.statusCode} for $path: $text',
        uri: uri,
      );
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}

class _TimedQuery {
  const _TimedQuery({
    required this.elapsedMicroseconds,
    this.returnedDocuments,
    this.readOperations,
    this.indexEntriesScanned,
    this.payloadBytes,
  });

  final int elapsedMicroseconds;
  final int? returnedDocuments;
  final int? readOperations;
  final int? indexEntriesScanned;
  final int? payloadBytes;
}

class _QueryResult {
  const _QueryResult({
    required this.returnedDocuments,
    required this.documentNames,
    this.readOperations,
    this.indexEntriesScanned,
    this.payloadBytes,
  });

  final int returnedDocuments;
  final int? readOperations;
  final int? indexEntriesScanned;
  final int? payloadBytes;
  final List<String> documentNames;
}
