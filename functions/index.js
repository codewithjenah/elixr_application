const {createHash, randomUUID} = require('node:crypto');
const {onRequest} = require('firebase-functions/v2/https');
const {onDocumentWritten, onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onObjectFinalized} = require('firebase-functions/v2/storage');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldPath, FieldValue, Timestamp, getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');

if (getApps().length === 0) initializeApp();

const REGION = 'asia-southeast1';
const STORAGE_BUCKET = process.env.FIREBASE_STORAGE_BUCKET || 'elixr-app-2026.firebasestorage.app';
const SUPPORTED_ROLES = new Set(['Teacher', 'Trainee']);
const SEARCH_LIMIT = 20;
const SEARCH_COOLDOWN_MS = 500;

// Learning materials are deliberately a narrow, server-authoritative surface.
// These limits are authoritative; client-side limits are UX only. Storage rules
// additionally bind an upload to the server-created staging record.
const ACTIVITY_MATERIAL_LIMITS = Object.freeze({
  maxPerAssignment: 10,
  stagingLifetimeMs: 15 * 60 * 1000,
  validationLeaseMs: 5 * 60 * 1000,
  terminalUploadRetentionMs: 7 * 24 * 60 * 60 * 1000,
  reconciliationBatchSize: 100,
  pdfBytes: 20 * 1024 * 1024,
  imageBytes: 10 * 1024 * 1024,
  videoBytes: 100 * 1024 * 1024,
  displayNameLength: 120,
  linkLength: 2048,
});
const ACTIVITY_MATERIAL_TYPES = new Set(['pdf', 'image', 'video', 'link']);
const ACTIVITY_UPLOAD_CONTENT_TYPES = Object.freeze({
  pdf: new Set(['application/pdf']),
  image: new Set(['image/jpeg', 'image/png']),
  video: new Set(['video/mp4']),
});

/**
 * @typedef {'pdf'|'image'|'video'|'link'} ActivityLearningMaterialType
 * @typedef {'staging'|'validating'|'ready'|'rejected'|'deleting'} ActivityMaterialLifecycle
 * @typedef {{upload_id:string, material_id:string, assignment_id:string,
 *   owner_teacher_id:string, type:ActivityLearningMaterialType,
 *   staging_path:string, state:ActivityMaterialLifecycle}} ActivityMaterialStage
 */

function normalizeSearchText(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLocaleLowerCase('en')
    .replace(/\s+/g, ' ');
}

function buildSearchPrefixes(displayName) {
  const normalized = normalizeSearchText(displayName);
  const sources = new Set([normalized, ...normalized.split(' ')]);
  const prefixes = new Set();
  for (const source of sources) {
    for (let length = 2; length <= Math.min(source.length, 40); length += 1) {
      prefixes.add(source.slice(0, length));
      if (prefixes.size >= 100) return [...prefixes];
    }
  }
  return [...prefixes];
}

function conversationIdFor(firstId, secondId) {
  return [firstId, secondId].sort().join('__');
}

function sanitizedResult(uid, data) {
  return {
    id: uid,
    display_name: data.display_name,
    role: data.role,
    ...(data.avatar_url ? {avatar_url: data.avatar_url} : {}),
  };
}

function validateSearchQuery(query) {
  const raw = String(query || '').trim();
  const normalized = normalizeSearchText(raw);
  if (raw.length < 2 || raw.length > 80 || normalized.length < 2) {
    return {valid: false, raw, normalized, emailShaped: false};
  }
  return {
    valid: true,
    raw,
    normalized,
    emailShaped: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw),
  };
}

function sanitizeDirectoryDocuments(requesterUid, documents) {
  return documents
    .filter((document) => document.id !== requesterUid)
    .filter((document) => {
      const data = document.data();
      return data.lifecycle_state === 'active' && SUPPORTED_ROLES.has(data.role);
    })
    .slice(0, SEARCH_LIMIT)
    .map((document) => sanitizedResult(document.id, document.data()));
}

function isSearchRateLimited(lastRequestMs, nowMs) {
  return nowMs - Number(lastRequestMs || 0) < SEARCH_COOLDOWN_MS;
}

function isActiveChatProfile(data) {
  return Boolean(data) &&
    SUPPORTED_ROLES.has(data.role) &&
    data.lifecycle_state !== 'deleting';
}

// Scheduled assignments are intentionally time-gated rather than requiring a
// client timer or an external scheduler. All authorization-sensitive callers
// use this server-clock predicate.
function assignmentIsPublished(assignment, now = Timestamp.now()) {
  return assignment.status === 'active' ||
    (assignment.status === 'scheduled' && assignment.publish_at &&
      now.toMillis() >= assignment.publish_at.toMillis());
}

function archivedConversationId(conversationId, activeIds) {
  const archiveHash = createHash('sha256')
    .update(`${conversationId}|${[...activeIds].sort().join('|')}`)
    .digest('hex')
    .slice(0, 40);
  return `archived_${archiveHash}`;
}

function buildArchivedConversationData({
  data,
  deletedUid,
  activeProfiles,
  archivedAt,
}) {
  const originalSnapshots = data.participant_snapshots || {};
  const deletedSnapshot = originalSnapshots[deletedUid] || {};
  const participantSnapshots = {
    deleted_user: {
      id: 'deleted_user',
      display_name: 'Deleted user',
      role: SUPPORTED_ROLES.has(deletedSnapshot.role)
        ? deletedSnapshot.role
        : 'Trainee',
    },
  };
  for (const [id, profile] of activeProfiles) {
    participantSnapshots[id] = originalSnapshots[id] || {
      id,
      display_name: profile.full_name,
      role: profile.role,
      ...(profile.profile_picture_url
        ? {avatar_url: profile.profile_picture_url}
        : {}),
    };
  }
  const activeIds = [...activeProfiles.keys()];
  const participantIds = [...activeIds, 'deleted_user'].sort();
  const archivedData = {
    ...data,
    participant_ids: participantIds,
    participant_a: participantIds[0],
    participant_b: participantIds[1],
    participant_snapshots: participantSnapshots,
    last_message_sender_id: data.last_message_sender_id === deletedUid
      ? 'deleted_user'
      : data.last_message_sender_id,
    unread_counts: Object.fromEntries(
      activeIds.map((id) => [id, data.unread_counts?.[id] || 0]),
    ),
    read_at: Object.fromEntries(
      activeIds.map((id) => [id, data.read_at?.[id] || null]),
    ),
    status: 'archived',
    updated_at: archivedAt,
    archived_at: archivedAt,
    schema_version: 1,
  };
  delete archivedData.deleted_user_id;
  return archivedData;
}

function setCors(response) {
  response.set('Access-Control-Allow-Origin', '*');
  response.set(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type, X-Firebase-Authorization',
  );
  response.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

function firebaseBearerToken(request) {
  const authorization = request.get('x-firebase-authorization') ||
    request.get('authorization') || '';
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

async function authenticatedUid(request) {
  const token = firebaseBearerToken(request);
  if (!token) return null;
  try {
    return (await getAuth().verifyIdToken(token, true)).uid;
  } catch (_) {
    return null;
  }
}

const OFFICIAL_ASSIGNMENTS = new Map([
  ['Normal Grip', ['official_normal_grip', 'official_normal_grip_v1']],
  ["Bartender's Grip", ['official_bartenders_grip', 'official_bartenders_grip_v1']],
  ['Reverse Grip', ['official_reverse_grip', 'official_reverse_grip_v1']],
  ['Claw Grip', ['official_claw_grip', 'official_claw_grip_v1']],
  ['Hand Stall', ['official_hand_stall', 'official_hand_stall_v1']],
  ['One Finger Stall', ['official_one_finger_stall', 'official_one_finger_stall_v1']],
  ['Forearm Stall', ['official_forearm_stall', 'official_forearm_stall_v1']],
  ['Elbow Stall', ['official_elbow_stall', 'official_elbow_stall_v1']],
  ['Reverse Forearm Stall', ['official_reverse_forearm_stall', 'official_reverse_forearm_stall_v1']],
  ['Shoulder Stall', ['official_shoulder_stall', 'official_shoulder_stall_v1']],
  ['Double Hand Stall', ['official_double_hand_stall', 'official_double_hand_stall_v1']],
  ['Bottle in a tin', ['official_bottle_in_a_tin', 'official_bottle_in_a_tin_v1']],
]);

function assignmentAudienceAllows(data, traineeId, recipient, assignmentId) {
  if (!data || typeof data !== 'object') return false;
  const hasType = Object.hasOwn(data, 'audience_type');
  if (!hasType) return !Object.hasOwn(data, 'target_trainee_ids');
  if (Object.hasOwn(data, 'target_trainee_ids')) return false;
  if (data.audience_type === 'entire_class') return true;
  return Boolean((data.audience_type === 'selected_students' ||
      data.audience_type === 'individual_student') &&
    validRecipientProjection(recipient, assignmentId, traineeId) &&
    recipient.group_id === data.group_id && recipient.teacher_id === data.teacher_id &&
    recipient.audience_type === data.audience_type);
}

function validRecipientProjection(data, assignmentId, traineeId) {
  let createdAtValid = false;
  try {
    const date = data?.created_at?.toDate?.();
    createdAtValid = date instanceof Date && !Number.isNaN(date.getTime());
  } catch (_) {
    createdAtValid = false;
  }
  return Boolean(data) &&
    Object.keys(data).length === 7 &&
    validId(assignmentId) &&
    validId(traineeId) &&
    validId(data.group_id) &&
    validId(data.teacher_id) &&
    data.assignment_id === assignmentId &&
    data.trainee_id === traineeId &&
    data.audience_type !== 'entire_class' &&
    (data.audience_type === 'selected_students' ||
      data.audience_type === 'individual_student') &&
    data.schema_version === 1 &&
    createdAtValid;
}

function assignmentJsonValue(value) {
  if (value instanceof Date) return value.toISOString();
  if (value && typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (Array.isArray(value)) return value.map(assignmentJsonValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [
        key,
        assignmentJsonValue(nested),
      ]),
    );
  }
  return value;
}

function validActivityAssessment(value, expectedMaximum) {
  if (!value || typeof value !== 'object' ||
      ![2, 3].includes(value.schema_version) ||
      !value.readiness || !value.rubric ||
      ![15, 30, 45, 60].includes(value.recording_duration_seconds)) return false;
  const isV2 = value.schema_version === 2;
  const allowedKeys = new Set(isV2 ? [
    'schema_version', 'readiness', 'rubric', 'attempt_policy',
    'recording_duration_seconds', 'demonstration_video',
  ] : [
    'schema_version', 'readiness', 'rubric',
    'recording_duration_seconds', 'demonstration_video',
  ]);
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) return false;
  const readiness = value.readiness;
  if (Object.keys(readiness).sort().join(',') !==
      (isV2 ? 'body,hands,prop' : 'body,hands')) return false;
  if ((isV2 && !['none', 'one_bottle', 'one_shaker', 'bottle_and_shaker', 'two_bottles'].includes(readiness.prop)) ||
      !['none', 'one_hand', 'two_hands'].includes(readiness.hands) ||
      !['none', 'upper_body'].includes(readiness.body)) return false;
  if (isV2 && !validAssignmentAttemptPolicy(value.attempt_policy)) return false;
  const rubric = value.rubric;
  if (!['standard_technique', 'beginner_fundamentals', 'control_consistency',
    'performance_flow', 'custom'].includes(rubric.template_id) ||
      rubric.maximum_score !== expectedMaximum || !Array.isArray(rubric.criteria) ||
      rubric.criteria.length < 3 || rubric.criteria.length > 5) return false;
  const ids = new Set();
  let total = 0;
  for (const criterion of rubric.criteria) {
    if (!criterion || !validId(criterion.id) || ids.has(criterion.id) ||
        !boundedText(criterion.label, 80) || !boundedText(criterion.description, 500) ||
        !Number.isInteger(criterion.maximum_points) || criterion.maximum_points < 1 ||
        (criterion.weight != null && (!Number.isInteger(criterion.weight) ||
          criterion.weight < 1 || criterion.weight > 100)) ||
        criterion.maximum_points > expectedMaximum) return false;
    ids.add(criterion.id); total += criterion.maximum_points;
  }
  const demo = value.demonstration_video;
  if (demo != null && (
    !boundedText(demo.storage_path, 1024) || demo.content_type !== 'video/mp4' ||
    !Number.isInteger(demo.size_bytes) || demo.size_bytes < 1 ||
    demo.size_bytes > 50 * 1024 * 1024 ||
    !Number.isInteger(demo.duration_ms) || demo.duration_ms < 1 ||
    demo.duration_ms > 60000 || !['uploaded', 'recorded'].includes(demo.source)
  )) return false;
  return total === expectedMaximum;
}

function validAssignmentAttemptPolicy(policy) {
  return !!policy && typeof policy === 'object' && (
    (policy.type === 'unlimited' && Object.keys(policy).length === 1) ||
    (policy.type === 'finite' && [1, 2, 3].includes(policy.maximum_attempts) &&
      Object.keys(policy).sort().join(',') === 'maximum_attempts,type')
  );
}

function assignmentAttemptPolicy(assignment) {
  if (validAssignmentAttemptPolicy(assignment.attempt_policy)) {
    return assignment.attempt_policy;
  }
  // Existing v2 Activity assignments carried this delivery policy inside the
  // snapshot. Read it only as a compatibility fallback; new writes never do.
  const legacy = assignment.activity_assessment?.attempt_policy;
  return validAssignmentAttemptPolicy(legacy) ? legacy : {type: 'unlimited'};
}

async function deleteQueryDocuments(firestore, query) {
  let deleted = 0;
  while (true) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) break;
    const batch = firestore.batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
    deleted += snapshot.size;
  }
  return deleted;
}

