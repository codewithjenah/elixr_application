import {readFileSync} from 'node:fs';
import {after, before, beforeEach, describe, test} from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteField,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'group-1';
const ANNOUNCEMENT_ID = 'announcement-1';
const RULES_SOURCE = readFileSync(
  new URL('../firestore.rules', import.meta.url),
  'utf8',
);

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: RULES_SOURCE, host: '127.0.0.1', port: 8080},
  });
});

beforeEach(async () => testEnv.clearFirestore());
after(async () => testEnv.cleanup());

function context(uid, {emailVerified = true} = {}) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: emailVerified,
  });
}

async function seedClass({active = true, approved = false} = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(doc(db, 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      role: 'Trainee',
    });
    await setDoc(doc(db, 'users', 'other'), {
      full_name: 'Other Teacher',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'groups', GROUP_ID), {
      teacher_id: 'teacher',
      name: 'BSHM 4A',
      status: active ? 'active' : 'archived',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    if (approved) {
      await setDoc(doc(db, 'group_memberships', `${GROUP_ID}_trainee`), {
        group_id: GROUP_ID,
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        teacher_display_name: 'Grace Hopper',
        trainee_display_name: 'Ada Lovelace',
        status: 'approved',
        invite_id: '7KPMXR4DQ2WT',
        request_version: 1,
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      });
    }
  });
}

function announcementRef(db) {
  return doc(db, 'groups', GROUP_ID, 'announcements', ANNOUNCEMENT_ID);
}

function announcementPayload() {
  return {
    group_id: GROUP_ID,
    teacher_id: 'teacher',
    title: 'Practice Reminder',
    body: 'Review Hand Stall before Friday.',
    created_at: serverTimestamp(),
    edited_at: null,
    trainee_visible: true,
    schema_version: 1,
  };
}

describe('Classroom announcements', () => {
  test('verified owning Teacher creates, edits, and deletes a broadcast', async () => {
    await seedClass();
    const teacher = context('teacher').firestore();
    await assertSucceeds(setDoc(announcementRef(teacher), announcementPayload()));
    const announcements = collection(teacher, 'groups', GROUP_ID, 'announcements');
    const visible = await assertSucceeds(
      getDocs(query(announcements, orderBy('created_at', 'desc'))),
    );
    assert.equal(visible.size, 1);
    await assertSucceeds(updateDoc(announcementRef(teacher), {
      title: 'Updated Reminder',
      body: 'Review Hand Stall before Thursday.',
      edited_at: serverTimestamp(),
    }));
    await assertSucceeds(deleteDoc(announcementRef(teacher)));
  });

  test('approved current member reads history; unapproved and removed members cannot', async () => {
    await seedClass({approved: true});
    const teacher = context('teacher').firestore();
    await assertSucceeds(setDoc(announcementRef(teacher), announcementPayload()));

    const trainee = context('trainee').firestore();
    const announcements = collection(trainee, 'groups', GROUP_ID, 'announcements');
    const visible = await assertSucceeds(getDocs(query(announcements, orderBy('created_at', 'desc'))));
    assert.equal(visible.size, 1);

    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'group_memberships', `${GROUP_ID}_trainee`), {
        status: 'removed',
      });
    });
    await assertFails(getDoc(announcementRef(trainee)));
    await assertFails(getDocs(query(announcements, orderBy('created_at', 'desc'))));
  });

  test('future scheduled announcements stay hidden until the server publishes them', async () => {
    await seedClass({approved: true});
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(announcementRef(admin.firestore()), {
        ...announcementPayload(),
        publish_at: new Date('2026-09-05T01:00:00.000Z'),
        trainee_visible: false,
      });
    });

    const teacher = context('teacher').firestore();
    const trainee = context('trainee').firestore();
    await assertSucceeds(getDoc(announcementRef(teacher)));
    await assertFails(getDoc(announcementRef(trainee)));

    // This is the only state transition made by the scheduled Admin Function.
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(announcementRef(admin.firestore()), {trainee_visible: true});
    });
    await assertSucceeds(getDoc(announcementRef(trainee)));
    await assertFails(getDoc(announcementRef(context('other').firestore())));
  });

  test('trainees cannot forge scheduled publication fields', async () => {
    await seedClass({approved: true});
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(announcementRef(admin.firestore()), {
        ...announcementPayload(),
        publish_at: new Date('2026-09-05T01:00:00.000Z'),
        trainee_visible: false,
      });
    });
    const traineeRef = announcementRef(context('trainee').firestore());
    await assertFails(updateDoc(traineeRef, {trainee_visible: true}));
    await assertFails(updateDoc(traineeRef, {publish_at: deleteField()}));
  });

  test('students and unrelated or unverified Teachers cannot write', async () => {
    await seedClass({approved: true});
    await assertFails(setDoc(announcementRef(context('trainee').firestore()), announcementPayload()));
    await assertFails(setDoc(announcementRef(context('other').firestore()), announcementPayload()));
    await assertFails(setDoc(
      announcementRef(context('teacher', {emailVerified: false}).firestore()),
      announcementPayload(),
    ));
  });

  test('students cannot read archived-class announcements, while owner can delete them', async () => {
    await seedClass({active: false, approved: true});
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(announcementRef(admin.firestore()), announcementPayload());
    });
    const trainee = context('trainee').firestore();
    await assertFails(getDoc(announcementRef(trainee)));
    await assertSucceeds(deleteDoc(announcementRef(context('teacher').firestore())));
  });

  test('owner alone can atomically point the classroom at one existing announcement', async () => {
    await seedClass({approved: true});
    const teacher = context('teacher').firestore();
    const group = doc(teacher, 'groups', GROUP_ID);
    await assertSucceeds(setDoc(announcementRef(teacher), announcementPayload()));
    await assertSucceeds(updateDoc(group, {
      pinned_announcement_id: ANNOUNCEMENT_ID,
      pinned_announcement_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));

    await assertFails(updateDoc(doc(context('trainee').firestore(), 'groups', GROUP_ID), {
      pinned_announcement_id: ANNOUNCEMENT_ID,
      pinned_announcement_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
    await assertFails(updateDoc(group, {
      pinned_announcement_id: 'missing-announcement',
      pinned_announcement_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(group, {
      pinned_announcement_id: deleteField(),
      pinned_announcement_at: deleteField(),
      updated_at: serverTimestamp(),
    }));
  });
});
