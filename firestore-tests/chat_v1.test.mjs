import {readFileSync} from 'node:fs';
import {after, before, beforeEach, describe, test} from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  or,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let testEnv;
const conversationId = 'alice__bob';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-elixr',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'users', 'alice'), {
      full_name: 'Alice Trainee',
      email: 'alice@example.test',
      role: 'Trainee',
    });
    await setDoc(doc(admin, 'users', 'bob'), {
      full_name: 'Bob Teacher',
      email: 'bob@example.test',
      role: 'Teacher',
    });
    await setDoc(doc(admin, 'users', 'mallory'), {
      full_name: 'Mallory Trainee',
      email: 'mallory@example.test',
      role: 'Trainee',
    });
  });
});

after(async () => testEnv.cleanup());

function db(uid) {
  return testEnv.authenticatedContext(uid, {email: `${uid}@example.test`}).firestore();
}

function snapshots() {
  return {
    alice: {id: 'alice', display_name: 'Alice Trainee', role: 'Trainee'},
    bob: {id: 'bob', display_name: 'Bob Teacher', role: 'Teacher'},
  };
}

async function createConversation(senderDb, {
  recipientUnread = 1,
  participantSnapshots = snapshots(),
  createdAt = serverTimestamp(),
} = {}) {
  const conversation = doc(senderDb, 'chat_conversations', conversationId);
  const message = doc(collection(conversation, 'messages'), 'message-1');
  const batch = writeBatch(senderDb);
  batch.set(message, {
    sender_id: 'alice',
    body: 'Hello Bob',
    created_at: createdAt,
    edited_at: null,
    deleted_at: null,
  });
  batch.set(conversation, {
    participant_ids: ['alice', 'bob'],
    participant_a: 'alice',
    participant_b: 'bob',
    participant_snapshots: participantSnapshots,
    last_message_id: 'message-1',
    last_message_body: 'Hello Bob',
    last_message_sender_id: 'alice',
    last_message_at: createdAt,
    unread_counts: {alice: 0, bob: recipientUnread},
    read_at: {alice: createdAt, bob: null},
    status: 'active',
    created_at: createdAt,
    updated_at: createdAt,
    schema_version: 1,
  });
  await batch.commit();
}