async function deleteStoragePrefix(storage, prefix) {
  const bucket = storage.bucket();
  const [files] = await bucket.getFiles({prefix});
  for (let index = 0; index < files.length; index += 50) {
    await Promise.all(files.slice(index, index + 50).map((file) =>
      file.delete({ignoreNotFound: true})));
  }
  return files.length;
}

async function cascadeAssignment({firestore, storage, assignmentRef, assignmentData}) {
  const assignmentId = assignmentRef.id;
  const teacherId = assignmentData?.teacher_id;
  const groupId = assignmentData?.group_id;
  if (validId(teacherId) && validId(groupId)) {
    await deleteStoragePrefix(
      storage,
      `assignment_submissions/${teacherId}/${groupId}/${assignmentId}/`,
    );
    await deleteStoragePrefix(
      storage,
      `assignment_media/${teacherId}/${groupId}/${assignmentId}/`,
    );
    await deleteStoragePrefix(
      storage,
      `teacher_activity_demos/${teacherId}/assignments/${assignmentId}/`,
    );
    await deleteStoragePrefix(
      storage,
      `activity_material_staging/${teacherId}/${assignmentId}/`,
    );
  }
  await deleteStoragePrefix(storage, `activity_learning_materials/${assignmentId}/`);
  await deleteQueryDocuments(
    firestore,
    firestore.collection('activity_material_uploads').where('assignment_id', '==', assignmentId),
  );
  await deleteMaterialAccessForAssignment(firestore, assignmentId);
  await materialAccessStateRef(firestore, assignmentId).delete();
  await deleteQueryDocuments(firestore, assignmentRef.collection('learning_materials'));
  await deleteQueryDocuments(
    firestore,
    assignmentRef.collection('assignment_recipients'),
  );
  await deleteQueryDocuments(
    firestore,
    firestore.collection('assignment_attempts').where('assignment_id', '==', assignmentId),
  );
  await deleteQueryDocuments(
    firestore,
    firestore.collection('assignment_attempt_states').where('assignment_id', '==', assignmentId),
  );
  await assignmentRef.delete();
}

async function permanentDeleteAssignmentHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
  storageFactory = getStorage,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (body.confirmation !== 'DELETE ASSIGNMENT' || !validId(body.assignment_id)) {
    return response.status(400).json({error: 'invalid_confirmation'});
  }
  const firestore = databaseFactory();
  const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
  try {
    const [snapshot, actor] = await Promise.all([
      assignmentRef.get(), firestore.collection('users').doc(uid).get(),
    ]);
    if (!snapshot.exists) return response.status(200).json({deleted: true, already_deleted: true});
    const data = snapshot.data();
    if (!actor.exists || actor.get('role') !== 'Teacher' || data.teacher_id !== uid) {
      return response.status(403).json({error: 'forbidden'});
    }
    await assignmentRef.set({
      deletion_state: 'deleting', deletion_requested_by: uid,
      deletion_requested_at: FieldValue.serverTimestamp(),
    }, {merge: true});
    await cascadeAssignment({firestore, storage: storageFactory(), assignmentRef, assignmentData: data});
    return response.status(200).json({deleted: true});
  } catch (error) {
    console.error('Permanent Assignment deletion failed', error);
    return response.status(503).json({error: 'delete_failed'});
  }
}

async function permanentDeleteClassroomHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
  storageFactory = getStorage,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (body.confirmation !== 'DELETE CLASSROOM' || !validId(body.group_id)) {
    return response.status(400).json({error: 'invalid_confirmation'});
  }
  const firestore = databaseFactory();
  const groupRef = firestore.collection('groups').doc(body.group_id);
  try {
    const [groupSnapshot, actor] = await Promise.all([
      groupRef.get(), firestore.collection('users').doc(uid).get(),
    ]);
    if (!groupSnapshot.exists) return response.status(200).json({deleted: true, already_deleted: true});
    const group = groupSnapshot.data();
    if (!actor.exists || actor.get('role') !== 'Teacher' || group.teacher_id !== uid) {
      return response.status(403).json({error: 'forbidden'});
    }
    await groupRef.set({
      deletion_state: 'deleting', deletion_requested_by: uid,
      deletion_requested_at: FieldValue.serverTimestamp(),
    }, {merge: true});
    const assignmentSnapshot = await firestore.collection('group_assignments')
      .where('group_id', '==', body.group_id).get();
    for (const assignment of assignmentSnapshot.docs) {
      await assignment.ref.set({deletion_state: 'deleting'}, {merge: true});
      await cascadeAssignment({
        firestore, storage: storageFactory(), assignmentRef: assignment.ref,
        assignmentData: assignment.data(),
      });
    }
    await deleteQueryDocuments(firestore, groupRef.collection('announcements'));
    await deleteQueryDocuments(
      firestore,
      firestore.collection('assignment_attempts').where('group_id', '==', body.group_id),
    );
    const deletedMemberships = await firestore.collection('group_memberships')
      .where('group_id', '==', body.group_id).get();
    for (const membershipDoc of deletedMemberships.docs) {
      const membership = membershipDoc.data();
      const traineeId = membership.trainee_id;
      if (!validId(traineeId)) continue;
      const accessRef = firestore.collection('classroom_teacher_access')
        .doc(`${uid}_${traineeId}`);
      const access = await accessRef.get();
      if (!access.exists || access.get('group_id') !== body.group_id) continue;
      const alternatives = await firestore.collection('group_memberships')
        .where('trainee_id', '==', traineeId).get();
      const replacement = alternatives.docs.find((candidate) => {
        const data = candidate.data();
        return data.group_id !== body.group_id && data.teacher_id === uid &&
          data.status === 'approved';
      });
      if (replacement) {
        await accessRef.set({
          teacher_id: uid,
          trainee_id: traineeId,
          group_id: replacement.get('group_id'),
          schema_version: 1,
          updated_at: FieldValue.serverTimestamp(),
        }, {merge: true});
      } else {
        await accessRef.delete();
      }
    }
    await deleteQueryDocuments(
      firestore,
      firestore.collection('classroom_teacher_access')
        .where('group_id', '==', body.group_id),
    );
    await deleteQueryDocuments(
      firestore,
      firestore.collection('group_memberships').where('group_id', '==', body.group_id),
    );
    if (validId(group.invite_code)) {
      await firestore.collection('group_invites').doc(group.invite_code).delete();
    }
    await deleteStoragePrefix(storageFactory(), `classroom_media/${uid}/${body.group_id}/`);
    await groupRef.delete();
    return response.status(200).json({deleted: true});
  } catch (error) {
    console.error('Permanent Classroom deletion failed', error);
    return response.status(503).json({error: 'delete_failed'});
  }
}

function attemptStateId(assignmentId, traineeId) {
  return `${assignmentId}__${traineeId}`;
}

// Overrides are private, assignment-scoped projections.  Never trust a
// client-supplied deadline or an override whose immutable identity disagrees
// with the parent assignment.
async function effectiveAssignmentDueAt(transaction, assignmentRef, assignment, traineeId) {
  const base = assignment.due_at || null;
  const override = await transaction.get(
    assignmentRef.collection('assignment_deadline_overrides').doc(traineeId),
  );
  if (!override.exists) return base;
  const data = override.data();
  if (!data || data.assignment_id !== assignmentRef.id ||
      data.group_id !== assignment.group_id || data.teacher_id !== assignment.teacher_id ||
      data.trainee_id !== traineeId || !(data.due_at instanceof Timestamp) ||
      (base && data.due_at.toMillis() <= base.toMillis())) return base;
  return data.due_at;
}

async function reserveTeacherActivityAttemptHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (!validId(body.assignment_id) || !validId(body.request_id)) {
    return response.status(400).json({error: 'invalid_payload'});
  }
  const firestore = databaseFactory();
  try {
    const result = await firestore.runTransaction(async (transaction) => {
      const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
      const stateRef = firestore.collection('assignment_attempt_states')
        .doc(attemptStateId(body.assignment_id, uid));
      const userRef = firestore.collection('users').doc(uid);
      const [assignmentSnapshot, stateSnapshot, userSnapshot] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(stateRef), transaction.get(userRef),
      ]);
      if (!assignmentSnapshot.exists) { const error = new Error('not_found'); error.code = 'not_found'; throw error; }
      const assignment = assignmentSnapshot.data();
      if (!userSnapshot.exists || userSnapshot.get('role') !== 'Trainee' ||
          userSnapshot.get('lifecycle_state') === 'deleting' ||
          !assignmentIsPublished(assignment) || assignment.deletion_state === 'deleting' ||
          !validActivityAssessment(assignment.activity_assessment, assignment.max_score)) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const membershipRef = firestore.collection('group_memberships')
        .doc(`${assignment.group_id}_${uid}`);
      const membership = await transaction.get(membershipRef);
      if (!membership.exists || membership.get('status') !== 'approved' ||
          membership.get('teacher_id') !== assignment.teacher_id ||
          membership.get('group_id') !== assignment.group_id) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      if (assignment.audience_type !== 'entire_class') {
        const recipient = await transaction.get(
          assignmentRef.collection('assignment_recipients').doc(uid),
        );
        if (!assignmentAudienceAllows(assignment, uid, recipient.data(), body.assignment_id)) {
          const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
        }
      }
      const now = Timestamp.now();
      const effectiveDueAt = await effectiveAssignmentDueAt(
        transaction, assignmentRef, assignment, uid,
      );
      if (effectiveDueAt && now.toMillis() > effectiveDueAt.toMillis()) {
        const error = new Error('deadline_passed'); error.code = 'deadline_passed'; throw error;
      }
      const state = stateSnapshot.exists ? stateSnapshot.data() : {};
      if (state.graded === true || assignment.grading_locked === true) {
        const error = new Error('graded'); error.code = 'graded'; throw error;
      }
      if (state.active_attempt_id) {
        if (state.active_request_id === body.request_id) {
          return {attemptId: state.active_attempt_id, reused: true};
        }
        const error = new Error('attempt_in_progress'); error.code = 'attempt_in_progress'; throw error;
      }
      const consumed = Number.isInteger(state.consumed_count) ? state.consumed_count : 0;
      const policy = assignmentAttemptPolicy(assignment);
      if (policy.type === 'finite' && consumed >= policy.maximum_attempts) {
        const error = new Error('attempts_exhausted'); error.code = 'attempts_exhausted'; throw error;
      }
      const ordinal = (Number.isInteger(state.next_ordinal) ? state.next_ordinal : consumed) + 1;
      const attemptId = `activity_${body.assignment_id}_${uid}_${ordinal}`;
      const attemptRef = firestore.collection('assignment_attempts').doc(attemptId);
      transaction.create(attemptRef, {
        trainee_id: uid, teacher_id: assignment.teacher_id, group_id: assignment.group_id,
        assignment_id: body.assignment_id, movement_id: assignment.movement_id,
        revision_id: assignment.revision_id, origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed', attempt_kind: 'teacher_review_submission',
        status: 'in_progress', awards_global_xp: false, created_at: now,
        attempt_number: ordinal, reservation_request_id: body.request_id,
        assignment_configuration_revision: assignment.configuration_revision,
        activity_assessment_snapshot: assignment.activity_assessment,
      });
      transaction.set(stateRef, {
        assignment_id: body.assignment_id, trainee_id: uid,
        teacher_id: assignment.teacher_id, group_id: assignment.group_id,
        consumed_count: consumed, next_ordinal: ordinal,
        active_attempt_id: attemptId, active_request_id: body.request_id,
        active_consumed: false, graded: false, updated_at: now,
      }, {merge: true});
      return {attemptId, reused: false};
    });
    const attempt = await firestore.collection('assignment_attempts').doc(result.attemptId).get();
    return response.status(200).json({
      attempt: {id: attempt.id, ...assignmentJsonValue(attempt.data())}, reused: result.reused,
    });
  } catch (error) {
    const known = ['not_found', 'forbidden', 'deadline_passed', 'graded', 'attempt_in_progress', 'attempts_exhausted'];
    if (known.includes(error.code)) {
      return response.status(error.code === 'forbidden' ? 403 : 409).json({error: error.code});
    }
    console.error('Teacher Activity attempt reservation failed', error);
    return response.status(503).json({error: 'unavailable'});
  }
}

async function consumeTeacherActivityAttemptHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (!uid || !validId(body.assignment_id) || !validId(body.attempt_id)) {
    return response.status(uid ? 400 : 401).json({error: uid ? 'invalid_payload' : 'unauthenticated'});
  }
  const firestore = databaseFactory();
  try {
    await firestore.runTransaction(async (transaction) => {
      const assignmentRef = firestore.collection('group_assignments')
        .doc(body.assignment_id);
      const stateRef = firestore.collection('assignment_attempt_states')
        .doc(attemptStateId(body.assignment_id, uid));
      const attemptRef = firestore.collection('assignment_attempts').doc(body.attempt_id);
      const [assignmentSnapshot, stateSnapshot, attemptSnapshot] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(stateRef), transaction.get(attemptRef),
      ]);
      if (!assignmentSnapshot.exists || !stateSnapshot.exists || !attemptSnapshot.exists ||
          stateSnapshot.get('active_attempt_id') !== body.attempt_id ||
          attemptSnapshot.get('trainee_id') !== uid ||
          attemptSnapshot.get('assignment_id') !== body.assignment_id) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      if (attemptSnapshot.get('recording_started_at')) return;
      const assignment = assignmentSnapshot.data();
      const attempt = attemptSnapshot.data();
      if (!assignmentIsPublished(assignment) || assignment.deletion_state === 'deleting' ||
          stateSnapshot.get('graded') === true || assignment.grading_locked === true ||
          !validActivityAssessment(assignment.activity_assessment, assignment.max_score)) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const now = Timestamp.now();
      const effectiveDueAt = await effectiveAssignmentDueAt(
        transaction, assignmentRef, assignment, uid,
      );
      if (effectiveDueAt && now.toMillis() > effectiveDueAt.toMillis()) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const membership = await transaction.get(
        firestore.collection('group_memberships').doc(`${assignment.group_id}_${uid}`),
      );
      if (!membership.exists || membership.get('status') !== 'approved' ||
          membership.get('teacher_id') !== assignment.teacher_id) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      if (assignment.audience_type !== 'entire_class') {
        const recipient = await transaction.get(assignmentRef
          .collection('assignment_recipients').doc(uid));
        if (!assignmentAudienceAllows(assignment, uid, recipient.data(), body.assignment_id)) {
          const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
        }
      }
      const consumed = stateSnapshot.get('consumed_count') || 0;
      transaction.update(attemptRef, {recording_started_at: now});
      transaction.update(stateRef, {
        consumed_count: consumed + 1, active_consumed: true, updated_at: now,
      });
    });
    return response.status(200).json({consumed: true});
  } catch (error) {
    if (error.code === 'forbidden') return response.status(403).json({error: 'forbidden'});
    return response.status(503).json({error: 'unavailable'});
  }
}

async function abandonTeacherActivityAttemptHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (!uid || !validId(body.assignment_id) || !validId(body.attempt_id)) {
    return response.status(uid ? 400 : 401).json({error: uid ? 'invalid_payload' : 'unauthenticated'});
  }
  const firestore = databaseFactory();
  try {
    const result = await firestore.runTransaction(async (transaction) => {
      const stateRef = firestore.collection('assignment_attempt_states')
        .doc(attemptStateId(body.assignment_id, uid));
      const attemptRef = firestore.collection('assignment_attempts').doc(body.attempt_id);
      const [stateSnapshot, attemptSnapshot] = await Promise.all([
        transaction.get(stateRef), transaction.get(attemptRef),
      ]);
      if (!stateSnapshot.exists || stateSnapshot.get('active_attempt_id') !== body.attempt_id) {
        return {alreadyReleased: true};
      }
      if (!attemptSnapshot.exists || attemptSnapshot.get('trainee_id') !== uid ||
          attemptSnapshot.get('assignment_id') !== body.assignment_id ||
          !attemptSnapshot.get('activity_assessment_snapshot')) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const now = Timestamp.now();
      transaction.update(attemptRef, {
        status: 'draft',
        abandoned_at: now,
      });
      transaction.update(stateRef, {
        active_attempt_id: FieldValue.delete(),
        active_request_id: FieldValue.delete(),
        active_consumed: FieldValue.delete(),
        updated_at: now,
      });
      return {alreadyReleased: false};
    });
    return response.status(200).json({released: true, already_released: result.alreadyReleased});
  } catch (error) {
    if (error.code === 'forbidden') return response.status(403).json({error: 'forbidden'});
    console.error('Teacher Activity attempt release failed', error);
    return response.status(503).json({error: 'unavailable'});
  }
}

async function updateTeacherActivityAssignmentHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  const title = boundedText(body.display_title, 80);
  const instructions = boundedText(body.display_instructions, 2000);
  const safety = body.display_safety_guidance == null || body.display_safety_guidance === ''
    ? null : boundedText(body.display_safety_guidance, 1000);
  const topic = body.topic == null || body.topic === '' ? null : boundedText(body.topic, 80);
  const audienceType = body.audience_type;
  const recipientIds = Array.isArray(body.recipient_ids)
    ? [...new Set(body.recipient_ids.map((value) => String(value).trim()))]
    : [];
  const maximum = body.activity_assessment?.rubric?.maximum_score;
  const requiredProp = body.allowed_prop;
  if (!validId(body.assignment_id) || !Number.isInteger(body.expected_configuration_revision) ||
      body.expected_configuration_revision < 1 || !title || !instructions ||
      (body.display_safety_guidance && !safety) || (body.topic && !topic) ||
      !['entire_class', 'selected_students', 'individual_student'].includes(audienceType) ||
      (audienceType === 'entire_class' && recipientIds.length !== 0) ||
      (audienceType === 'individual_student' && recipientIds.length !== 1) ||
      (audienceType === 'selected_students' && recipientIds.length < 1) ||
      recipientIds.some((id) => !validId(id)) ||
      !['bottle', 'shaker', 'bottle_and_shaker'].includes(requiredProp) ||
      !Number.isInteger(maximum) || maximum < 1 || maximum > 100 ||
      !validAssignmentAttemptPolicy(body.attempt_policy) ||
      !validActivityAssessment(body.activity_assessment, maximum)) {
    return response.status(400).json({error: 'invalid_payload'});
  }
  let dueAt = null;
  if (body.due_at != null) {
    const date = new Date(body.due_at);
    if (Number.isNaN(date.getTime())) return response.status(400).json({error: 'invalid_due_at'});
    dueAt = Timestamp.fromDate(date);
  }
  const firestore = databaseFactory();
  const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
  try {
    const recipientSnapshot = await assignmentRef
      .collection('assignment_recipients').get();
    const result = await firestore.runTransaction(async (transaction) => {
      const assignmentSnapshot = await transaction.get(assignmentRef);
      if (!assignmentSnapshot.exists) { const error = new Error('not_found'); error.code = 'not_found'; throw error; }
      const assignment = assignmentSnapshot.data();
      if (assignment.teacher_id !== uid || assignment.origin !== 'teacher_created' ||
          assignment.assessment_mode !== 'teacher_reviewed' ||
          !['draft', 'scheduled', 'active'].includes(assignment.status) ||
          assignment.deletion_state === 'deleting' ||
          (assignment.configuration_revision || 1) !== body.expected_configuration_revision) {
        const error = new Error('conflict'); error.code = 'conflict'; throw error;
      }
      const currentStates = await transaction.get(
        firestore.collection('assignment_attempt_states')
          .where('assignment_id', '==', body.assignment_id),
      );
      for (const currentState of currentStates.docs) {
        const consumed = currentState.get('consumed_count') || 0;
        if (body.attempt_policy.type === 'finite' &&
            consumed > body.attempt_policy.maximum_attempts) {
          const error = new Error('attempt_limit_conflict'); error.code = 'attempt_limit_conflict'; throw error;
        }
      }
      for (const traineeId of recipientIds) {
        const membership = await transaction.get(
          firestore.collection('group_memberships').doc(`${assignment.group_id}_${traineeId}`),
        );
        if (!membership.exists || membership.get('status') !== 'approved' ||
            membership.get('teacher_id') !== uid) {
          const error = new Error('invalid_recipient'); error.code = 'invalid_recipient'; throw error;
        }
      }
      const now = Timestamp.now();
      transaction.update(assignmentRef, {
        display_title: title, display_instructions: instructions,
        display_safety_guidance: safety || FieldValue.delete(),
        topic: topic || FieldValue.delete(), due_at: dueAt || FieldValue.delete(),
        audience_type: audienceType, activity_assessment: body.activity_assessment,
        attempt_policy: body.attempt_policy,
        allowed_prop: requiredProp,
        max_score: maximum,
        configuration_revision: body.expected_configuration_revision + 1,
        updated_at: now,
      });
      const nextRecipients = new Set(recipientIds);
      for (const existing of recipientSnapshot.docs) {
        if (!nextRecipients.has(existing.id)) transaction.delete(existing.ref);
      }
      for (const traineeId of recipientIds) {
        transaction.set(assignmentRef.collection('assignment_recipients').doc(traineeId), {
          assignment_id: body.assignment_id, group_id: assignment.group_id,
          teacher_id: uid, trainee_id: traineeId, audience_type: audienceType,
          schema_version: 1, created_at: now,
        });
      }
      const responseAssignment = {
        ...assignment, display_title: title, display_instructions: instructions,
        ...(safety ? {display_safety_guidance: safety} : {}),
        ...(topic ? {topic} : {}), ...(dueAt ? {due_at: dueAt} : {}),
        audience_type: audienceType, activity_assessment: body.activity_assessment,
        attempt_policy: body.attempt_policy,
        allowed_prop: requiredProp,
        max_score: maximum,
        configuration_revision: body.expected_configuration_revision + 1,
        updated_at: now,
      };
      if (!safety) delete responseAssignment.display_safety_guidance;
      if (!topic) delete responseAssignment.topic;
      if (!dueAt) delete responseAssignment.due_at;
      return responseAssignment;
    });
    return response.status(200).json({
      assignment: {id: body.assignment_id, ...assignmentJsonValue(result)},
      recipient_ids: recipientIds,
    });
  } catch (error) {
    const known = ['not_found', 'conflict', 'attempt_limit_conflict', 'invalid_recipient'];
    if (known.includes(error.code)) return response.status(409).json({error: error.code});
    console.error('Teacher Activity Assignment update failed', error);
    return response.status(503).json({error: 'unavailable'});
  }
}

async function gradeTeacherActivityAttemptHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  const feedback = body.feedback == null || body.feedback === ''
    ? null : boundedText(body.feedback, 1000);
  if (!validId(body.attempt_id) || !body.criterion_scores ||
      typeof body.criterion_scores !== 'object' ||
      (body.feedback && !feedback)) {
    return response.status(400).json({error: 'invalid_payload'});
  }
  const firestore = databaseFactory();
  const attemptRef = firestore.collection('assignment_attempts').doc(body.attempt_id);
  try {
    await firestore.runTransaction(async (transaction) => {
      const attemptSnapshot = await transaction.get(attemptRef);
      if (!attemptSnapshot.exists) { const error = new Error('not_found'); error.code = 'not_found'; throw error; }
      const attempt = attemptSnapshot.data();
      if (attempt.teacher_id !== uid || attempt.status !== 'submitted' ||
          !attempt.activity_assessment_snapshot) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const stateRef = firestore.collection('assignment_attempt_states')
        .doc(attemptStateId(attempt.assignment_id, attempt.trainee_id));
      const state = await transaction.get(stateRef);
      if (!state.exists || state.get('latest_submission_id') !== body.attempt_id ||
          state.get('graded') === true) {
        const error = new Error('not_current'); error.code = 'not_current'; throw error;
      }
      const criteria = attempt.activity_assessment_snapshot.rubric?.criteria;
      if (!Array.isArray(criteria)) { const error = new Error('invalid_snapshot'); error.code = 'invalid_snapshot'; throw error; }
      const submittedIds = Object.keys(body.criterion_scores);
      if (submittedIds.length !== criteria.length) {
        const error = new Error('invalid_scores'); error.code = 'invalid_scores'; throw error;
      }
      let total = 0;
      for (const criterion of criteria) {
        const score = body.criterion_scores[criterion.id];
        if (!Number.isInteger(score) || score < 0 || score > criterion.maximum_points) {
          const error = new Error('invalid_scores'); error.code = 'invalid_scores'; throw error;
        }
        total += score;
      }
      const now = Timestamp.now();
      transaction.update(attemptRef, {
        status: 'checked', criterion_scores: body.criterion_scores,
        grade_score: total,
        grade_max_score: attempt.activity_assessment_snapshot.rubric.maximum_score,
        checked_at: now, review_updated_at: now,
        review_revision: (attempt.review_revision || 0) + 1,
        review_feedback: feedback || FieldValue.delete(),
      });
      transaction.set(stateRef, {graded: true, updated_at: now}, {merge: true});
    });
    const updated = await attemptRef.get();
    return response.status(200).json({
      attempt: {id: updated.id, ...assignmentJsonValue(updated.data())},
    });
  } catch (error) {
    const known = ['not_found', 'forbidden', 'not_current', 'invalid_snapshot', 'invalid_scores'];
    if (known.includes(error.code)) {
      return response.status(error.code === 'forbidden' ? 403 : 409).json({error: error.code});
    }
    console.error('Teacher Activity grading failed', error);
    return response.status(503).json({error: 'unavailable'});
  }
}

function sanitizedAssignment(document) {
  return {
    ...assignmentJsonValue(document.data()),
    id: document.id,
  };
}

async function enforceSearchRateLimit(uid) {
  const firestore = getFirestore();
  const ref = firestore.collection('chat_search_rate_limits').doc(uid);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const lastRequestMs = snapshot.get('last_request_ms') || 0;
    const now = Date.now();
    if (isSearchRateLimited(lastRequestMs, now)) {
      const error = new Error('rate-limited');
      error.code = 'rate-limited';
      throw error;
    }
    transaction.set(ref, {
      last_request_ms: now,
      updated_at: FieldValue.serverTimestamp(),
    });
  });
}

exports.searchChatUsers = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 15},
  async (request, response) => {
    setCors(response);
    if (request.method === 'OPTIONS') {
      response.status(204).send('');
      return;
    }
    if (request.method !== 'GET') {
      response.status(405).json({error: 'method_not_allowed'});
      return;
    }
    const uid = await authenticatedUid(request);
    if (!uid) {
      response.status(401).json({error: 'unauthenticated'});
      return;
    }
    const search = validateSearchQuery(request.query.q);
    if (!search.valid) {
      response.status(400).json({error: 'invalid_query'});
      return;
    }
    try {
      await enforceSearchRateLimit(uid);
    } catch (error) {
      if (error.code === 'rate-limited') {
        response.status(429).json({error: 'rate_limited'});
        return;
      }
      response.status(503).json({error: 'unavailable'});
      return;
    }

    const firestore = getFirestore();
    let documents = [];
    if (search.emailShaped) {
      try {
        const authUser = await getAuth().getUserByEmail(search.raw.toLowerCase());
        const [profile, directory] = await Promise.all([
          firestore.collection('users').doc(authUser.uid).get(),
          firestore.collection('chat_user_directory').doc(authUser.uid).get(),
        ]);
        if (profile.exists &&
            isActiveChatProfile(profile.data()) &&
            normalizeSearchText(profile.get('email')) === search.normalized &&
            directory.exists) {
          documents = [directory];
        }
      } catch (error) {
        if (error.code !== 'auth/user-not-found') {
          response.status(503).json({error: 'unavailable'});
          return;
        }
      }
    } else {
      const snapshot = await firestore
        .collection('chat_user_directory')
        .where('search_prefixes', 'array-contains', search.normalized)
        .limit(SEARCH_LIMIT + 1)
        .get();
      documents = snapshot.docs;
    }

    const results = sanitizeDirectoryDocuments(uid, documents);
    response.status(200).json({results});
  },
);

