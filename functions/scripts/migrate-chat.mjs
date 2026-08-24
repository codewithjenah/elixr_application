import {applicationDefault, getApps, initializeApp} from 'firebase-admin/app';
import {FieldValue, getFirestore} from 'firebase-admin/firestore';
import migrationHelpers from '../lib/migration_helpers.js';

const {
  legacyMessageId,
  legacyMessageData,
  shouldReplaceConversationSummary,
  timestampMillis: millis,
} = migrationHelpers;

if (getApps().length === 0) initializeApp({credential: applicationDefault()});
const firestore = getFirestore();
const write = process.argv.includes('--write');
const counts = {
  users_scanned: 0,
  directory_migrated: 0,
  notes_scanned: 0,
  messages_migrated: 0,
  skipped: 0,
  failures: 0,
};

function normalize(value) {
  return String(value || '').normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
    .trim().toLowerCase().replace(/\s+/g, ' ');
}

function prefixes(name) {
  const normalized = normalize(name);
  const result = new Set();
  for (const token of new Set([normalized, ...normalized.split(' ')])) {
    for (let size = 2; size <= Math.min(token.length, 40); size += 1) {
      result.add(token.slice(0, size));
      if (result.size === 100) return [...result];
    }
  }
  return [...result];
}

function conversationId(first, second) {
  return [first, second].sort().join('__');
}

const users = await firestore.collection('users').get();
const userData = new Map();
for (const user of users.docs) {
  counts.users_scanned += 1;
  const data = user.data();
  if (!['Teacher', 'Trainee'].includes(data.role) ||
      data.lifecycle_state === 'deleting' ||
      !String(data.full_name || '').trim()) {
    counts.skipped += 1;
    continue;
  }
  userData.set(user.id, data);
  counts.directory_migrated += 1;
  if (write) {
    await firestore.collection('chat_user_directory').doc(user.id).set({
      display_name: data.full_name.trim(),
      role: data.role,
      ...(data.profile_picture_url ? {avatar_url: data.profile_picture_url} : {}),
      search_prefixes: prefixes(data.full_name),
      lifecycle_state: 'active',
      schema_version: 1,
      updated_at: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

const notes = await firestore.collection('teacher_coaching_notes').get();
const grouped = new Map();
for (const note of notes.docs) {
  counts.notes_scanned += 1;
  const data = note.data();
  if (!userData.has(data.teacher_id) || !userData.has(data.trainee_id) ||
      typeof data.body !== 'string' || !data.created_at) {
    counts.skipped += 1;
    continue;
  }
  const id = conversationId(data.teacher_id, data.trainee_id);
  if (!grouped.has(id)) grouped.set(id, []);
  grouped.get(id).push({id: note.id, ...data});
}

for (const [id, pairNotes] of grouped) {
  try {
    pairNotes.sort((a, b) => millis(a.created_at) - millis(b.created_at));
    const latest = pairNotes[pairNotes.length - 1];
    const teacher = userData.get(latest.teacher_id);
    const trainee = userData.get(latest.trainee_id);
    const participantIds = [latest.teacher_id, latest.trainee_id].sort();
    const conversationRef = firestore.collection('chat_conversations').doc(id);
    const existing = await conversationRef.get();
    const shouldReplaceSummary = shouldReplaceConversationSummary(
      existing.exists
        ? {exists: true, lastMessageAt: existing.get('last_message_at')}
        : null,
      latest.created_at,
    );
    if (write) {
      for (let offset = 0; offset < pairNotes.length; offset += 400) {
        const messageBatch = firestore.batch();
        for (const note of pairNotes.slice(offset, offset + 400)) {
          messageBatch.set(
            conversationRef.collection('messages').doc(legacyMessageId(note.id)),
            legacyMessageData(note, FieldValue.serverTimestamp()),
            {merge: false},
          );
        }
        await messageBatch.commit();
      }
      await conversationRef.set({
        participant_a: participantIds[0],
        participant_b: participantIds[1],
        ...(shouldReplaceSummary ? {
          participant_ids: participantIds,
          participant_snapshots: {
            [latest.teacher_id]: {
              id: latest.teacher_id,
              display_name: teacher.full_name,
              role: teacher.role,
              ...(teacher.profile_picture_url ? {avatar_url: teacher.profile_picture_url} : {}),
            },
            [latest.trainee_id]: {
              id: latest.trainee_id,
              display_name: trainee.full_name,
              role: trainee.role,
              ...(trainee.profile_picture_url ? {avatar_url: trainee.profile_picture_url} : {}),
            },
          },
          last_message_id: legacyMessageId(latest.id),
          last_message_body: latest.body,
          last_message_sender_id: latest.teacher_id,
          last_message_at: latest.created_at,
          unread_counts: {[latest.teacher_id]: 0, [latest.trainee_id]: 0},
          read_at: {[latest.teacher_id]: latest.created_at, [latest.trainee_id]: null},
          status: 'active',
          created_at: pairNotes[0].created_at,
          updated_at: latest.created_at,
          schema_version: 1,
        } : {}),
      }, {merge: true});
    }
    counts.messages_migrated += pairNotes.length;
  } catch (error) {
    counts.failures += 1;
    console.error(`Failed conversation ${id}:`, error);
  }
}

console.log(JSON.stringify({mode: write ? 'write' : 'dry-run', ...counts}, null, 2));
if (!write) console.log('No writes performed. Re-run with --write after review.');
