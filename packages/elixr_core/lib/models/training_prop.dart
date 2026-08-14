enum TrainingProp {
  bottle(protocolValue: 'bottle', displayLabel: 'Bottle'),
  shaker(protocolValue: 'shaker', displayLabel: 'Cocktail Shaker'),
  bottleAndShaker(
    protocolValue: 'bottle_and_shaker',
    displayLabel: 'Bottle + Cocktail Shaker',
  );

  const TrainingProp({required this.protocolValue, required this.displayLabel});

  final String protocolValue;
  final String displayLabel;

  static TrainingProp fromProtocolValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'bottle' => TrainingProp.bottle,
      'shaker' => TrainingProp.shaker,
      'bottle_and_shaker' => TrainingProp.bottleAndShaker,
      _ => TrainingProp.bottle,
    };
  }

  static TrainingProp parse(Object? value) => fromProtocolValue(value);
}
