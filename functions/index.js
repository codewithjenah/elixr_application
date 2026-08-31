const {createHash} = require('node:crypto');
const {onRequest} = require('firebase-functions/v2/https');
const {onDocumentWritten, onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldPath, FieldValue, Timestamp, getFirestore} = require('firebase-admin/firestore');

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

async function authenticatedUid(request) {
  const authorization = request.get('authorization') || '';
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  try {
    return (await getAuth().verifyIdToken(match[1], true)).uid;
  } catch (_) {
    return null;
  }
}

function setCors(response) {
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  response.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
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
    // Canonical targeted assignments never carry recipient identities. Query
    // only this trainee's private projection, then validate every projection
    // against its canonical assignment and current approved membership.
    const recipientSnapshot = await firestore.collectionGroup('assignment_recipients')
      .where('trainee_id', '==', uid).get();
    const targetedIds = new Set();
    for (const recipientDocument of recipientSnapshot.docs) {
      const path = typeof recipientDocument.ref?.path === 'string'
        ? recipientDocument.ref.path.split('/')
        : [];
      if (path.length !== 4 || path[0] !== 'group_assignments' ||
          path[2] !== 'assignment_recipients' || path[3] !== uid ||
          recipientDocument.id !== uid) continue;
      const recipient = recipientDocument.data();
      const assignmentId = path[1];
      if (!validRecipientProjection(recipient, assignmentId, uid)) continue;
      const assignmentDocument = await firestore.collection('group_assignments').doc(assignmentId).get();
      if (!assignmentDocument.exists) continue;
      const assignment = assignmentDocument.data();
      if (!assignment || typeof assignment !== 'object') continue;
      if (requestedGroupId && assignment.group_id !== requestedGroupId) continue;
      if (teacherByGroupId.get(assignment.group_id) !== assignment.teacher_id ||
          !assignmentAudienceAllows(assignment, uid, recipient, assignmentId)) continue;
      targetedIds.add(assignmentId);
      documents.push(assignmentDocument);
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
    const authorization = request.get('authorization') || '';
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    return match ? getAuth().verifyIdToken(match[1], true) : null;
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
  if (!validId(body.group_id) ||
      !['entire_class', 'selected_students', 'individual_student'].includes(audienceType) ||
      !Array.isArray(recipientIds) || recipientIds.some((id) => !validId(id)) ||
      new Set(recipientIds).size !== recipientIds.length ||
      (audienceType === 'entire_class' && recipientIds.length !== 0) ||
      (audienceType === 'selected_students' && recipientIds.length < 1) ||
      (audienceType === 'individual_student' && recipientIds.length !== 1)) {
    return response.status(400).json({error: 'invalid_audience'});
  }
  const dueAt = body.due_at == null ? null : new Date(body.due_at);
  if (body.due_at != null && Number.isNaN(dueAt.getTime())) {
    return response.status(400).json({error: 'invalid_due_at'});
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
        created_at: now, updated_at: now,
        ...(dueAt ? {due_at: dueAt} : {}),
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
        if (!movement.exists || !revision.exists || movement.get('teacher_id') !== token.uid ||
            movement.get('status') !== 'active' || movement.get('current_revision_id') !== body.revision_id ||
            revision.get('teacher_id') !== token.uid || revision.get('movement_id') !== body.movement_id ||
            revision.get('assessment_mode') !== 'teacher_reviewed') {
          const error = new Error('invalid_movement'); error.code = 'invalid_movement'; throw error;
        }
        const spec = revision.get('spec');
        const title = boundedText(movement.get('title'), 80);
        const instructions = boundedText(spec?.instructions, 2000);
        const safetyGuidance = spec?.safety_guidance == null
          ? null
          : boundedText(spec.safety_guidance, 1000);
        if (!spec || spec.capability !== 'teacher_review_only' ||
            !title || !instructions ||
            (spec.safety_guidance != null && !safetyGuidance) ||
            !['bottle', 'shaker', 'bottle_and_shaker'].includes(spec.required_prop)) {
          const error = new Error('invalid_movement'); error.code = 'invalid_movement'; throw error;
        }
        assignment = {...common, movement_id: body.movement_id, revision_id: body.revision_id,
          origin: 'teacher_created', assessment_mode: 'teacher_reviewed', display_title: title,
          display_instructions: instructions, ...(safetyGuidance ? {display_safety_guidance: safetyGuidance} : {}),
          allowed_prop: spec.required_prop, max_score: body.max_score, grading_locked: false};
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
    if (['forbidden', 'invalid_recipient', 'invalid_movement', 'invalid_payload', 'invalid_instructions', 'invalid_identity'].includes(error.code)) {
      return response.status(error.code === 'forbidden' ? 403 : 400).json({error: error.code});
    }
    return response.status(503).json({error: 'unavailable'});
  }
}

exports.createClassroomAssignment = onRequest(
  {region: REGION, cors: false, timeoutSeconds: 30}, createClassroomAssignmentHandler,
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
  sanitizedAssignment,
  listTraineeAssignmentsHandler,
  createClassroomAssignmentHandler,
};
