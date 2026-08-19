import 'package:elixr_application/data/models/training_plan.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrainingPlan identity', () {
    test('uses a deterministic owner/day document id', () {
      final plan = TrainingPlan.training(
        userId: 'alice',
        dayKey: '20260819',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        propType: TrainingProp.bottle,
        targetDurationMinutes: 10,
      );
      expect(plan.id, 'alice_20260819');
      expect(TrainingPlan.documentId('alice', '20260819'), 'alice_20260819');
    });
  });

  group('TrainingPlan validation', () {
    test('accepts a training plan with a catalog movement and duration', () {
      expect(
        TrainingPlan.validate(
          userId: 'alice',
          dayKey: '20260819',
          planType: TrainingPlanType.training,
          movementName: 'Hand Stall',
          difficulty: 'Medium',
          propType: TrainingProp.shaker,
          targetDurationMinutes: 15,
        ),
        isNull,
      );
    });

    test('accepts a rest plan without movement fields', () {
      expect(
        TrainingPlan.validate(
          userId: 'alice',
          dayKey: '20260819',
          planType: TrainingPlanType.rest,
        ),
        isNull,
      );
    });

    test('rejects unknown movements, durations, and empty owners', () {
      expect(
        TrainingPlan.validate(
          userId: '',
          dayKey: '20260819',
          planType: TrainingPlanType.rest,
        ),
        isNotNull,
      );
      expect(
        TrainingPlan.validate(
          userId: 'alice',
          dayKey: '20261301',
          planType: TrainingPlanType.rest,
        ),
        isNotNull,
      );
      expect(
        TrainingPlan.validate(
          userId: 'alice',
          dayKey: '20260819',
          planType: TrainingPlanType.training,
          movementName: 'Not A Move',
          difficulty: 'Medium',
          propType: TrainingProp.bottle,
          targetDurationMinutes: 10,
        ),
        isNotNull,
      );
      expect(
        TrainingPlan.validate(
          userId: 'alice',
          dayKey: '20260819',
          planType: TrainingPlanType.training,
          movementName: 'Hand Stall',
          difficulty: 'Medium',
          propType: TrainingProp.bottle,
          targetDurationMinutes: 7,
        ),
        isNotNull,
      );
    });
  });

  group('TrainingPlan serialization', () {
    test('round-trips a training plan', () {
      final plan = TrainingPlan.training(
        userId: 'alice',
        dayKey: '20260819',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        propType: TrainingProp.bottle,
        targetDurationMinutes: 10,
      );
      final parsed = TrainingPlan.tryFromMap(plan.toMap(), id: plan.id);
      expect(parsed, isNotNull);
      expect(parsed!.movementName, 'Hand Stall');
      expect(parsed.difficulty, 'Medium');
      expect(parsed.propType, TrainingProp.bottle);
      expect(parsed.targetDurationMinutes, 10);
      expect(parsed.isTraining, isTrue);
    });

    test('round-trips a rest plan without training fields', () {
      final plan = TrainingPlan.rest(userId: 'alice', dayKey: '20260820');
      final map = plan.toMap();
      expect(map.containsKey('movement_name'), isFalse);
      expect(map['plan_type'], 'rest');
      final parsed = TrainingPlan.tryFromMap(map, id: plan.id);
      expect(parsed, isNotNull);
      expect(parsed!.isRest, isTrue);
    });

    test('rejects a mismatched document id', () {
      final map = TrainingPlan.rest(
        userId: 'alice',
        dayKey: '20260819',
      ).toMap();
      expect(TrainingPlan.tryFromMap(map, id: 'bob_20260819'), isNull);
    });

    test('rejects an unknown prop type', () {
      expect(
        TrainingPlan.tryFromMap({
          'user_id': 'alice',
          'day_key': '20260819',
          'plan_type': 'training',
          'movement_name': 'Hand Stall',
          'difficulty': 'Medium',
          'prop_type': 'tin',
          'target_duration_minutes': 10,
        }),
        isNull,
      );
    });
  });
}