async function listTraineeAssignmentsHandler(
  request,
  response,
  {authenticate = authenticatedUid, databaseFactory = getFirestore} = {},
) {
  setCors(response);
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }
  if (request.method !== 'GET') {
    response.status(405).json({error: 'method_not_allowed'});
    return;
  }
  const uid = await authenticate(request);
  if (!uid) {
    response.status(401).json({error: 'unauthenticated'});
    return;
  }
  const requestedGroupId = String(request.query.group_id || '').trim();
  if (requestedGroupId &&
      !/^[A-Za-z0-9_-]{1,128}$/.test(requestedGroupId)) {
    response.status(400).json({error: 'invalid_group'});
    return;
  }

  try {
    const firestore = databaseFactory();
    const memberships = await firestore
      .collection('group_memberships')
      .where('trainee_id', '==', uid)
      .get();
    const approvedMemberships = memberships.docs
      .map((document) => ({id: document.id, data: document.data()}))
      .filter(({id, data}) => data.trainee_id === uid &&
        data.status === 'approved' &&
        typeof data.group_id === 'string' &&
        typeof data.teacher_id === 'string' &&
        /^[A-Za-z0-9_-]{1,128}$/.test(data.group_id) &&
        /^[A-Za-z0-9_-]{1,128}$/.test(data.teacher_id) &&
        id === `${data.group_id}_${uid}`)
      .map(({data}) => data);
    const teacherByGroupId = new Map(
      approvedMemberships.map((data) => [data.group_id, data.teacher_id]),
    );
    let groupIds = [...teacherByGroupId.keys()];
    if (requestedGroupId) {
      groupIds = groupIds.includes(requestedGroupId) ? [requestedGroupId] : [];
    }
    if (groupIds.length === 0) {
      response.status(200).json({assignments: []});
      return;
    }

    const documents = [];
    for (let index = 0; index < groupIds.length; index += 30) {
      const chunk = groupIds.slice(index, index + 30);
      let query = firestore.collection('group_assignments');
      query = chunk.length === 1
        ? query.where('group_id', '==', chunk[0])
        : query.where('group_id', 'in', chunk);
      const snapshot = await query.get();
      documents.push(...snapshot.docs);
    }
    // Canonical targeted assignments never carry recipient identities. The
    // assignments above are already scoped to the trainee's approved classes,
    // so direct-read only this trainee's projection under each known targeted
    // assignment. This avoids a collection-group index dependency at runtime.
    const targetedIds = new Set();
    for (const assignmentDocument of documents) {
      const assignment = assignmentDocument.data();
      if (!assignment || typeof assignment !== 'object' ||
          !Object.hasOwn(assignment, 'audience_type') ||
          assignment.audience_type === 'entire_class') continue;
      const recipientDocument = await assignmentDocument.ref
        .collection('assignment_recipients').doc(uid).get();
      if (!recipientDocument.exists) continue;
      const recipient = recipientDocument.data();
      if (teacherByGroupId.get(assignment.group_id) !== assignment.teacher_id ||
          !assignmentAudienceAllows(
            assignment, uid, recipient, assignmentDocument.id,
          )) continue;
      targetedIds.add(assignmentDocument.id);
    }
    const uniqueDocuments = [...new Map(documents.map((document) => [document.id, document])).values()];
    const assignments = await Promise.all(uniqueDocuments
      .filter((document) => {
        const data = document.data();
        return teacherByGroupId.get(data.group_id) === data.teacher_id &&
          (!data.status || data.status === 'active' ||
            (data.status === 'scheduled' && data.publish_at &&
              Timestamp.now().toMillis() >= data.publish_at.toMillis())) &&
          (assignmentAudienceAllows(data, uid, null, document.id) ||
            targetedIds.has(document.id));
      })
      .map(async (document) => {
        const assignment = document.data();
        const value = sanitizedAssignment(document);
        const override = await document.ref
          .collection('assignment_deadline_overrides').doc(uid).get();
        const deadline = override.exists ? override.data() : null;
        if (deadline && deadline.assignment_id === document.id &&
            deadline.group_id === assignment.group_id &&
            deadline.teacher_id === assignment.teacher_id &&
            deadline.trainee_id === uid && deadline.due_at instanceof Timestamp &&
            (!assignment.due_at || deadline.due_at.toMillis() > assignment.due_at.toMillis())) {
          value.due_at = deadline.due_at;
        }
        return value;
      }));
    response.status(200).json({assignments});
  } catch (_) {
    response.status(503).json({error: 'unavailable'});
  }
}

function validId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function boundedText(value, max, {required = true} = {}) {
  if (value == null && !required) return null;
  return typeof value === 'string' && value.trim().length > 0 &&
    value.trim().length <= max ? value.trim() : null;
}

function materialMaximumBytes(type) {
  return type === 'pdf' ? ACTIVITY_MATERIAL_LIMITS.pdfBytes :
    type === 'image' ? ACTIVITY_MATERIAL_LIMITS.imageBytes :
      type === 'video' ? ACTIVITY_MATERIAL_LIMITS.videoBytes : 0;
}

function materialAccessId(assignmentId, materialId, userId) {
  return `${assignmentId}__${materialId}__${userId}`;
}

const ACTIVITY_MATERIAL_SAFE_REJECTIONS = new Set([
  'invalid_size', 'invalid_content', 'expired', 'material_unavailable', 'upload_failed',
]);

function safeActivityMaterialRejectionReason(value) {
  return ACTIVITY_MATERIAL_SAFE_REJECTIONS.has(value) ? value : 'upload_failed';
}

function stagingPathFor(teacherId, assignmentId, uploadId) {
  return `activity_material_staging/${teacherId}/${assignmentId}/${uploadId}`;
}

function finalMaterialPathFor(assignmentId, materialId) {
  return `activity_learning_materials/${assignmentId}/${materialId}`;
}

function timestampsOlderThan(value, milliseconds) {
  return value && typeof value.toMillis === 'function' &&
    value.toMillis() <= Date.now() - milliseconds;
}

// This is intentionally byte-oriented. The client-declared MIME type and any
// filename never influence the canonical content type written to Firestore or
// Storage. It is not a full media parser; the narrow signatures below reject
// malformed and type-confused uploads before publication.
function detectActivityMaterialContent(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) return null;
  if (buffer.length >= 5 && buffer.subarray(0, 5).toString('ascii') === '%PDF-') {
    return {type: 'pdf', contentType: 'application/pdf'};
  }
  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  )) return {type: 'image', contentType: 'image/png'};
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return {type: 'image', contentType: 'image/jpeg'};
  }
  // ISO base media files (including MP4) start with a box length followed by
  // `ftyp`. Only a short known MP4 brand allowlist is accepted; this remains
  // signature-level validation, not an attempt to decode untrusted video.
  const majorBrand = buffer.length >= 12 ? buffer.subarray(8, 12).toString('ascii') : '';
  if (buffer.length >= 16 && buffer.subarray(4, 8).toString('ascii') === 'ftyp' &&
      ['isom', 'iso2', 'avc1', 'mp41', 'mp42', 'M4V '].includes(majorBrand)) {
    return {type: 'video', contentType: 'video/mp4'};
  }
  return null;
}

function normalizeActivityMaterialLink(value) {
  const raw = boundedText(value, ACTIVITY_MATERIAL_LIMITS.linkLength);
  if (!raw) return null;
  try {
    const parsed = new URL(raw);
    if (!['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname ||
        parsed.username || parsed.password) return null;
    parsed.hash = '';
    return parsed.toString();
  } catch (_) {
    return null;
  }
}

function materialStageMatchesObject(stage, objectName) {
  return stage && stage.schema_version === 1 &&
    stage.state && ['staging', 'validating'].includes(stage.state) &&
    validId(stage.upload_id) && validId(stage.material_id) &&
    validId(stage.assignment_id) && validId(stage.owner_teacher_id) &&
    ACTIVITY_MATERIAL_TYPES.has(stage.type) && stage.type !== 'link' &&
    typeof stage.staging_path === 'string' && stage.staging_path === objectName &&
    stage.staging_path === stagingPathFor(
      stage.owner_teacher_id, stage.assignment_id, stage.upload_id,
    ) && Number.isInteger(stage.declared_size_bytes) &&
    stage.declared_size_bytes > 0 &&
    stage.declared_size_bytes <= materialMaximumBytes(stage.type);
}

async function deleteMaterialAccessForAssignment(firestore, assignmentId) {
  return deleteQueryDocuments(
    firestore,
    firestore.collection('activity_material_access').where('assignment_id', '==', assignmentId),
  );
}

// Removal must not invalidate the complete assignment projection. In
// particular, access to material B must remain usable while material A is
// being deleted or retried.
async function deleteMaterialAccessForMaterial(firestore, assignmentId, materialId) {
  return deleteQueryDocuments(
    firestore,
    firestore.collection('activity_material_access')
      .where('assignment_id', '==', assignmentId)
      .where('material_id', '==', materialId),
  );
}

async function synchronizeRemainingMaterialAccess(firestore, assignmentRef) {
  const [materials, access] = await Promise.all([
    assignmentRef.collection('learning_materials').where('status', '==', 'ready').get(),
    firestore.collection('activity_material_access').where('assignment_id', '==', assignmentRef.id).get(),
  ]);
  const readyIds = new Set(materials.docs.map((document) => document.id));
  await Promise.all(access.docs
    .filter((document) => !readyIds.has(document.get('material_id')))
    .map((document) => document.ref.delete()));
}

function materialReconciliationStateRef(firestore) {
  return firestore.collection('activity_material_reconciliation_state').doc('v1');
}

function materialAccessStateRef(firestore, assignmentId) {
  return firestore.collection('activity_material_access_state').doc(assignmentId);
}

function revokedMaterialIds(state) {
  return Array.isArray(state?.revoked_material_ids)
    ? state.revoked_material_ids.filter(validId) : [];
}

// This is committed with the material's transition to deleting, before any
// Storage delete. Storage rules consult the same state document as projection
// generation, keeping the rule lookup budget at two documents.
async function revokeActivityMaterialAccess(firestore, assignmentId, materialId, transaction) {
  const stateRef = materialAccessStateRef(firestore, assignmentId);
  const update = async (activeTransaction) => {
    const state = await activeTransaction.get(stateRef);
    const revoked = new Set(revokedMaterialIds(state.exists ? state.data() : null));
    revoked.add(materialId);
    // Retained materials include deleting ones, so this server-owned list is
    // bounded by maxPerAssignment until each confirmed deletion is cleaned up.
    activeTransaction.set(stateRef, {
      assignment_id: assignmentId,
      revoked_material_ids: [...revoked],
      schema_version: 1,
      updated_at: Timestamp.now(),
    }, {merge: true});
  };
  if (transaction) return update(transaction);
  return firestore.runTransaction(update);
}

// Only call after the final object deletion has succeeded and its canonical
// metadata is gone. Retaining a marker on failure is safer than restoring a
// potentially stale projection.
async function clearActivityMaterialAccessRevocation(firestore, assignmentId, materialId) {
  const stateRef = materialAccessStateRef(firestore, assignmentId);
  return firestore.runTransaction(async (transaction) => {
    const state = await transaction.get(stateRef);
    if (!state.exists) return;
    const current = revokedMaterialIds(state.data());
    const revoked = current.filter((id) => id !== materialId);
    if (revoked.length === current.length) return;
    transaction.set(stateRef, {
      revoked_material_ids: revoked,
      updated_at: Timestamp.now(),
    }, {merge: true});
  });
}

async function hasReadyActivityMaterialAccess(
    firestore, assignmentId, materialId, userId) {
  const [access, state] = await Promise.all([
    firestore.collection('activity_material_access')
      .doc(materialAccessId(assignmentId, materialId, userId)).get(),
    materialAccessStateRef(firestore, assignmentId).get(),
  ]);
  return access.exists && state.exists && state.get('state') === 'ready' &&
    access.get('assignment_id') === assignmentId && access.get('material_id') === materialId &&
    access.get('user_id') === userId && access.get('projection_generation') === state.get('generation');
}

async function rejectStagedMaterialRecord(firestore, stage, reason) {
  const materialRef = firestore.collection('group_assignments').doc(stage.assignment_id)
    .collection('learning_materials').doc(stage.material_id);
  await firestore.runTransaction(async (transaction) => {
    const material = await transaction.get(materialRef);
    if (material.exists && material.get('status') === 'staging') {
      transaction.update(materialRef, {
        status: 'rejected', rejection_reason: reason, updated_at: Timestamp.now(),
      });
    }
  });
}

async function markMaterialProjectionSynchronized(firestore, materialRef) {
  await firestore.runTransaction(async (transaction) => {
    const material = await transaction.get(materialRef);
    // Never recreate metadata after a concurrent removal. A missing or
    // deleting material must remain pending only in historical work queues,
    // where reconciliation will ignore it rather than restoring access.
    if (!material.exists || material.get('status') !== 'ready' ||
        material.get('material_id') !== materialRef.id) return;
    transaction.set(materialRef, {
      projection_sync_state: 'ready', projection_synced_at: Timestamp.now(),
    }, {merge: true});
  });
}

async function publishMaterialAccessProjection({
  firestore, stateRef, assignmentRef, assignment, materialRef, generation, eligible, now,
}) {
  const recipients = [...eligible];
  for (let index = 0; index < recipients.length; index += 400) {
    const recipientChunk = recipients.slice(index, index + 400);
    const published = await firestore.runTransaction(async (transaction) => {
      const [state, material] = await Promise.all([
        transaction.get(stateRef), transaction.get(materialRef),
      ]);
      // These reads make a removal transaction conflict with an in-flight
      // publisher. If removal wins, the retried transaction sees its
      // revocation/deleting metadata and cannot recreate usable access.
      if (!state.exists || state.get('generation') !== generation ||
          revokedMaterialIds(state.data()).includes(materialRef.id) ||
          !material.exists || material.get('status') !== 'ready' ||
          material.get('material_id') !== materialRef.id ||
          material.get('assignment_id') !== assignmentRef.id) return false;
      for (const userId of recipientChunk) {
        transaction.set(firestore.collection('activity_material_access')
          .doc(materialAccessId(assignmentRef.id, materialRef.id, userId)), {
          assignment_id: assignmentRef.id, material_id: materialRef.id, user_id: userId,
          owner_teacher_id: assignment.teacher_id, projection_generation: generation,
          schema_version: 1, created_at: now,
        });
      }
      return true;
    });
    if (!published) return false;
  }
  return true;
}

// Rebuild rather than incrementally mutate the access projection. A short
// fail-closed gap is preferable to carrying forward a removed recipient. Each
// Storage read uses the per-material projection plus its generation state,
// rather than the assignment/membership/recipient source chain.
async function syncActivityMaterialAccess({firestore, assignmentRef, assignmentData}) {
  // Always take a fresh source snapshot. Trigger payloads may be stale by the
  // time a concurrent audience or membership change starts its own rebuild.
  const assignmentSnapshot = await assignmentRef.get();
  const assignment = assignmentSnapshot.exists ? assignmentSnapshot.data() : null;
  if (!assignment) {
    await deleteMaterialAccessForAssignment(firestore, assignmentRef.id);
    await materialAccessStateRef(firestore, assignmentRef.id).delete();
    return;
  }
  const stateRef = materialAccessStateRef(firestore, assignmentRef.id);
  const {generation, revoked} = await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(stateRef);
    const next = (current.exists && Number.isInteger(current.get('generation'))
      ? current.get('generation') : 0) + 1;
    transaction.set(stateRef, {
      assignment_id: assignmentRef.id, generation: next, state: 'rebuilding',
      schema_version: 1, revoked_material_ids: revokedMaterialIds(
        current.exists ? current.data() : null,
      ), updated_at: Timestamp.now(),
    }, {merge: true});
    return {generation: next, revoked: new Set(revokedMaterialIds(
      current.exists ? current.data() : null,
    ))};
  });
  const materialSnapshot = await assignmentRef.collection('learning_materials')
    .where('status', '==', 'ready').get();
  await deleteMaterialAccessForAssignment(firestore, assignmentRef.id);
  if (materialSnapshot.empty || !validId(assignment.teacher_id) ||
      assignment.deletion_state === 'deleting') {
    await firestore.runTransaction(async (transaction) => {
      const current = await transaction.get(stateRef);
      if (current.exists && current.get('generation') === generation) {
        transaction.set(stateRef, {state: 'ready', updated_at: Timestamp.now()}, {merge: true});
      }
    });
    return;
  }

  const eligible = new Set([assignment.teacher_id]);
  if (assignmentIsPublished(assignment)) {
    if (assignment.audience_type === 'entire_class') {
      const memberships = await firestore.collection('group_memberships')
        .where('group_id', '==', assignment.group_id).get();
      for (const membership of memberships.docs) {
        const data = membership.data();
        if (data.status === 'approved' && data.teacher_id === assignment.teacher_id &&
            validId(data.trainee_id)) eligible.add(data.trainee_id);
      }
    } else if (['selected_students', 'individual_student'].includes(assignment.audience_type)) {
      const recipients = await assignmentRef.collection('assignment_recipients').get();
      for (const recipient of recipients.docs) {
        const data = recipient.data();
        if (!validRecipientProjection(data, assignmentRef.id, recipient.id)) continue;
        const membership = await firestore.collection('group_memberships')
          .doc(`${assignment.group_id}_${recipient.id}`).get();
        if (membership.exists && membership.get('status') === 'approved' &&
            membership.get('teacher_id') === assignment.teacher_id) eligible.add(recipient.id);
      }
    }
  }
  const now = Timestamp.now();
  // A sync that observes a revocation never recreates its projection. If a
  // removal commits after this snapshot, the state revocation remains an
  // immediate rule-level denial until final object deletion is confirmed.
  for (const material of materialSnapshot.docs) {
    if (revoked.has(material.id)) continue;
    await publishMaterialAccessProjection({
      firestore, stateRef, assignmentRef, assignment, materialRef: material.ref,
      generation, eligible, now,
    });
  }
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(stateRef);
    if (current.exists && current.get('generation') === generation) {
      transaction.set(stateRef, {state: 'ready', updated_at: Timestamp.now()}, {merge: true});
    }
  });
}

