import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes each prop with its protocol value and label', () {
    expect(TrainingProp.bottle.protocolValue, 'bottle');
    expect(TrainingProp.bottle.displayLabel, 'Bottle');
    expect(TrainingProp.shaker.protocolValue, 'shaker');
    expect(TrainingProp.shaker.displayLabel, 'Cocktail Shaker');
  });

  test('invalid and missing values default to Bottle', () {
    expect(TrainingProp.fromProtocolValue(null), TrainingProp.bottle);
    expect(TrainingProp.fromProtocolValue(''), TrainingProp.bottle);
    expect(TrainingProp.fromProtocolValue('unknown'), TrainingProp.bottle);
    expect(TrainingProp.fromProtocolValue('SHAKER'), TrainingProp.shaker);
  });
}
