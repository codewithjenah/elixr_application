import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/calendar/models/calendar_day_summary.dart';
import 'package:elixr_application/features/history/history_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../teacher/teacher_phase3_test_support.dart';

Session _session({
  required String id,
  int? score,
  String? customMovementId,
  String createdAt = '2026-08-02T10:00:00.000',
}) => Session.fromMap({
  'id': id,
  'user_id': 'teacher',
  'movement_name': customMovementId == null ? 'Hand Stall' : 'My Toss',
  'difficulty': 'Easy',
  'duration_seconds': 30,
  'created_at': createdAt,
  'prop_type': 'bottle',
  'assessment_version': 1,
  'score': ?score,
  'custom_movement_id': ?customMovementId,
  'custom_movement_revision_id': ?(customMovementId == null ? null : 'rev'),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final legacyA = _session(id: 'legacy-a', score: 60);
  final legacyB = _session(id: 'legacy-b', score: 80);
  final custom = _session(id: 'custom-a', score: 100, customMovementId: 'm1');

  test('calendar day summaries exclude custom sessions from legacy', () {
    final day = CalendarDaySummary(
      date: DateTime(2026, 8, 2),
      sessions: [legacyA, legacyB, custom],
    );
    expect(day.legacySessionCount, 2);
    expect(day.averageLegacyScore, 70);
    expect(day.bestLegacyScore, 80);
  });

  testWidgets('History legacy cohort and average exclude custom sessions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = phase3TeacherAuth();
    final sessions = SessionService();
    addTearDown(auth.dispose);
    addTearDown(sessions.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SessionService>.value(value: sessions),
        ],
        child: FluentApp(
          theme: AppTheme.dark,
          home: ElixShadThemeBridge(
            child: HistoryScreen(
              sessionsLoader: (_) async => [legacyA, custom, legacyB],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Legacy-only aggregate: (60 + 80) / 2 = 70 from 2 sessions. The custom
    // 100% would have produced 80 from 3 sessions if it were mixed in.
    expect(find.text('Average Score'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.text('from 2 sessions'), findsOneWidget);
    expect(find.text('Best Score'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('Total Sessions'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Custom Assessment'), findsOneWidget);
  });
}