async function finalizeStagedActivityMaterial(uploadId, {
  databaseFactory = getFirestore,
  storageFactory = getStorage,
} = {}) {
  if (!validId(uploadId)) return {processed: false, reason: 'invalid_upload'};
  const firestore = databaseFactory();
  const stageRef = firestore.collection('activity_material_uploads').doc(uploadId);
  let stage;
  try {
    stage = await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(stageRef);
      if (!snapshot.exists) return null;
      const data = snapshot.data();
      if (data.state === 'ready' || data.state === 'rejected') return null;
      if (!data.expires_at || typeof data.expires_at.toMillis !== 'function' ||
          data.expires_at.toMillis() <= Date.now()) {
        transaction.set(stageRef, {
          state: 'rejected', rejection_reason: 'expired', rejected_at: Timestamp.now(),
        }, {merge: true});
        return {...data, expired: true};
      }
      if (!materialStageMatchesObject(data, data.staging_path)) return null;
      if (data.state === 'validating' && !timestampsOlderThan(
        data.validation_started_at, ACTIVITY_MATERIAL_LIMITS.validationLeaseMs,
      )) return null;
      transaction.update(stageRef, {
        state: 'validating', validation_started_at: Timestamp.now(),
      });
      return data;
    });
  } catch (error) {
    console.error('Activity material validation lease failed', error);
    return {processed: false, reason: 'lease_failed'};
  }
  if (!stage) return {processed: false, reason: 'already_processed'};
  const storage = storageFactory();
  const bucket = storage.bucket();
  const stagedFile = bucket.file(stage.staging_path);
  if (stage.expired) {
    await stagedFile.delete({ignoreNotFound: true}).catch(() => undefined);
    await rejectStagedMaterialRecord(firestore, stage, 'expired').catch(() => undefined);
    return {processed: false, reason: 'expired'};
  }
  try {
    const [buffer] = await stagedFile.download();
    if (buffer.length === 0 || buffer.length !== stage.declared_size_bytes ||
        buffer.length > materialMaximumBytes(stage.type)) {
      throw Object.assign(new Error('invalid_size'), {code: 'invalid_size'});
    }
    const detected = detectActivityMaterialContent(buffer);
    if (!detected || detected.type !== stage.type) {
      throw Object.assign(new Error('invalid_content'), {code: 'invalid_content'});
    }
    const finalPath = finalMaterialPathFor(stage.assignment_id, stage.material_id);
    await bucket.file(finalPath).save(buffer, {
      resumable: false,
      metadata: {
        contentType: detected.contentType,
        metadata: {
          assignment_id: stage.assignment_id,
          material_id: stage.material_id,
          owner_teacher_id: stage.owner_teacher_id,
          schema_version: '1',
        },
      },
    });
    const assignmentRef = firestore.collection('group_assignments').doc(stage.assignment_id);
    const materialRef = assignmentRef.collection('learning_materials').doc(stage.material_id);
    const published = await firestore.runTransaction(async (transaction) => {
      const [assignment, material, currentStage] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(materialRef), transaction.get(stageRef),
      ]);
      if (!assignment.exists || !material.exists || !currentStage.exists ||
          assignment.get('teacher_id') !== stage.owner_teacher_id ||
          assignment.get('deletion_state') === 'deleting' ||
          material.get('status') === 'deleting' ||
          currentStage.get('state') !== 'validating' ||
          !currentStage.get('expires_at') ||
          currentStage.get('expires_at').toMillis() <= Date.now()) return null;
      transaction.update(materialRef, {
        detected_content_type: detected.contentType, size_bytes: buffer.length,
        storage_path: finalPath, status: 'ready', projection_sync_state: 'pending',
        updated_at: Timestamp.now(),
      });
      transaction.set(stageRef, {
        state: 'ready', final_storage_path: finalPath,
        detected_content_type: detected.contentType, validated_size_bytes: buffer.length,
        published_at: Timestamp.now(), terminal_at: Timestamp.now(),
      }, {merge: true});
      return assignment.data();
    });
    if (!published) {
      await bucket.file(finalPath).delete({ignoreNotFound: true});
      throw Object.assign(new Error('material_unavailable'), {code: 'material_unavailable'});
    }
    try {
      await syncActivityMaterialAccess({
        firestore, assignmentRef, assignmentData: published,
      });
      await markMaterialProjectionSynchronized(firestore, materialRef);
    } catch (error) {
      // Publication already committed. Keep the terminal upload state intact
      // and let the dedicated pending-projection pass repair only this
      // material, rather than attempting a duplicate finalization.
      console.error('Activity material access projection sync failed', error);
      return {processed: true, materialId: stage.material_id, projectionPending: true};
    }
    // Cleanup is non-authoritative once publication committed. Retrying a
    // delete must never regress the already-ready stage back to staging.
    await stagedFile.delete({ignoreNotFound: true}).catch(() => undefined);
    return {processed: true, materialId: stage.material_id};
  } catch (error) {
    const rejection = ['invalid_size', 'invalid_content', 'material_unavailable'].includes(error.code);
    if (rejection) {
      await stagedFile.delete({ignoreNotFound: true}).catch(() => undefined);
      await stageRef.set({
        state: 'rejected', rejection_reason: safeActivityMaterialRejectionReason(error.code),
        rejected_at: Timestamp.now(), terminal_at: Timestamp.now(),
      }, {merge: true}).catch(() => undefined);
      await rejectStagedMaterialRecord(firestore, stage, error.code).catch(() => undefined);
    } else {
      // Leave a retryable record. The scheduled reconciler will retry the
      // server-owned operation; no client can promote it to ready.
      await stageRef.set({state: 'staging', last_error: 'publish_failed'}, {merge: true})
        .catch(() => undefined);
    }
    console.error('Activity material validation failed', error);
    return {processed: false, reason: error.code || 'validation_failed'};
  }
}

async function beginActivityMaterialUploadHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  const type = body.type;
  const displayName = boundedText(body.display_name, ACTIVITY_MATERIAL_LIMITS.displayNameLength);
  const declaredContentType = typeof body.declared_content_type === 'string'
    ? body.declared_content_type.toLowerCase().trim() : '';
  if (!validId(body.assignment_id) || !['pdf', 'image', 'video'].includes(type) ||
      !displayName || !ACTIVITY_UPLOAD_CONTENT_TYPES[type].has(declaredContentType) ||
      !Number.isInteger(body.size_bytes) || body.size_bytes < 1 ||
      body.size_bytes > materialMaximumBytes(type)) {
    return response.status(400).json({error: 'invalid_payload'});
  }
  const firestore = databaseFactory();
  const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
  const uploadId = randomUUID();
  const materialId = randomUUID();
  try {
    const result = await firestore.runTransaction(async (transaction) => {
      const userRef = firestore.collection('users').doc(uid);
      const materials = assignmentRef.collection('learning_materials');
      const [assignmentSnapshot, userSnapshot, materialSnapshot] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(userRef), transaction.get(materials),
      ]);
      if (!assignmentSnapshot.exists) { const error = new Error('not_found'); error.code = 'not_found'; throw error; }
      const assignment = assignmentSnapshot.data();
      if (!userSnapshot.exists || userSnapshot.get('role') !== 'Teacher' ||
          assignment.teacher_id !== uid) { const error = new Error('forbidden'); error.code = 'forbidden'; throw error; }
      if (!['draft', 'scheduled', 'active'].includes(assignment.status) ||
          assignment.deletion_state === 'deleting') {
        const error = new Error('assignment_unavailable'); error.code = 'assignment_unavailable'; throw error;
      }
      const retained = materialSnapshot.docs.filter((doc) =>
        !['deleted', 'rejected'].includes(doc.get('status')),
      ).length;
      if (retained >= ACTIVITY_MATERIAL_LIMITS.maxPerAssignment) {
        const error = new Error('material_limit'); error.code = 'material_limit'; throw error;
      }
      const now = Timestamp.now();
      const expiresAt = Timestamp.fromMillis(Date.now() + ACTIVITY_MATERIAL_LIMITS.stagingLifetimeMs);
      const path = stagingPathFor(uid, body.assignment_id, uploadId);
      // Reserve the canonical material ID before Storage receives any bytes.
      // This lets a removal race mark the material deleting, which finalization
      // checks transactionally instead of being able to recreate metadata.
      transaction.create(assignmentRef.collection('learning_materials').doc(materialId), {
        material_id: materialId, assignment_id: body.assignment_id,
        owner_teacher_id: uid, type, display_name: displayName,
        status: 'staging', schema_version: 1, created_at: now, updated_at: now,
      });
      transaction.create(firestore.collection('activity_material_uploads').doc(uploadId), {
        upload_id: uploadId, material_id: materialId, assignment_id: body.assignment_id,
        owner_teacher_id: uid, type, display_name: displayName,
        declared_content_type: declaredContentType, declared_size_bytes: body.size_bytes,
        staging_path: path, state: 'staging', schema_version: 1,
        created_at: now, expires_at: expiresAt,
      });
      return {path, expiresAt};
    });
    return response.status(200).json({
      upload_id: uploadId, material_id: materialId, staging_path: result.path,
      declared_content_type: declaredContentType,
      expires_at: result.expiresAt.toDate().toISOString(),
    });
  } catch (error) {
    if (['not_found', 'forbidden', 'assignment_unavailable', 'material_limit'].includes(error.code)) {
      return response.status(error.code === 'forbidden' ? 403 : 409).json({error: error.code});
    }
    console.error('Activity material upload initialization failed', error);
    return response.status(503).json({error: 'unavailable'});
  }
}

async function addActivityLearningMaterialLinkHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  const displayName = boundedText(body.display_name, ACTIVITY_MATERIAL_LIMITS.displayNameLength);
  const url = normalizeActivityMaterialLink(body.url);
  if (!validId(body.assignment_id) || !displayName || !url) {
    return response.status(400).json({error: 'invalid_payload'});
  }
  const firestore = databaseFactory();
  const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
  const materialId = randomUUID();
  try {
    const assignment = await firestore.runTransaction(async (transaction) => {
      const [assignmentSnapshot, userSnapshot, materials] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(firestore.collection('users').doc(uid)),
        transaction.get(assignmentRef.collection('learning_materials')),
      ]);
      if (!assignmentSnapshot.exists) { const error = new Error('not_found'); error.code = 'not_found'; throw error; }
      if (!userSnapshot.exists || userSnapshot.get('role') !== 'Teacher' ||
          assignmentSnapshot.get('teacher_id') !== uid) { const error = new Error('forbidden'); error.code = 'forbidden'; throw error; }
      if (!['draft', 'scheduled', 'active'].includes(assignmentSnapshot.get('status')) ||
          assignmentSnapshot.get('deletion_state') === 'deleting') {
        const error = new Error('assignment_unavailable'); error.code = 'assignment_unavailable'; throw error;
      }
      if (materials.docs.filter((doc) =>
        !['deleted', 'rejected'].includes(doc.get('status')),
      ).length >=
          ACTIVITY_MATERIAL_LIMITS.maxPerAssignment) {
        const error = new Error('material_limit'); error.code = 'material_limit'; throw error;
      }
      transaction.create(assignmentRef.collection('learning_materials').doc(materialId), {
        material_id: materialId, assignment_id: body.assignment_id, owner_teacher_id: uid,
        type: 'link', display_name: displayName, external_url: url, status: 'ready',
        projection_sync_state: 'pending', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      return assignmentSnapshot.data();
    });
    await syncActivityMaterialAccess({firestore, assignmentRef, assignmentData: assignment});
    await markMaterialProjectionSynchronized(firestore,
      assignmentRef.collection('learning_materials').doc(materialId),
    );
    return response.status(200).json({
      material_id: materialId, assignment_id: body.assignment_id, type: 'link',
      display_name: displayName, external_url: url,
    });
  } catch (error) {
    if (['not_found', 'forbidden', 'assignment_unavailable', 'material_limit'].includes(error.code)) {
      return response.status(error.code === 'forbidden' ? 403 : 409).json({error: error.code});
    }
    console.error('Activity material link creation failed', error);
    return response.status(503).json({error: 'unavailable'});
  }
}

async function removeActivityLearningMaterialHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
  storageFactory = getStorage,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (!validId(body.assignment_id) || !validId(body.material_id)) {
    return response.status(400).json({error: 'invalid_payload'});
  }
  const firestore = databaseFactory();
  const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
  const materialRef = assignmentRef.collection('learning_materials').doc(body.material_id);
  const stateRef = materialAccessStateRef(firestore, body.assignment_id);
  try {
    const material = await firestore.runTransaction(async (transaction) => {
      const [assignment, user, existing, state] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(firestore.collection('users').doc(uid)),
        transaction.get(materialRef), transaction.get(stateRef),
      ]);
      if (!assignment.exists || !user.exists || user.get('role') !== 'Teacher' ||
          assignment.get('teacher_id') !== uid) { const error = new Error('forbidden'); error.code = 'forbidden'; throw error; }
      if (!existing.exists) return null;
      if (existing.get('status') !== 'deleting') {
        transaction.set(materialRef, {status: 'deleting', deletion_requested_at: Timestamp.now()}, {merge: true});
      }
      const revoked = new Set(revokedMaterialIds(state.exists ? state.data() : null));
      revoked.add(body.material_id);
      transaction.set(stateRef, {
        assignment_id: body.assignment_id, revoked_material_ids: [...revoked],
        schema_version: 1, updated_at: Timestamp.now(),
      }, {merge: true});
      return existing.data();
    });
    if (!material) {
      // A prior invocation may have deleted metadata after object deletion but
      // failed while cleaning its marker. Retrying this idempotent endpoint is
      // the safe cleanup path; metadata absence is the post-delete proof.
      await deleteMaterialAccessForMaterial(firestore, body.assignment_id, body.material_id);
      await clearActivityMaterialAccessRevocation(firestore, body.assignment_id, body.material_id);
      return response.status(200).json({removed: true, already_removed: true});
    }
    // This is deliberately before any Storage operation. Storage rules consult
    // these records, so a failed object deletion remains fail-closed.
    await deleteMaterialAccessForMaterial(firestore, body.assignment_id, body.material_id);
    const stages = await firestore.collection('activity_material_uploads')
      .where('material_id', '==', body.material_id).get();
    for (const stage of stages.docs) {
      if (stage.get('state') !== 'deleting') {
        await stage.ref.set({
          state: 'deleting', deletion_requested_at: Timestamp.now(), terminal_at: Timestamp.now(),
        }, {merge: true});
      }
      const path = stage.get('staging_path');
      if (typeof path === 'string' && path.startsWith('activity_material_staging/')) {
        await storageFactory().bucket().file(path).delete({ignoreNotFound: true}).catch(() => undefined);
      }
    }
    if (typeof material.storage_path === 'string' && material.storage_path.startsWith('activity_learning_materials/')) {
      await storageFactory().bucket().file(material.storage_path).delete({ignoreNotFound: true});
    }
    await materialRef.delete();
    await clearActivityMaterialAccessRevocation(firestore, body.assignment_id, body.material_id);
    // Do not rebuild the assignment generation here: its other materials have
    // unchanged authoritative recipients and must not have a user-visible
    // access gap while this one material is removed.
    await synchronizeRemainingMaterialAccess(firestore, assignmentRef);
    return response.status(200).json({removed: true});
  } catch (error) {
    if (error.code === 'forbidden') return response.status(403).json({error: 'forbidden'});
    console.error('Activity material removal failed', error);
    return response.status(503).json({error: 'remove_pending'});
  }
}

async function getActivityMaterialUploadStatusHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (!validId(body.upload_id)) return response.status(400).json({error: 'invalid_payload'});
  const firestore = databaseFactory();
  const stageSnapshot = await firestore.collection('activity_material_uploads').doc(body.upload_id).get();
  if (!stageSnapshot.exists) return response.status(404).json({error: 'not_found'});
  const stage = stageSnapshot.data();
  const user = await firestore.collection('users').doc(uid).get();
  if (!user.exists || user.get('role') !== 'Teacher' || stage.owner_teacher_id !== uid) {
    return response.status(403).json({error: 'forbidden'});
  }
  if (!validId(stage.material_id) || !validId(stage.assignment_id) ||
      !['staging', 'validating', 'ready', 'rejected', 'deleting'].includes(stage.state)) {
    return response.status(404).json({error: 'not_found'});
  }
  const output = {upload_id: body.upload_id, material_id: stage.material_id, state: stage.state};
  if (stage.state === 'rejected') {
    output.rejection_reason = safeActivityMaterialRejectionReason(stage.rejection_reason);
  } else if (stage.state === 'ready') {
    const material = await firestore.collection('group_assignments').doc(stage.assignment_id)
      .collection('learning_materials').doc(stage.material_id).get();
    if (!material.exists || material.get('status') !== 'ready' ||
        material.get('owner_teacher_id') !== uid) {
      output.state = 'rejected';
      output.rejection_reason = 'material_unavailable';
    } else if (material.get('projection_sync_state') !== 'ready') {
      // The final object exists, but a trainee must not be told it is usable
      // before the Storage access projection has been rebuilt. Keep the UI in
      // its bounded validating state; the reconciler can finish this safely.
      output.state = 'validating';
    } else {
      output.material = {material_id: material.id, ...assignmentJsonValue(material.data())};
    }
  }
  return response.status(200).json(output);
}

