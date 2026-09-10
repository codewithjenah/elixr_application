import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dashboard_firestore_emulator_client.dart';
import 'package:elixr_application/data/diagnostics/dashboard_read_audit.dart';

void main() {
  test(
    'emulator audit captures 10/100/1000 dashboard read measurements',
    () async {
      final audit = DashboardFirestoreEmulatorAudit();
      addTearDown(audit.close);
      final report = await audit.measure();
      expect(report.environment, 'firestore-emulator');
      expect(report.historySizes, DashboardReadAuditHarness.historySizes);
      for (final size in DashboardReadAuditHarness.historySizes) {
        final rows = report.rows.where((row) => row.datasetSize == size);
        expect(
          rows.map((row) => row.operationName),
          containsAll([
            'ProgressRepository.getStatsForUser',
            'ProgressRepository.getStatsForUser.countSessionsForUser',
            'ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser',
            'ProgressRepository.getStatsForUser.sessionCountByMovement',
            'SessionRepository.getSessionsForUser',
            'dashboard.dataLoad.total',
          ]),
        );
        final history = rows.singleWhere(
          (row) => row.operationName == 'SessionRepository.getSessionsForUser',
        );
        expect(history.returnedDocumentCount, size);
        expect(history.estimatedSerializedPayloadBytes, greaterThan(0));
        expect(history.elapsedMicroseconds, greaterThan(0));
      }
      // ignore: avoid_print
      print(report.toMarkdown());
    },
    skip: Platform.environment['ELIXR_FIRESTORE_EMULATOR'] != '1'
        ? 'Set ELIXR_FIRESTORE_EMULATOR=1 against a local Firestore emulator'
        : false,
  );
}
