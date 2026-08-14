import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FilledButton safely renders inside a Row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeacherTheme(),
        home: const Scaffold(
          body: Row(
            children: [
              Text('Title'),
              Spacer(),
              FilledButton(onPressed: null, child: Text('Action')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
