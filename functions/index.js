const {createHash} = require('node:crypto');
const {onRequest} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldPath, FieldValue, getFirestore} = require('firebase-admin/firestore');

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
};
