import {applicationDefault, getApps, initializeApp} from 'firebase-admin/app';
import {FieldValue, Timestamp, getFirestore} from 'firebase-admin/firestore';

// This migration is deliberately dry-run by default. It normalizes existing
// date-only-looking deadlines to Manila end-of-day, adds the compatibility
// maximum of 100, and seeds grading locks for assignments with legacy review
// records. It never rewrites or deletes assignment attempts or Storage clips.
if (getApps().length === 0) initializeApp({credential: applicationDefault()});
const firestore = getFirestore();
const write = process.argv.includes('--write');
const manilaOffsetMs = 8 * 60 * 60 * 1000;
const counts = {
  assignments_scanned: 0,
  assignments_changed: 0,
  max_scores_seeded: 0,
  deadlines_normalized: 0,
  grading_locks_seeded: 0,
  skipped: 0,
  failures: 0,
};

function millis(value) {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toDate === 'function') return value.toDate().getTime();
  return null;
}

function manilaEndOfDay(value) {
  const sourceMillis = millis(value);
  if (sourceMillis == null) return null;
  const manila = new Date(sourceMillis + manilaOffsetMs);
  const utcMillis = Date.UTC(
    manila.getUTCFullYear(),
    manila.getUTCMonth(),
    manila.getUTCDate(),
    15,
    59,
    59,
    999,
  );
  return Timestamp.fromMillis(utcMillis);
}

function isLegacyReview(data) {
  return data.status === 'approved' ||
    data.status === 'needs_retry' ||
    data.review_verdict === 'approved' ||
    data.review_verdict === 'needs_retry' ||
    data.status === 'checked';
}

const [assignmentSnapshot, attemptSnapshot] = await Promise.all([
  firestore.collection('group_assignments').get(),
  firestore.collection('assignment_attempts').get(),
]);
const attemptsByAssignment = new Map();
for (const attempt of attemptSnapshot.docs) {
  const data = attempt.data();
  const list = attemptsByAssignment.get(data.assignment_id) || [];
  list.push(data);
  attemptsByAssignment.set(data.assignment_id, list);
}

const writes = [];
for (const assignment of assignmentSnapshot.docs) {
  counts.assignments_scanned += 1;
  const data = assignment.data();
  if (data.origin !== 'teacher_created' ||
      data.assessment_mode !== 'teacher_reviewed') {
    counts.skipped += 1;
    continue;
  }
  const update = {};
  if (!Number.isInteger(data.max_score) || data.max_score < 1 || data.max_score > 100) {
    update.max_score = 100;
    counts.max_scores_seeded += 1;
  }
  if (data.due_at != null) {
    const normalized = manilaEndOfDay(data.due_at);
    if (normalized == null) {
      counts.failures += 1;
      console.error(`Skipping invalid deadline on ${assignment.id}`);
      continue;
    }
    if (millis(normalized) !== millis(data.due_at)) {
      update.due_at = normalized;
      counts.deadlines_normalized += 1;
    }
  }
  const hasLegacyReview = (attemptsByAssignment.get(assignment.id) || [])
    .some(isLegacyReview);
  if (hasLegacyReview && data.grading_locked !== true) {
    const reviewedAt = (attemptsByAssignment.get(assignment.id) || [])
      .flatMap((attempt) => [
        millis(attempt.reviewed_at),
        millis(attempt.checked_at),
        millis(attempt.review_updated_at),
      ])
      .filter((value) => value != null)
      .sort((a, b) => a - b)[0];
    update.grading_locked = true;
    update.grading_locked_at = reviewedAt == null
      ? FieldValue.serverTimestamp()
      : Timestamp.fromMillis(reviewedAt);
    counts.grading_locks_seeded += 1;
  } else if (data.grading_locked !== true && data.grading_locked !== false) {
    update.grading_locked = false;
  }
  if (Object.keys(update).length === 0) continue;
  counts.assignments_changed += 1;
  if (write) writes.push({ref: assignment.ref, update});
}

if (write) {
  for (let offset = 0; offset < writes.length; offset += 400) {
    const batch = firestore.batch();
    for (const item of writes.slice(offset, offset + 400)) {
      batch.set(item.ref, item.update, {merge: true});
    }
    await batch.commit();
  }
}

console.log(JSON.stringify({mode: write ? 'write' : 'dry-run', ...counts}, null, 2));
if (!write) {
  console.log('No writes performed. Re-run with --write only after reviewing the output.');
}
