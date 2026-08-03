import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/session_summary_sheet.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _practiceFeedback(String message) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Basic Flip',
    score: 50,
    feedback: message,
    feedbackType: 'warning',
    postureStatus: 'ok',
  );
}

Future<void> _openSummary(
  WidgetTester tester, {
  required Future<String> Function(String? existingSessionId) onSave,
}) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (context) {
          return Center(
            child: FilledButton(
              onPressed: () async {
                await SessionSummarySheet.show(
                  context,
                  movement: 'Basic Flip',
                  score: 50,
                  durationSeconds: 45,
                  feedbacks: [_practiceFeedback('Keep your wrist steady')],
                  onSave: onSave,
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  tester.takeException();
}

Finder get _saveButton => find.byType(GameActionButton);

void main() {
  testWidgets('duplicate save clicks issue one persistence operation', (
    tester,
  ) async {
    var saveCalls = 0;

    await _openSummary(
      tester,
      onSave: (existingSessionId) async {
        saveCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return existingSessionId ?? 'session-duplicate';
      },
    );

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
    expect(saveCalls, 1);
    await tester.pump(const Duration(milliseconds: 200));
    tester.takeException();
  });

  testWidgets('failed save shows error and restores enabled actions', (
    tester,
  ) async {
    await _openSummary(
      tester,
      onSave: (_) async {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      },
    );

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    expect(find.textContaining('Could not save your session'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Discard without saving'), findsOneWidget);
    expect(_saveButton, findsOneWidget);
  });

  testWidgets('successful retry closes the dialog once', (tester) async {
    var saveCalls = 0;
    SessionSummaryResult? result;

    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: FilledButton(
                onPressed: () async {
                  result = await SessionSummarySheet.show(
                    context,
                    movement: 'Basic Flip',
                    score: 50,
                    durationSeconds: 45,
                    feedbacks: [_practiceFeedback('Keep your wrist steady')],
                    onSave: (existingSessionId) async {
                      saveCalls++;
                      if (saveCalls == 1) {
                        throw FirebaseException(
                          plugin: 'cloud_firestore',
                          code: 'unavailable',
                        );
                      }
                      return existingSessionId ?? 'session-retry';
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    tester.takeException();

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
    expect(find.textContaining('Could not save your session'), findsOneWidget);

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    expect(saveCalls, 2);
    expect(result, SessionSummaryResult.saved);
  });
}
