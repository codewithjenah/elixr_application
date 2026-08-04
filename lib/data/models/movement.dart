import 'training_prop.dart';

class Movement {
  const Movement({
    required this.name,
    required this.difficulty,
    required this.description,
    required this.requiresHandsDetection,
    required this.enabled,
    this.supportedProps = const [TrainingProp.bottle],
  });

  final String name;
  final String difficulty;
  final String description;
  final bool requiresHandsDetection;
  final bool enabled;

  /// Props this movement can be practiced with. Prop availability is owned
  /// by movement metadata rather than inferred from [difficulty]: most
  /// movements default to [TrainingProp.bottle] only, some explicitly offer
  /// a choice between multiple props, and some require a fixed combination
  /// such as [TrainingProp.bottleAndShaker].
  final List<TrainingProp> supportedProps;
}
