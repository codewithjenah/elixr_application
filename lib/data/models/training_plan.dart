import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/utils/manila_day.dart';

import 'training_prop.dart';

enum TrainingPlanType {
  training,
  rest;

  String get firestoreValue => name;

  static TrainingPlanType? tryParse(Object? value) {
    return switch (value) {
      'training' => TrainingPlanType.training,
      'rest' => TrainingPlanType.rest,
      _ => null,
    };
  }
}

/// One primary training or rest plan for a Manila calendar day.
///
/// Completion is never stored. Status is derived from this plan, the current
/// Manila day, and matching completed [Session] records.
class TrainingPlan {
  const TrainingPlan._({
    required this.userId,
    required this.dayKey,
    required this.planType,
    this.movementName,
    this.difficulty,
    this.propType,
    this.targetDurationMinutes,
    this.createdAt,
    this.updatedAt,
  });

  factory TrainingPlan.training({
    required String userId,
    required String dayKey,
    required String movementName,
    required String difficulty,
    required TrainingProp propType,
    required int targetDurationMinutes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrainingPlan._(
      userId: userId,
      dayKey: dayKey,
      planType: TrainingPlanType.training,
      movementName: movementName,
      difficulty: difficulty,
      propType: propType,
      targetDurationMinutes: targetDurationMinutes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory TrainingPlan.rest({
    required String userId,
    required String dayKey,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrainingPlan._(
      userId: userId,
      dayKey: dayKey,
      planType: TrainingPlanType.rest,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static const allowedTargetDurations = [5, 10, 15, 20, 30];
  static const allowedDifficulties = ['Easy', 'Medium', 'Hard'];

  final String userId;
  final String dayKey;
  final TrainingPlanType planType;
  final String? movementName;
  final String? difficulty;
  final TrainingProp? propType;
  final int? targetDurationMinutes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get id => ManilaDay.ownerDayDocumentId(userId: userId, dayKey: dayKey);

  bool get isTraining => planType == TrainingPlanType.training;
  bool get isRest => planType == TrainingPlanType.rest;

  int get targetDurationSeconds =>
      (targetDurationMinutes ?? 0).clamp(0, 24 * 60) * 60;

  static String documentId(String userId, String dayKey) =>
      ManilaDay.ownerDayDocumentId(userId: userId, dayKey: dayKey);

  static String? validate({
    required String userId,
    required String dayKey,
    required TrainingPlanType planType,
    String? movementName,
    String? difficulty,
    TrainingProp? propType,
    int? targetDurationMinutes,
  }) {
    if (userId.isEmpty) return 'User is required.';
    if (!ManilaDay.isValidDayKey(dayKey)) return 'Day key is invalid.';
    if (planType == TrainingPlanType.rest) {
      return null;
    }
    if (movementName == null || !isRecognizedCoachingMovement(movementName)) {
      return 'Choose a recognized movement.';
    }
    if (difficulty == null || !allowedDifficulties.contains(difficulty)) {
      return 'Difficulty is invalid.';
    }
    if (propType == null) return 'Training prop is required.';
    if (targetDurationMinutes == null ||
        !allowedTargetDurations.contains(targetDurationMinutes)) {
      return 'Choose a target duration.';
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'user_id': userId,
      'day_key': dayKey,
      'plan_type': planType.firestoreValue,
    };
    if (isTraining) {
      map['movement_name'] = movementName;
      map['difficulty'] = difficulty;
      map['prop_type'] = propType!.protocolValue;
      map['target_duration_minutes'] = targetDurationMinutes;
    }
    return map;
  }

  static TrainingPlan? tryFromMap(Map<String, dynamic> map, {String? id}) {
    final userId = map['user_id'];
    final dayKey = map['day_key'];
    final planType = TrainingPlanType.tryParse(map['plan_type']);
    if (userId is! String ||
        userId.isEmpty ||
        dayKey is! String ||
        planType == null) {
      return null;
    }
    if (id != null && id != documentId(userId, dayKey)) {
      return null;
    }

    if (planType == TrainingPlanType.rest) {
      if (validate(userId: userId, dayKey: dayKey, planType: planType) !=
          null) {
        return null;
      }
      return TrainingPlan.rest(
        userId: userId,
        dayKey: dayKey,
        createdAt: _readDateTime(map['created_at']),
        updatedAt: _readDateTime(map['updated_at']),
      );
    }

    final durationRaw = map['target_duration_minutes'];
    final duration = durationRaw is num ? durationRaw.toInt() : null;
    final propRaw = map['prop_type'];
    if (propRaw is! String ||
        (propRaw != 'bottle' &&
            propRaw != 'shaker' &&
            propRaw != 'bottle_and_shaker')) {
      return null;
    }
    final plan = TrainingPlan.training(
      userId: userId,
      dayKey: dayKey,
      movementName: map['movement_name'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? '',
      propType: TrainingProp.fromProtocolValue(propRaw),
      targetDurationMinutes: duration ?? 0,
      createdAt: _readDateTime(map['created_at']),
      updatedAt: _readDateTime(map['updated_at']),
    );
    if (validate(
          userId: plan.userId,
          dayKey: plan.dayKey,
          planType: plan.planType,
          movementName: plan.movementName,
          difficulty: plan.difficulty,
          propType: plan.propType,
          targetDurationMinutes: plan.targetDurationMinutes,
        ) !=
        null) {
      return null;
    }
    return plan;
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        return toDate() as DateTime?;
      }
    } catch (_) {}
    return null;
  }
}
