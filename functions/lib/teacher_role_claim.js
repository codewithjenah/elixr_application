'use strict';

const TEACHER_ROLE = 'Teacher';
const TEACHER_ACCESS_CODE_PATTERN = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$/;

function teacherEvidenceFailure(profile, code, uid) {
  if (!profile?.exists) return 'missing_profile';
  if (profile.get('role') !== TEACHER_ROLE) return 'not_teacher_profile';
  const codeId = profile.get('teacher_access_code');
  if (typeof codeId !== 'string' || !TEACHER_ACCESS_CODE_PATTERN.test(codeId)) {
    return 'missing_access_code_reference';
  }
  if (!code?.exists) return 'missing_access_code';
  if (code.get('consumed') !== true) return 'access_code_not_consumed';
  if (code.get('consumed_by') !== uid) return 'access_code_consumer_mismatch';
  return null;
}

async function loadTeacherEvidence({firestore, uid}) {
  const profile = await firestore.collection('users').doc(uid).get();
  const codeId = profile.exists ? profile.get('teacher_access_code') : null;
  const code = typeof codeId === 'string' && TEACHER_ACCESS_CODE_PATTERN.test(codeId)
    ? await firestore.collection('teacher_access_codes').doc(codeId).get()
    : null;
  return {profile, code, codeId};
}

async function ensureTeacherRoleClaimForUid({firestore, auth, uid}) {
  const {profile, code} = await loadTeacherEvidence({firestore, uid});
  const failure = teacherEvidenceFailure(profile, code, uid);
  if (failure) return {granted: false, failure};

  const authUser = await auth.getUser(uid);
  const existingClaims = authUser.customClaims || {};
  if (existingClaims.role === TEACHER_ROLE) {
    return {granted: true, alreadyPresent: true};
  }
  await auth.setCustomUserClaims(uid, {...existingClaims, role: TEACHER_ROLE});
  return {granted: true, alreadyPresent: false};
}

module.exports = {
  TEACHER_ROLE,
  TEACHER_ACCESS_CODE_PATTERN,
  ensureTeacherRoleClaimForUid,
  loadTeacherEvidence,
  teacherEvidenceFailure,
};