describe('direct message rules', () => {
  test('atomic first send succeeds only with exact recipient unread increment', async () => {
    await assertSucceeds(createConversation(db('alice')));
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      for (const [uid, name, role] of [
        ['alice', 'Alice Trainee', 'Trainee'],
        ['bob', 'Bob Teacher', 'Teacher'],
      ]) {
        await setDoc(doc(admin, 'users', uid), {full_name: name, role});
      }
    });
    await assertFails(createConversation(db('alice'), {recipientUnread: 3}));
  });

  test('first send rejects forged identity snapshots and client timestamps', async () => {
    await assertFails(createConversation(db('alice'), {
      participantSnapshots: {
        ...snapshots(),
        alice: {id: 'alice', display_name: 'Forged Name', role: 'Trainee'},
      },
    }));
    await assertFails(createConversation(db('alice'), {
      createdAt: Timestamp.fromDate(new Date('2026-08-24T00:00:00Z')),
    }));
  });

  test('participants can read history while an unrelated account cannot', async () => {
    await createConversation(db('alice'));
    const refForBob = doc(db('bob'), 'chat_conversations', conversationId);
    await assertSucceeds(getDoc(refForBob));
    await assertSucceeds(getDocs(collection(refForBob, 'messages')));
    await assertFails(getDoc(doc(db('mallory'), 'chat_conversations', conversationId)));
  });

  test('participants can list their inbox with the production query shape', async () => {
    await createConversation(db('alice'));
    const inbox = query(
      collection(db('bob'), 'chat_conversations'),
      or(
        where('participant_a', '==', 'bob'),
        where('participant_b', '==', 'bob'),
      ),
      orderBy('updated_at', 'desc'),
    );
    await assertSucceeds(getDocs(inbox));

    const unrelatedInbox = query(
      collection(db('mallory'), 'chat_conversations'),
      or(
        where('participant_a', '==', 'alice'),
        where('participant_b', '==', 'alice'),
      ),
      orderBy('updated_at', 'desc'),
    );
    await assertFails(getDocs(unrelatedInbox));
  });

  test('read-state update can reset only the caller fields', async () => {
    await createConversation(db('alice'));
    const ref = doc(db('bob'), 'chat_conversations', conversationId);
    await assertSucceeds(updateDoc(ref, {
      unread_counts: {alice: 0, bob: 0},
      read_at: {alice: (await getDoc(ref)).data().read_at.alice, bob: serverTimestamp()},
    }));
    await assertFails(updateDoc(ref, {unread_counts: {alice: 9, bob: 0}}));
  });

  test('only the sender can edit or soft-delete a message', async () => {
    await createConversation(db('alice'));
    const aliceMessage = doc(db('alice'), 'chat_conversations', conversationId, 'messages', 'message-1');
    await assertSucceeds(updateDoc(aliceMessage, {
      body: 'Edited',
      edited_at: serverTimestamp(),
    }));
    const bobMessage = doc(db('bob'), 'chat_conversations', conversationId, 'messages', 'message-1');
    await assertFails(updateDoc(bobMessage, {
      body: 'Forged',
      edited_at: serverTimestamp(),
    }));
    await assertFails(updateDoc(aliceMessage, {
      created_at: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(aliceMessage, {
      body: null,
      edited_at: null,
      deleted_at: serverTimestamp(),
    }));
  });

  test('a block in either direction prevents the next send', async () => {
    await createConversation(db('alice'));
    await assertSucceeds(setDoc(
      doc(db('bob'), 'chat_blocks', 'bob', 'blocked_users', 'alice'),
      {blocker_id: 'bob', blocked_id: 'alice', created_at: serverTimestamp()},
    ));
    const alice = db('alice');
    const conversation = doc(alice, 'chat_conversations', conversationId);
    const next = doc(collection(conversation, 'messages'), 'message-2');
    const batch = writeBatch(alice);
    batch.set(next, {
      sender_id: 'alice', body: 'Blocked', created_at: serverTimestamp(),
      edited_at: null, deleted_at: null,
    });
    batch.update(conversation, {
      participant_snapshots: snapshots(),
      last_message_id: 'message-2',
      last_message_body: 'Blocked',
      last_message_sender_id: 'alice',
      last_message_at: serverTimestamp(),
      unread_counts: {alice: 0, bob: 2},
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());

    await deleteDoc(doc(db('bob'), 'chat_blocks', 'bob', 'blocked_users', 'alice'));
    await assertSucceeds(setDoc(
      doc(db('alice'), 'chat_blocks', 'alice', 'blocked_users', 'bob'),
      {blocker_id: 'alice', blocked_id: 'bob', created_at: serverTimestamp()},
    ));
    const outgoing = writeBatch(alice);
    outgoing.set(doc(collection(conversation, 'messages'), 'message-3'), {
      sender_id: 'alice', body: 'Still blocked', created_at: serverTimestamp(),
      edited_at: null, deleted_at: null,
    });
    outgoing.update(conversation, {
      participant_snapshots: snapshots(),
      last_message_id: 'message-3',
      last_message_body: 'Still blocked',
      last_message_sender_id: 'alice',
      last_message_at: serverTimestamp(),
      unread_counts: {alice: 0, bob: 2},
      updated_at: serverTimestamp(),
    });
    await assertFails(outgoing.commit());
  });

  test('a deleting account cannot start or continue a conversation', async () => {
    await createConversation(db('alice'));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'users', 'alice'), {
        lifecycle_state: 'deleting',
      });
    });
    const bob = db('bob');
    const conversation = doc(bob, 'chat_conversations', conversationId);
    const send = writeBatch(bob);
    send.set(doc(collection(conversation, 'messages'), 'message-2'), {
      sender_id: 'bob', body: 'Are you there?', created_at: serverTimestamp(),
      edited_at: null, deleted_at: null,
    });
    send.update(conversation, {
      participant_snapshots: snapshots(),
      last_message_id: 'message-2',
      last_message_body: 'Are you there?',
      last_message_sender_id: 'bob',
      last_message_at: serverTimestamp(),
      unread_counts: {alice: 1, bob: 0},
      updated_at: serverTimestamp(),
    });
    await assertFails(send.commit());
  });

  test('archived history is participant-readable and sender-editable but cannot continue', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      const archived = doc(admin, 'chat_conversations', 'archived_example');
      await setDoc(archived, {
        participant_ids: ['bob', 'deleted_user'],
        participant_snapshots: {
          bob: {id: 'bob', display_name: 'Bob Teacher', role: 'Teacher'},
          deleted_user: {
            id: 'deleted_user', display_name: 'Deleted user', role: 'Trainee',
          },
        },
        last_message_id: 'kept-message',
        last_message_body: 'Retained body',
        last_message_sender_id: 'bob',
        last_message_at: Timestamp.now(),
        unread_counts: {bob: 0},
        read_at: {bob: Timestamp.now()},
        status: 'archived',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
        archived_at: Timestamp.now(),
        schema_version: 1,
      });
      await setDoc(doc(collection(archived, 'messages'), 'kept-message'), {
        sender_id: 'bob', body: 'Retained body', created_at: Timestamp.now(),
        edited_at: null, deleted_at: null,
      });
    });

    const bob = db('bob');
    const bobConversation = doc(bob, 'chat_conversations', 'archived_example');
    const bobMessage = doc(collection(bobConversation, 'messages'), 'kept-message');
    await assertSucceeds(getDoc(bobConversation));
    await assertSucceeds(getDoc(bobMessage));
    await assertSucceeds(updateDoc(bobMessage, {
      body: 'Retained body, edited', edited_at: serverTimestamp(),
    }));
    await assertFails(getDoc(doc(db('mallory'), 'chat_conversations', 'archived_example')));

    const send = writeBatch(bob);
    send.set(doc(collection(bobConversation, 'messages'), 'new-message'), {
      sender_id: 'bob', body: 'Cannot continue', created_at: serverTimestamp(),
      edited_at: null, deleted_at: null,
    });
    send.update(bobConversation, {
      last_message_id: 'new-message',
      last_message_body: 'Cannot continue',
      last_message_sender_id: 'bob',
      last_message_at: serverTimestamp(),
      unread_counts: {bob: 0},
      updated_at: serverTimestamp(),
    });
    await assertFails(send.commit());
  });

  test('directory is server-only and legacy coaching writes are retired', async () => {
    await assertFails(getDocs(query(
      collection(db('alice'), 'chat_user_directory'),
      where('search_prefixes', 'array-contains', 'al'),
    )));
    await assertFails(setDoc(doc(db('bob'), 'teacher_coaching_notes', 'new'), {
      teacher_id: 'bob',
      trainee_id: 'alice',
      teacher_display_name: 'Bob Teacher',
      body: 'Legacy write',
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
  });
});