async function listActivityLearningMaterialsHandler(request, response, {
  authenticate = authenticatedUid,
  databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  const uid = await authenticate(request);
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  if (!uid) return response.status(401).json({error: 'unauthenticated'});
  if (!validId(body.assignment_id)) return response.status(400).json({error: 'invalid_payload'});
  const firestore = databaseFactory();
  const assignmentRef = firestore.collection('group_assignments').doc(body.assignment_id);
  const assignment = await assignmentRef.get();
  if (!assignment.exists) return response.status(404).json({error: 'not_found'});
  const materials = await assignmentRef.collection('learning_materials').where('status', '==', 'ready').get();
  const allowed = assignment.get('teacher_id') === uid;
  const output = [];
  for (const material of materials.docs) {
    const access = allowed || await hasReadyActivityMaterialAccess(
      firestore, body.assignment_id, material.id, uid,
    );
    if (access) output.push({material_id: material.id, ...assignmentJsonValue(material.data())});
  }
  return response.status(200).json({materials: output});
}

async function createClassroomAssignmentHandler(request, response, {
  verifyToken = async (request) => {
    const token = firebaseBearerToken(request);
    return token ? getAuth().verifyIdToken(token, true) : null;
  }, databaseFactory = getFirestore,
} = {}) {
  setCors(response);
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'POST') return response.status(405).json({error: 'method_not_allowed'});
  let token;
  try { token = await verifyToken(request); } catch (_) { token = null; }
  if (!token || !validId(token.uid) || token.email_verified !== true) {
    return response.status(401).json({error: 'unauthenticated'});
  }
  const body = request.body && typeof request.body === 'object' ? request.body : {};
  const audienceType = body.audience_type;
  const recipientIds = body.recipient_ids;
  const attemptPolicy = body.attempt_policy == null
    ? {type: 'unlimited'}
    : body.attempt_policy;
  if (!validId(body.group_id) ||
      !['entire_class', 'selected_students', 'individual_student'].includes(audienceType) ||
      !Array.isArray(recipientIds) || recipientIds.some((id) => !validId(id)) ||
      new Set(recipientIds).size !== recipientIds.length ||
      (audienceType === 'entire_class' && recipientIds.length !== 0) ||
      (audienceType === 'selected_students' && recipientIds.length < 1) ||
      (audienceType === 'individual_student' && recipientIds.length !== 1) ||
      !validAssignmentAttemptPolicy(attemptPolicy)) {
    return response.status(400).json({error: 'invalid_audience'});
  }
  const dueAt = body.due_at == null ? null : new Date(body.due_at);
  if (body.due_at != null && Number.isNaN(dueAt.getTime())) {
    return response.status(400).json({error: 'invalid_due_at'});
  }
  const requestedStatus = body.status == null ? 'active' : body.status;
  const publishDate = body.publish_at == null ? null : new Date(body.publish_at);
  if (!['draft', 'scheduled', 'active'].includes(requestedStatus) ||
      (body.publish_at != null && Number.isNaN(publishDate.getTime())) ||
      (requestedStatus === 'scheduled' && (!publishDate || publishDate.getTime() <= Date.now())) ||
      (requestedStatus !== 'scheduled' && publishDate) ||
      (dueAt && publishDate && dueAt.getTime() <= publishDate.getTime())) {
    return response.status(400).json({error: 'invalid_publication'});
  }
  const topic = body.topic == null ? null : boundedText(body.topic, 80, {required: false});
  if (body.topic != null && !topic) {
    return response.status(400).json({error: 'invalid_topic'});
  }
  try {
    const firestore = databaseFactory();
    const result = await firestore.runTransaction(async (transaction) => {
      const userRef = firestore.collection('users').doc(token.uid);
      const groupRef = firestore.collection('groups').doc(body.group_id);
      const [user, group] = await Promise.all([transaction.get(userRef), transaction.get(groupRef)]);
      if (!user.exists || user.get('role') !== 'Teacher' || user.get('lifecycle_state') === 'deleting' ||
          !group.exists || group.get('teacher_id') !== token.uid || group.get('status') !== 'active') {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const teacherDisplayName = boundedText(user.get('full_name'), 80);
      const groupName = boundedText(group.get('name'), 80);
      if (!teacherDisplayName || !groupName) {
        const error = new Error('invalid_identity'); error.code = 'invalid_identity'; throw error;
      }
      for (const traineeId of recipientIds) {
        const membership = await transaction.get(
          firestore.collection('group_memberships').doc(`${body.group_id}_${traineeId}`),
        );
        if (!membership.exists || membership.get('group_id') !== body.group_id ||
            membership.get('teacher_id') !== token.uid || membership.get('trainee_id') !== traineeId ||
            membership.get('status') !== 'approved') {
          const error = new Error('invalid_recipient'); error.code = 'invalid_recipient'; throw error;
        }
      }
      const now = Timestamp.now();
      const common = {
        teacher_id: token.uid, group_id: body.group_id, audience_type: audienceType,
        status: requestedStatus, teacher_display_name: teacherDisplayName, group_name: groupName,
        attempt_policy: attemptPolicy,
        created_at: now, updated_at: now,
        ...(dueAt ? {due_at: dueAt} : {}),
        ...(publishDate ? {publish_at: Timestamp.fromDate(publishDate)} : {}),
        ...(topic ? {topic} : {}),
      };
      let assignment;
      if (body.origin === 'official_elixr') {
        const official = OFFICIAL_ASSIGNMENTS.get(body.official_movement_name);
        if (!official) { const error = new Error('invalid_movement'); error.code = 'invalid_movement'; throw error; }
        const instructions = boundedText(body.display_instructions, 2000, {required: false});
        if (body.display_instructions != null && instructions == null) {
          const error = new Error('invalid_instructions'); error.code = 'invalid_instructions'; throw error;
        }
        assignment = {...common, movement_id: official[0], revision_id: official[1],
          origin: 'official_elixr', assessment_mode: 'official_guided',
          official_movement_name: body.official_movement_name, display_title: body.official_movement_name,
          ...(instructions ? {display_instructions: instructions} : {})};
      } else if (body.origin === 'teacher_created' && validId(body.movement_id) && validId(body.revision_id) &&
          Number.isInteger(body.max_score) && body.max_score >= 1 && body.max_score <= 100) {
        const movementRef = firestore.collection('teacher_movements').doc(body.movement_id);
        const revisionRef = movementRef.collection('revisions').doc(body.revision_id);
        const [movement, revision] = await Promise.all([transaction.get(movementRef), transaction.get(revisionRef)]);
        if (!movement.exists) {
          const error = new Error('movement_not_found'); error.code = 'movement_not_found'; throw error;
        }
        if (!revision.exists) {
          const error = new Error('revision_not_found'); error.code = 'revision_not_found'; throw error;
        }
        if (movement.get('teacher_id') !== token.uid || revision.get('teacher_id') !== token.uid) {
          const error = new Error('invalid_movement_owner'); error.code = 'invalid_movement_owner'; throw error;
        }
        if (movement.get('status') !== 'active') {
          const error = new Error('movement_archived'); error.code = 'movement_archived'; throw error;
        }
        if (movement.get('current_revision_id') !== body.revision_id) {
          const error = new Error('stale_revision'); error.code = 'stale_revision'; throw error;
        }
        if (revision.get('movement_id') !== body.movement_id ||
            revision.get('assessment_mode') !== 'teacher_reviewed') {
          const error = new Error('invalid_movement_spec'); error.code = 'invalid_movement_spec'; throw error;
        }
        const spec = revision.get('spec');
        const title = boundedText(body.display_title ?? movement.get('title'), 80);
        const instructions = boundedText(
          body.display_instructions ?? spec?.instructions, 2000,
        );
        const rawSafety = Object.prototype.hasOwnProperty.call(body, 'display_safety_guidance')
          ? body.display_safety_guidance
          : spec?.safety_guidance;
        const safetyGuidance = rawSafety == null || rawSafety === ''
          ? null
          : boundedText(rawSafety, 1000);
        const activityAssessment = body.activity_assessment || spec?.activity_assessment || null;
        if (!spec || spec.capability !== 'teacher_review_only' ||
            !title || !instructions ||
            (rawSafety != null && rawSafety !== '' && !safetyGuidance) ||
            !['bottle', 'shaker', 'bottle_and_shaker'].includes(spec.required_prop)) {
          const error = new Error('invalid_movement_spec'); error.code = 'invalid_movement_spec'; throw error;
        }
        if (activityAssessment != null &&
            !validActivityAssessment(activityAssessment, body.max_score)) {
          const error = new Error('invalid_activity_assessment'); error.code = 'invalid_activity_assessment'; throw error;
        }
        assignment = {...common, movement_id: body.movement_id, revision_id: body.revision_id,
          origin: 'teacher_created', assessment_mode: 'teacher_reviewed', display_title: title,
          display_instructions: instructions, ...(safetyGuidance ? {display_safety_guidance: safetyGuidance} : {}),
          allowed_prop: spec.required_prop, max_score: body.max_score, grading_locked: false,
          ...(activityAssessment ? {
            configuration_revision: 1,
            activity_assessment: assignmentJsonValue(activityAssessment),
          } : {})};
      } else { const error = new Error('invalid_payload'); error.code = 'invalid_payload'; throw error; }
      const assignmentRef = firestore.collection('group_assignments').doc();
      transaction.create(assignmentRef, assignment);
      for (const traineeId of recipientIds) {
        transaction.create(assignmentRef.collection('assignment_recipients').doc(traineeId), {
          assignment_id: assignmentRef.id, group_id: body.group_id, teacher_id: token.uid,
          trainee_id: traineeId, audience_type: audienceType, schema_version: 1,
          created_at: common.created_at,
        });
      }
      return {id: assignmentRef.id, assignment};
    });
    return response.status(200).json({assignment: {id: result.id, ...assignmentJsonValue(result.assignment)}, recipient_ids: recipientIds});
  } catch (error) {
    if (['forbidden', 'invalid_recipient', 'invalid_movement', 'movement_not_found',
      'movement_archived', 'revision_not_found', 'stale_revision',
      'invalid_movement_owner', 'invalid_movement_spec',
      'invalid_activity_assessment', 'invalid_payload', 'invalid_instructions',
      'invalid_identity', 'invalid_topic'].includes(error.code)) {
      return response.status(error.code === 'forbidden' ? 403 : 400).json({error: error.code});
    }
    return response.status(503).json({error: 'unavailable'});
  }
}

exports.createClassroomAssignment = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30}, createClassroomAssignmentHandler,
);

exports.permanentDeleteAssignment = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 540, memory: '512MiB'},
  permanentDeleteAssignmentHandler,
);

exports.permanentDeleteClassroom = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 540, memory: '512MiB'},
  permanentDeleteClassroomHandler,
);

exports.reserveTeacherActivityAttempt = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  reserveTeacherActivityAttemptHandler,
);

exports.consumeTeacherActivityAttempt = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  consumeTeacherActivityAttemptHandler,
);

exports.abandonTeacherActivityAttempt = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  abandonTeacherActivityAttemptHandler,
);

exports.updateTeacherActivityAssignment = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 60},
  updateTeacherActivityAssignmentHandler,
);

exports.gradeTeacherActivityAttempt = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  gradeTeacherActivityAttemptHandler,
);

exports.beginActivityMaterialUpload = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  beginActivityMaterialUploadHandler,
);

exports.addActivityLearningMaterialLink = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  addActivityLearningMaterialLinkHandler,
);

exports.removeActivityLearningMaterial = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 60},
  removeActivityLearningMaterialHandler,
);

exports.getActivityMaterialUploadStatus = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  getActivityMaterialUploadStatusHandler,
);

exports.listActivityLearningMaterials = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30},
  listActivityLearningMaterialsHandler,
);

exports.validateStagedActivityLearningMaterial = onObjectFinalized(
  {region: REGION, bucket: STORAGE_BUCKET, timeoutSeconds: 120, memory: '512MiB'},
  async (event) => {
    const objectName = event.data.name || '';
    const match = objectName.match(
      /^activity_material_staging\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_-]+)\/([A-Za-z0-9-]+)$/,
    );
    if (!match || !validId(match[1]) || !validId(match[2]) || !validId(match[3])) return;
    await finalizeStagedActivityMaterial(match[3]);
  },
);

// Assignment writes and membership changes are the authoritative sources for
// projection reconciliation. This handles audience edits, archive/restore,
// publish-now, and immediate membership revocation without trusting a client.
exports.syncActivityMaterialAccessForAssignment = onDocumentWritten(
  {region: REGION, document: 'group_assignments/{assignmentId}'},
  async (event) => {
    const firestore = getFirestore();
    if (!event.data.after.exists) {
      await deleteMaterialAccessForAssignment(firestore, event.params.assignmentId);
      return;
    }
    await syncActivityMaterialAccess({
      firestore, assignmentRef: event.data.after.ref, assignmentData: event.data.after.data(),
    });
  },
);

exports.syncActivityMaterialAccessForRecipient = onDocumentWritten(
  {region: REGION, document: 'group_assignments/{assignmentId}/assignment_recipients/{traineeId}'},
  async (event) => {
    const firestore = getFirestore();
    const assignmentRef = firestore.collection('group_assignments').doc(event.params.assignmentId);
    await syncActivityMaterialAccess({firestore, assignmentRef});
  },
);

exports.syncActivityMaterialAccessForMembership = onDocumentWritten(
  {region: REGION, document: 'group_memberships/{membershipId}'},
  async (event) => {
    const membership = event.data.after.exists ? event.data.after.data() : event.data.before.data();
    if (!membership || !validId(membership.group_id)) return;
    const firestore = getFirestore();
    const assignments = await firestore.collection('group_assignments')
      .where('group_id', '==', membership.group_id).get();
    for (const assignment of assignments.docs) {
      await syncActivityMaterialAccess({
        firestore, assignmentRef: assignment.ref, assignmentData: assignment.data(),
      });
    }
  },
);

async function runActivityMaterialReconciliation({
  firestore = getFirestore(), storage = getStorage(), now = Timestamp.now(),
} = {}) {
  const stateRef = materialReconciliationStateRef(firestore);
  const stateSnapshot = await stateRef.get();
  const cursors = stateSnapshot.exists ? stateSnapshot.get('cursors') || {} : {};
  const batchSize = ACTIVITY_MATERIAL_LIMITS.reconciliationBatchSize;

  // Cursors advance even when an individual retry fails. A bad historical
  // record therefore cannot pin the first page and starve later uploads.
  async function processCursorBatch(cursorKey, buildQuery, processDocument, orderField = 'created_at') {
    const cursor = cursors[cursorKey];
    let query = buildQuery();
    if (cursor?.[orderField] && typeof cursor.document_id === 'string') {
      query = query.startAfter(cursor[orderField], cursor.document_id);
    }
    const snapshot = await query.limit(batchSize).get();
    for (const document of snapshot.docs) {
      try {
        await processDocument(document);
      } catch (error) {
        console.error(`Activity material reconciliation ${cursorKey} failed`, error);
      }
    }
    if (snapshot.empty || snapshot.size < batchSize) {
      await stateRef.set({cursors: {[cursorKey]: FieldValue.delete()}}, {merge: true});
    } else {
      const last = snapshot.docs.at(-1);
      await stateRef.set({cursors: {[cursorKey]: {
        [orderField]: last.get(orderField), document_id: last.id,
      }}}, {merge: true});
    }
  }

  for (const lifecycle of ['staging', 'validating']) {
    await processCursorBatch(`stage_${lifecycle}`, () => firestore
      .collection('activity_material_uploads').where('state', '==', lifecycle)
      .orderBy('created_at').orderBy(FieldPath.documentId()), async (document) => {
      const stage = document.data();
      if (stage.expires_at && stage.expires_at.toMillis() <= now.toMillis()) {
        const path = stage.staging_path;
        if (typeof path === 'string' && path.startsWith('activity_material_staging/')) {
          await storage.bucket().file(path).delete({ignoreNotFound: true});
        }
        await document.ref.set({
          state: 'rejected', rejection_reason: 'expired', rejected_at: now, terminal_at: now,
        }, {merge: true});
        await rejectStagedMaterialRecord(firestore, stage, 'expired');
      } else {
        await finalizeStagedActivityMaterial(document.id, {
          databaseFactory: () => firestore, storageFactory: () => storage,
        });
      }
    });
  }

  // Terminal records remain long enough for a Teacher to observe status, then
  // are removed in deterministic bounded passes.
  const retentionCutoff = Timestamp.fromMillis(now.toMillis() -
    ACTIVITY_MATERIAL_LIMITS.terminalUploadRetentionMs);
  for (const lifecycle of ['ready', 'rejected', 'deleting']) {
    await processCursorBatch(`terminal_${lifecycle}`, () => firestore
      .collection('activity_material_uploads').where('state', '==', lifecycle)
      .where('terminal_at', '<=', retentionCutoff)
      .orderBy('terminal_at').orderBy(FieldPath.documentId()), async (document) => {
      const path = document.get('staging_path');
      if (typeof path === 'string' && path.startsWith('activity_material_staging/')) {
        await storage.bucket().file(path).delete({ignoreNotFound: true});
      }
      await document.ref.delete();
    }, 'terminal_at');
    // Pre-status-endpoint records did not carry terminal_at. They are already
    // older than retention and can be safely cleared without preserving an
    // obsolete status forever.
    await processCursorBatch(`legacy_terminal_${lifecycle}`, () => firestore
      .collection('activity_material_uploads').where('state', '==', lifecycle)
      .where('created_at', '<=', retentionCutoff)
      .orderBy('created_at').orderBy(FieldPath.documentId()), async (document) => {
      if (document.get('terminal_at')) return;
      const path = document.get('staging_path');
      if (typeof path === 'string' && path.startsWith('activity_material_staging/')) {
        await storage.bucket().file(path).delete({ignoreNotFound: true});
      }
      await document.ref.delete();
    });
  }

  await processCursorBatch('deleting_material', () => firestore.collectionGroup('learning_materials')
    .where('status', '==', 'deleting').orderBy('deletion_requested_at')
    .orderBy(FieldPath.documentId()), async (material) => {
    const assignmentRef = material.ref.parent.parent;
    if (!assignmentRef) return;
    await revokeActivityMaterialAccess(firestore, assignmentRef.id, material.id);
    await deleteMaterialAccessForMaterial(firestore, assignmentRef.id, material.id);
    const path = material.get('storage_path');
    if (typeof path === 'string' && path.startsWith('activity_learning_materials/')) {
      await storage.bucket().file(path).delete({ignoreNotFound: true});
    }
    await material.ref.delete();
    await clearActivityMaterialAccessRevocation(firestore, assignmentRef.id, material.id);
    await synchronizeRemainingMaterialAccess(firestore, assignmentRef);
  }, 'deletion_requested_at');

  // This replaces the old first-100 scan of every ready material. Only a
  // publication that could not complete its immediate projection sync is work.
  await processCursorBatch('pending_projection', () => firestore.collectionGroup('learning_materials')
    .where('status', '==', 'ready').where('projection_sync_state', '==', 'pending')
    .orderBy('created_at').orderBy(FieldPath.documentId()), async (material) => {
    const assignmentRef = material.ref.parent.parent;
    if (!assignmentRef) return;
    await syncActivityMaterialAccess({firestore, assignmentRef});
    await markMaterialProjectionSynchronized(firestore, material.ref);
  });
}

