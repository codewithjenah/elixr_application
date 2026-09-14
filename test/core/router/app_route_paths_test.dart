import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personal practice route preserves reserved query values', () {
    final location = AppRoutePaths.personalPractice(
      movement: 'Hand & Stall / A',
      difficulty: 'Medium / Plus',
      prop: 'bottle&shaker',
    );
    final uri = Uri.parse(location);

    expect(uri.path, AppRoutePaths.practice);
    expect(uri.queryParameters, {
      'movement': 'Hand & Stall / A',
      'difficulty': 'Medium / Plus',
      'prop': 'bottle&shaker',
    });
  });
}
