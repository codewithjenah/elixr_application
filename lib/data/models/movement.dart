class Movement {
  const Movement({
    required this.name,
    required this.difficulty,
    required this.description,
    required this.requiresHandsDetection,
    required this.enabled,
  });

  final String name;
  final String difficulty;
  final String description;
  final bool requiresHandsDetection;
  final bool enabled;
}
