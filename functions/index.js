const {createHash} = require('node:crypto');
const {onRequest} = require('firebase-functions/v2/https');
const {onDocumentWritten, onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldPath, FieldValue, Timestamp, getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');

if (getApps().length === 0) initializeApp();

const REGION = 'asia-southeast1';
const SUPPORTED_ROLES = new Set(['Teacher', 'Trainee']);
const SEARCH_LIMIT = 20;
const SEARCH_COOLDOWN_MS = 500;

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
  }
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
          assignment.status !== 'active' || assignment.deletion_state === 'deleting' ||
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
      if (assignment.due_at && now.toMillis() > assignment.due_at.toMillis()) {
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
      if (assignment.status !== 'active' || assignment.deletion_state === 'deleting' ||
          stateSnapshot.get('graded') === true || assignment.grading_locked === true ||
          !validActivityAssessment(assignment.activity_assessment, assignment.max_score)) {
        const error = new Error('forbidden'); error.code = 'forbidden'; throw error;
      }
      const now = Timestamp.now();
      if (assignment.due_at && now.toMillis() > assignment.due_at.toMillis()) {
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
          assignment.assessment_mode !== 'teacher_reviewed' || assignment.status !== 'active' ||
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
    const assignments = uniqueDocuments
      .filter((document) => {
        const data = document.data();
        return teacherByGroupId.get(data.group_id) === data.teacher_id &&
          (assignmentAudienceAllows(data, uid, null, document.id) ||
            targetedIds.has(document.id));
      })
      .map(sanitizedAssignment);
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
        status: 'active', teacher_display_name: teacherDisplayName, group_name: groupName,
        attempt_policy: attemptPolicy,
        created_at: now, updated_at: now,
        ...(dueAt ? {due_at: dueAt} : {}),
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
};
