import {applicationDefault, getApps, initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {FieldPath, getFirestore} from 'firebase-admin/firestore';
import teacherClaimModule from '../lib/teacher_role_claim.js';

const {
  TEACHER_ROLE,
  ensureTeacherRoleClaimForUid,
  loadTeacherEvidence,
  teacherEvidenceFailure,
} = teacherClaimModule;

// Safe by default. Pass --apply only after reviewing the dry-run report.
if (getApps().length === 0) initializeApp({credential: applicationDefault()});

const apply = process.argv.includes('--apply');
const firestore = getFirestore();
const auth = getAuth();
const counts = {scanned: 0, eligible: 0, granted: 0, already_correct: 0, invalid: 0, failures: 0};
const invalid = [];
const failures = [];
let cursor = null;

while (true) {
  let query = firestore.collection('users')
    .where('role', '==', TEACHER_ROLE)
    .orderBy(FieldPath.documentId())
    .limit(200);
  if (cursor) query = query.startAfter(cursor);
  const snapshot = await query.get();
  if (snapshot.empty) break;

  for (const profile of snapshot.docs) {
    counts.scanned += 1;
    try {
      const evidence = await loadTeacherEvidence({firestore, uid: profile.id});
      const evidenceFailure = teacherEvidenceFailure(
        evidence.profile,
        evidence.code,
        profile.id,
      );
      if (evidenceFailure) {
        counts.invalid += 1;
        invalid.push({uid: profile.id, reason: evidenceFailure});
        continue;
      }
      const authUser = await auth.getUser(profile.id);
      counts.eligible += 1;
      if (authUser.customClaims?.role === TEACHER_ROLE) {
        counts.already_correct += 1;
        continue;
      }
      if (apply) {
        const result = await ensureTeacherRoleClaimForUid({
          firestore,
          auth,
          uid: profile.id,
        });
        if (!result.granted) throw new Error(`evidence_changed:${result.failure}`);
        counts.granted += 1;
      }
    } catch (error) {
      counts.failures += 1;
      failures.push({uid: profile.id, reason: error?.code || error?.message || 'unknown'});
    }
  }

  cursor = snapshot.docs.at(-1);
  if (snapshot.size < 200) break;
}

console.log(JSON.stringify({
  mode: apply ? 'apply' : 'dry-run',
  ...counts,
  invalid,
  failures,
}, null, 2));
if (!apply) {
  console.log('No claims were changed. Re-run with --apply after reviewing the report.');
}
if (counts.failures > 0) process.exitCode = 1;
