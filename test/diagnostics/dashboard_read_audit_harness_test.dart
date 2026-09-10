import 'package:elixr_application/data/diagnostics/dashboard_read_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardReadAuditHarness', () {
    test(
      'seeds 10, 100, and 1000 synthetic sessions without production PII',
      () {
        for (final size in DashboardReadAuditHarness.historySizes) {
          final sessions = DashboardReadAuditHarness.seedSessions(size);
          expect(sessions, hasLength(size));
          expect(
            sessions.every((session) => session.userId == 'elx011-synth-$size'),
            isTrue,
          );
          expect(
            sessions.any((session) => (session.userId).contains('@')),
            isFalse,
          );
          expect(sessions.first.createdAt, isNotNull);
        }
      },
    );

    test('local measurement rows expose the required fields for each size', () {
      final report = DashboardReadAuditHarness.measureLocalPlan();

      expect(report.environment, 'local-plan');
      expect(report.historySizes, [10, 100, 1000]);
      for (final size in DashboardReadAuditHarness.historySizes) {
        final rows = report.rows.where((row) => row.datasetSize == size);
        final names = rows.map((row) => row.operationName).toList();
        expect(
          names,
          containsAll([
            'ProgressRepository.getStatsForUser',
            'ProgressRepository.getStatsForUser.countSessionsForUser',
            'ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser',
            'ProgressRepository.getStatsForUser.sessionCountByMovement',
            'SessionRepository.getSessionsForUser',
            'dashboard.dataLoad.total',
          ]),
        );
        for (final row in rows) {
          expect(row.returnedDocumentCount, greaterThanOrEqualTo(0));
          expect(row.estimatedSerializedPayloadBytes, greaterThanOrEqualTo(0));
          expect(row.elapsedMicroseconds, greaterThanOrEqualTo(0));
          expect(row.payloadSourceLabel, 'deterministic_serialized_estimate');
        }

        final historyGet = rows.singleWhere(
          (row) => row.operationName == 'SessionRepository.getSessionsForUser',
        );
        expect(historyGet.returnedDocumentCount, size);
        expect(historyGet.estimatedSerializedPayloadBytes, greaterThan(0));
        expect(historyGet.billableReads, isNull);
      }
    });

    test('current dashboard plan is a single ordered history get', () {
      final report =
          DashboardReadAuditHarness.measureCurrentDashboardLocalPlan();

      expect(report.environment, 'local-plan-current-dashboard');
      expect(report.historyScalingOperations, [
        'SessionRepository.getSessionsForUser',
      ]);
      for (final size in DashboardReadAuditHarness.historySizes) {
        final rows = report.rows.where((row) => row.datasetSize == size);
        expect(
          rows.map((row) => row.operationName),
          containsAll([
            'SessionRepository.getSessionsForUser',
            'dashboard.dataLoad.total',
          ]),
        );
        expect(
          rows.any(
            (row) => row.operationName == 'ProgressRepository.getStatsForUser',
          ),
          isFalse,
        );
        final total = rows.singleWhere(
          (row) => row.operationName == 'dashboard.dataLoad.total',
        );
        expect(total.returnedDocumentCount, size);
        expect(total.estimatedSerializedPayloadBytes, greaterThan(0));
        expect(total.billableReads, isNull);
      }
    });

    test('marks the unbounded history fetch as the history-scaling read', () {
      final report = DashboardReadAuditHarness.measureLocalPlan();
      final scaling = report.historyScalingOperations.toSet();
      expect(
        scaling,
        containsAll({
          'ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser',
          'ProgressRepository.getStatsForUser.sessionCountByMovement',
          'SessionRepository.getSessionsForUser',
        }),
      );
      expect(
        scaling.contains(
          'ProgressRepository.getStatsForUser.countSessionsForUser',
        ),
        isFalse,
      );
    });
  });
}
