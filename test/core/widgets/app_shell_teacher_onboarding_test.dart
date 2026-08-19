import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppShell only arms onboarding for Trainee accounts', () {
    final source = File('lib/core/widgets/app_shell.dart').readAsStringSync();
    expect(source, contains('currentUser?.isTrainee == true'));
    expect(source, contains('OnboardingOverlay.show'));
  });
}