exports.reconcileActivityLearningMaterials = onSchedule(
  {region: REGION, schedule: 'every 10 minutes', timeoutSeconds: 540, memory: '512MiB'},
  async () => runActivityMaterialReconciliation(),
);

exports.syncTeacherActivityAttemptState = onDocumentWritten(
  {region: REGION, document: 'assignment_attempts/{attemptId}'},
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after || !after.activity_assessment_snapshot ||
        after.attempt_kind !== 'teacher_review_submission') return;
    if (!['submitted', 'checked'].includes(after.status)) return;
    if (before && before.status === after.status) return;
    const firestore = getFirestore();
    const stateRef = firestore.collection('assignment_attempt_states')
      .doc(attemptStateId(after.assignment_id, after.trainee_id));
    const transition = await firestore.runTransaction(async (transaction) => {
      const stateSnapshot = await transaction.get(stateRef);
      if (!stateSnapshot.exists) return {accepted: false};
      const currentLatestId = stateSnapshot.get('latest_submission_id') || null;
      const currentOrdinal = stateSnapshot.get('latest_submission_ordinal') || 0;
      const nextOrdinal = Number.isInteger(after.attempt_number)
        ? after.attempt_number : 0;
      if (after.status === 'checked') {
        if (currentLatestId !== event.params.attemptId) return {accepted: false};
        transaction.set(stateRef, {
          graded: true,
          updated_at: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {accepted: true, previousLatestId: null};
      }
      if (nextOrdinal < currentOrdinal) return {accepted: false};
      transaction.set(stateRef, {
        latest_submission_id: event.params.attemptId,
        latest_submission_ordinal: nextOrdinal,
        active_attempt_id: FieldValue.delete(),
        active_request_id: FieldValue.delete(),
        active_consumed: FieldValue.delete(),
        updated_at: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {accepted: true, previousLatestId: currentLatestId};
    });

    const previousLatestId = transition.previousLatestId;
    const assignmentSnapshot = await firestore.collection('group_assignments')
      .doc(after.assignment_id).get();
    const unlimited = after.status === 'submitted' &&
      assignmentAttemptPolicy(assignmentSnapshot.exists ? assignmentSnapshot.data() : {})
        .type === 'unlimited';
    if (transition.accepted && unlimited && previousLatestId &&
        previousLatestId !== event.params.attemptId) {
      const previousRef = firestore.collection('assignment_attempts').doc(previousLatestId);
      const previous = await previousRef.get();
      const path = previous.exists ? previous.get('video_storage_path') : null;
      if (typeof path === 'string' && path.startsWith('assignment_submissions/')) {
        try {
          await getStorage().bucket().file(path).delete({ignoreNotFound: true});
          await previousRef.set({
            video_deleted_at: FieldValue.serverTimestamp(),
            video_storage_path: FieldValue.delete(),
          }, {merge: true});
        } catch (error) {
          console.error('Unlimited attempt retention cleanup failed', error);
        }
      }
    }
  },
);

exports.deleteAssignmentRecipients = onDocumentDeleted(
  {region: REGION, document: 'group_assignments/{assignmentId}'},
  async (event) => {
    const recipients = event.data.ref.collection('assignment_recipients');
    while (true) {
      const snapshot = await recipients.limit(400).get();
      if (snapshot.empty) break;
      const batch = getFirestore().batch();
      snapshot.docs.forEach((document) => batch.delete(document.ref));
      await batch.commit();
    }
  },
);

const SCHEDULED_ANNOUNCEMENT_PUBLICATION_BATCH_SIZE = 100;
const SCHEDULED_ANNOUNCEMENT_PUBLICATION_MAX_PAGES = 3;

function timestampMillis(value) {
  return value instanceof Timestamp ? value.toMillis() : null;
}

/**
 * Publishes one bounded, oldest-first page of due announcements. The
 * collection-group query deliberately cannot repair legacy documents that lack
 * `trainee_visible`: missing markers are repaired by the explicit, one-time
 * migrate:announcement-visibility script rather than a permanent full-database
 * scheduler scan.
 */
async function runScheduledAnnouncementPublication({
  firestore,
  now = Timestamp.now(),
  batchSize = SCHEDULED_ANNOUNCEMENT_PUBLICATION_BATCH_SIZE,
  maxPages = SCHEDULED_ANNOUNCEMENT_PUBLICATION_MAX_PAGES,
}) {
  const nowMillis = timestampMillis(now);
  if (nowMillis == null) throw new TypeError('now must be a Firestore Timestamp.');
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 500) {
    throw new RangeError('batchSize must be an integer from 1 through 500.');
  }
  if (!Number.isInteger(maxPages) || maxPages < 1 || maxPages > 10) {
    throw new RangeError('maxPages must be an integer from 1 through 10.');
  }

  const announcements = firestore.collectionGroup('announcements');
  const results = {candidates: 0, published: 0, skipped: 0, failed: 0};
  let cursor = null;

  // A fixed number of pages gives later due documents a chance even when the
  // oldest page contains repeated transaction failures, without open-ended
  // scheduler work. The next invocation resumes any remaining due work.
  for (let page = 0; page < maxPages; page += 1) {
    let query = announcements
      .where('trainee_visible', '==', false)
      .where('publish_at', '<=', now)
      .orderBy('publish_at', 'asc');
    if (cursor) query = query.startAfter(cursor);
    const due = await query.limit(batchSize).get();
    results.candidates += due.size;

    // Isolate a malformed/deleted document or a transient transaction failure
    // so it cannot block other due announcements.
    for (const candidate of due.docs) {
      try {
        const published = await firestore.runTransaction(async (transaction) => {
          const current = await transaction.get(candidate.ref);
          if (!current.exists) return false;
          const data = current.data();
          const publishAtMillis = timestampMillis(data.publish_at);
          if (data.trainee_visible !== false ||
              publishAtMillis == null || publishAtMillis > nowMillis) {
            return false;
          }
          transaction.update(candidate.ref, {trainee_visible: true});
          return true;
        });
        if (published) results.published += 1;
        else results.skipped += 1;
      } catch (error) {
        results.failed += 1;
        console.error('Scheduled announcement publication failed', {
          path: candidate.ref.path,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    if (due.size < batchSize) break;
    cursor = due.docs[due.docs.length - 1];
  }
  return results;
}

// Firestore rules require a queryable, server-maintained publication marker;
// request.time alone cannot make a collection query excluding future documents
// provably safe. A transaction rechecks canonical state to prevent a stale
// scheduler candidate from defeating a Teacher reschedule or deletion.
exports.publishScheduledAnnouncements = onSchedule(
  {region: REGION, schedule: 'every 1 minutes'},
  () => runScheduledAnnouncementPublication({firestore: getFirestore()}),
);

exports.listTraineeAssignments = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 15},
  listTraineeAssignmentsHandler,
);

exports.projectChatUserDirectory = onDocumentWritten(
  {region: REGION, document: 'users/{uid}'},
  async (event) => {
    const uid = event.params.uid;
    const after = event.data && event.data.after.exists
      ? event.data.after.data()
      : null;
    const directory = getFirestore().collection('chat_user_directory').doc(uid);
    if (!after ||
        !SUPPORTED_ROLES.has(after.role) ||
        after.lifecycle_state === 'deleting' ||
        typeof after.full_name !== 'string' ||
        !after.full_name.trim()) {
      await directory.delete();
      return;
    }
    await directory.set({
      display_name: after.full_name.trim(),
      role: after.role,
      ...(typeof after.profile_picture_url === 'string' && after.profile_picture_url
        ? {avatar_url: after.profile_picture_url}
        : {avatar_url: FieldValue.delete()}),
      search_prefixes: buildSearchPrefixes(after.full_name),
      lifecycle_state: 'active',
      schema_version: 1,
      updated_at: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
);

async function deleteConversationTree(conversationRef) {
  while (true) {
    const snapshot = await conversationRef.collection('messages').limit(400).get();
    if (snapshot.empty) break;
    const batch = getFirestore().batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
  }
  await conversationRef.delete();
}

async function archiveConversationForDeletedUser(conversation, deletedUid) {
  const firestore = getFirestore();
  const data = conversation.data();
  const candidateIds = (data.participant_ids || [])
    .filter((id) => id !== deletedUid && id !== 'deleted_user');
  const activeProfiles = new Map();
  for (const id of candidateIds) {
    const user = await firestore.collection('users').doc(id).get();
    if (user.exists && isActiveChatProfile(user.data())) {
      activeProfiles.set(id, user.data());
    }
  }
  if (activeProfiles.size === 0) {
    await deleteConversationTree(conversation.ref);
    return 'deleted';
  }

  const archiveRef = firestore.collection('chat_conversations').doc(
    archivedConversationId(conversation.id, activeProfiles.keys()),
  );
  const archivedData = buildArchivedConversationData({
    data,
    deletedUid,
    activeProfiles,
    archivedAt: FieldValue.serverTimestamp(),
  });
  await archiveRef.set(archivedData, {merge: true});

  let cursor = null;
  while (true) {
    let query = conversation.ref.collection('messages')
      .orderBy(FieldPath.documentId())
      .limit(350);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    const batch = firestore.batch();
    for (const message of snapshot.docs) {
      const messageData = message.data();
      batch.set(archiveRef.collection('messages').doc(message.id), {
        ...messageData,
        sender_id: messageData.sender_id === deletedUid
          ? 'deleted_user'
          : messageData.sender_id,
      });
    }
    await batch.commit();
    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < 350) break;
  }
  await deleteConversationTree(conversation.ref);
  return 'archived';
}

exports.archiveChatForAccountErasure = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 540, memory: '512MiB'},
  async (request, response) => {
    setCors(response);
    if (request.method === 'OPTIONS') {
      response.status(204).send('');
      return;
    }
    if (request.method !== 'POST') {
      response.status(405).json({error: 'method_not_allowed'});
      return;
    }
    const uid = await authenticatedUid(request);
    if (!uid) {
      response.status(401).json({error: 'unauthenticated'});
      return;
    }
    const firestore = getFirestore();
    const userRef = firestore.collection('users').doc(uid);
    const user = await userRef.get();
    if (user.exists) {
      await userRef.update({lifecycle_state: 'deleting'});
    }
    const conversations = await firestore
      .collection('chat_conversations')
      .where('participant_ids', 'array-contains', uid)
      .get();
    let archived = 0;
    let deleted = 0;
    for (const conversation of conversations.docs) {
      const result = await archiveConversationForDeletedUser(conversation, uid);
      if (result === 'archived') archived += 1;
      else deleted += 1;
    }

    const outgoingBlocks = await firestore
      .collection('chat_blocks')
      .doc(uid)
      .collection('blocked_users')
      .get();
    const incomingBlocks = await firestore
      .collectionGroup('blocked_users')
      .where('blocked_id', '==', uid)
      .get();
    const blockRefs = new Map();
    outgoingBlocks.docs.forEach((doc) => blockRefs.set(doc.ref.path, doc.ref));
    incomingBlocks.docs.forEach((doc) => blockRefs.set(doc.ref.path, doc.ref));
    const refs = [...blockRefs.values()];
    for (let index = 0; index < refs.length; index += 400) {
      const batch = firestore.batch();
      refs.slice(index, index + 400).forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
    await firestore.collection('chat_user_directory').doc(uid).delete();
    response.status(200).json({archived, deleted, blocks_removed: refs.length});
  },
);

exports._test = {
  normalizeSearchText,
  buildSearchPrefixes,
  conversationIdFor,
  sanitizedResult,
  validateSearchQuery,
  sanitizeDirectoryDocuments,
  isSearchRateLimited,
  isActiveChatProfile,
  archivedConversationId,
  buildArchivedConversationData,
  authenticatedUid,
  assignmentAudienceAllows,
  validRecipientProjection,
  assignmentJsonValue,
  validActivityAssessment,
  ACTIVITY_MATERIAL_LIMITS,
  safeActivityMaterialRejectionReason,
  materialMaximumBytes,
  materialAccessId,
  stagingPathFor,
  finalMaterialPathFor,
  detectActivityMaterialContent,
  normalizeActivityMaterialLink,
  materialStageMatchesObject,
  beginActivityMaterialUploadHandler,
  addActivityLearningMaterialLinkHandler,
  removeActivityLearningMaterialHandler,
  getActivityMaterialUploadStatusHandler,
  listActivityLearningMaterialsHandler,
  finalizeStagedActivityMaterial,
  runActivityMaterialReconciliation,
  syncActivityMaterialAccess,
  permanentDeleteAssignmentHandler,
  permanentDeleteClassroomHandler,
  cascadeAssignment,
  reserveTeacherActivityAttemptHandler,
  consumeTeacherActivityAttemptHandler,
  abandonTeacherActivityAttemptHandler,
  updateTeacherActivityAssignmentHandler,
  gradeTeacherActivityAttemptHandler,
  attemptStateId,
  sanitizedAssignment,
  listTraineeAssignmentsHandler,
  createClassroomAssignmentHandler,
  SCHEDULED_ANNOUNCEMENT_PUBLICATION_BATCH_SIZE,
  SCHEDULED_ANNOUNCEMENT_PUBLICATION_MAX_PAGES,
  runScheduledAnnouncementPublication,
};
