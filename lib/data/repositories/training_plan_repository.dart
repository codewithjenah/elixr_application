import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/utils/manila_day.dart';

import '../models/training_plan.dart';

class TrainingPlanRepository {
  TrainingPlanRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _plans =>
      _firestore.collection(FirestoreCollections.trainingPlans);

  Future<List<TrainingPlan>> getPlansForUser(String userId) async {
    if (userId.isEmpty) return const [];
    final snapshot = await _plans.where('user_id', isEqualTo: userId).get();
    return _decodeDocs(snapshot.docs);
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
    final snapshot = await _plans
        .where('user_id', isEqualTo: userId)
        .where('day_key', isGreaterThanOrEqualTo: startDayKey)
        .where('day_key', isLessThanOrEqualTo: endDayKey)
        .get();
    return _decodeDocs(snapshot.docs);
  }

  Future<void> upsertPlan(TrainingPlan plan) {
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

    final ref = _plans.doc(plan.id);
    return _firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      final payload = plan.toMap();
      payload['updated_at'] = FieldValue.serverTimestamp();
      if (existing.exists) {
        payload['created_at'] = existing.data()?['created_at'];
        // Overwrite so switching training ↔ rest cannot leave stale fields.
        tx.set(ref, payload);
      } else {
        payload['created_at'] = FieldValue.serverTimestamp();
        tx.set(ref, payload);
      }
    });
  }

  Future<void> deletePlan({required String userId, required String dayKey}) {
    final id = TrainingPlan.documentId(userId, dayKey);
    return _plans.doc(id).delete();
  }

  List<TrainingPlan> _decodeDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final plans = <TrainingPlan>[];
    for (final doc in docs) {
      final plan = TrainingPlan.tryFromMap(doc.data(), id: doc.id);
      if (plan != null) plans.add(plan);
    }
    return List<TrainingPlan>.unmodifiable(plans);
  }
}
