import 'package:elixr_core/database/supabase_support.dart';
import 'package:elixr_core/utils/manila_day.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../models/training_plan.dart';

class TrainingPlanRepository {
  TrainingPlanRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  Future<List<TrainingPlan>> getPlansForUser(String userId) async {
    if (userId.isEmpty) return const [];
    final rows = await _client
        .from('training_plans')
        .select()
        .eq('user_id', userId);
    return _decodeRows(rows);
  }

  Future<List<TrainingPlan>> getPlansInRange({
    required String userId,
    required String startDayKey,
    required String endDayKey,
  }) async {
    if (userId.isEmpty ||
        !ManilaDay.isValidDayKey(startDayKey) ||
        !ManilaDay.isValidDayKey(endDayKey)) {
      return const [];
    }
    final rows = await _client
        .from('training_plans')
        .select()
        .eq('user_id', userId)
        .gte('day_key', startDayKey)
        .lte('day_key', endDayKey);
    return _decodeRows(rows);
  }

  Future<void> upsertPlan(TrainingPlan plan) async {
    final error = TrainingPlan.validate(
      userId: plan.userId,
      dayKey: plan.dayKey,
      planType: plan.planType,
      movementName: plan.movementName,
      difficulty: plan.difficulty,
      propType: plan.propType,
      targetDurationMinutes: plan.targetDurationMinutes,
    );
    if (error != null) {
      throw ArgumentError.value(plan, 'plan', error);
    }
    if (_client.auth.currentUser?.id != plan.userId) {
      throw StateError('Training plans can only be saved by their owner.');
    }
    // The server overwrites every plan field so switching training ↔ rest
    // cannot leave stale fields, and preserves the original created_at.
    await _client.rpc<dynamic>(
      'upsert_training_plan',
      params: {'p_plan': plan.toMap()},
    );
  }

  Future<void> deletePlan({required String userId, required String dayKey}) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('Training plans can only be deleted by their owner.');
    }
    return _client.rpc<dynamic>(
      'delete_training_plan',
      params: {'p_day_key': dayKey},
    );
  }

  List<TrainingPlan> _decodeRows(List<Map<String, dynamic>> rows) {
    final plans = <TrainingPlan>[];
    for (final row in rows) {
      final plan = TrainingPlan.tryFromMap(
        compactRow(row),
        id: row['id'] as String,
      );
      if (plan != null) plans.add(plan);
    }
    return List<TrainingPlan>.unmodifiable(plans);
  }
}
