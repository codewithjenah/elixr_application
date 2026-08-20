// Firebase Emulator security-rules tests for firestore.rules.
//
// Covers the daily-quest-board / daily-quest-claim / leaderboard quest_xp
// surface added in the Persistent Daily Quest System (Phase 1): replay-proof
// claims, exact-tier board creation, and the Asia/Manila server-time-anchored
// real-day window. Not part of the Flutter app; run with `npm test` from
// this directory (requires the Firebase Emulator Suite, via `firebase-tools`).
import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  getDoc,
  getDocs,
  collection,
  collectionGroup,
  deleteDoc,
  updateDoc,
  query,
  where,
  orderBy,
  documentId,
  limit,
  writeBatch,
  Timestamp,
  serverTimestamp,
  deleteField,
} from 'firebase/firestore';

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

function manilaDayKeyFor(date) {
  const shifted = new Date(date.getTime() + MANILA_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const d = String(shifted.getUTCDate()).padStart(2, '0');
  return `${y}${m}${d}`;
}

function manilaDayStartFor(date) {
  const shifted = new Date(date.getTime() + MANILA_OFFSET_MS);
  const utcMidnight = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
  return new Date(utcMidnight - MANILA_OFFSET_MS);
}

function manilaMonthKeyFor(date) {
  const shifted = new Date(date.getTime() + MANILA_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  return `${y}${m}`;
}

// A 5-quest combo satisfying exactly 2 easy + 2 medium + 1 hard with no
// category-cap violations (sessionCount/duration/scoreThreshold all 0 here).
// Kept in sync by the Dart<->rules contract test, not independently here.
const VALID_QUEST_IDS = [
  'two_movements', // easy
  'use_shaker', // easy
  'distinct_props_2', // medium
  'three_movements', // medium
  'practice_hard_movement', // hard
];
const CLAIM_QUEST_ID = 'two_movements';
const CLAIM_QUEST_XP = 10;
const ROLE_TRAINEE = 'Trainee';
const ROLE_TEACHER = 'Teacher';
const ROLE_ADMIN = 'Admin';

let testEnv;

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

// Phase 3A coaching-note policy.  These tests intentionally use direct client
// writes/queries: repository validation is defense in depth, while these rules
// are the authoritative boundary for a modified client.
describe('teacher coaching notes', () => {
  const notePath = (db, id = 'note') => doc(db, 'teacher_coaching_notes', id);
  const linkId = 'bob_alice';
  const noteData = (overrides = {}) => ({
    teacher_id: 'bob', trainee_id: 'alice', teacher_display_name: 'Bob Teacher',
    body: 'Keep your wrist steady.', created_at: serverTimestamp(), updated_at: serverTimestamp(),
    ...overrides,
  });
  const legacyNoteData = (overrides = {}) => noteData({
    authorization_source: 'legacy_link',
    ...overrides,
  });
  function teacherGroupBackedQuery(db, {
    teacherId = 'bob',
    traineeId = 'alice',
    groupId = 'group-1',
  } = {}) {
    return getDocs(query(
      collection(db, 'teacher_coaching_notes'),
      where('teacher_id', '==', teacherId),
      where('trainee_id', '==', traineeId),
      where('group_id', '==', groupId),
      orderBy('created_at', 'desc'),
      orderBy(documentId(), 'desc'),
    ));
  }
  function teacherLegacyQuery(db, {
    teacherId = 'bob',
    traineeId = 'alice',
  } = {}) {
    return getDocs(query(
      collection(db, 'teacher_coaching_notes'),
      where('teacher_id', '==', teacherId),
      where('trainee_id', '==', traineeId),
      where('authorization_source', '==', 'legacy_link'),
      orderBy('created_at', 'desc'),
      orderBy(documentId(), 'desc'),
    ));
  }
  function traineeReceiveQuery(db, traineeId = 'alice') {
    return getDocs(query(
      collection(db, 'teacher_coaching_notes'),
      where('trainee_id', '==', traineeId),
      orderBy('created_at', 'desc'),
      orderBy(documentId(), 'desc'),
    ));
  }
  function broadTeacherTraineeQuery(db, teacherId = 'bob', traineeId = 'alice') {
    return getDocs(query(
      collection(db, 'teacher_coaching_notes'),
      where('teacher_id', '==', teacherId),
      where('trainee_id', '==', traineeId),
    ));
  }
  async function seed({ status = 'approved', note = false } = {}) {
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'users', 'bob'), { full_name: 'Bob Teacher', role: ROLE_TEACHER });
      await setDoc(doc(admin, 'users', 'alice'), { full_name: 'Alice Trainee', role: ROLE_TRAINEE });
      await setDoc(doc(admin, 'teacher_student_links', linkId), {
        teacher_id: 'bob', trainee_id: 'alice', status,
      });
      if (note) await setDoc(notePath(admin), noteData({ created_at: Timestamp.now(), updated_at: Timestamp.now() }));
    });
  }

  test('approved teacher creates valid note and can query their exact history', async () => {
    await seed();
    const bob = bobDb();
    await assertSucceeds(setDoc(notePath(bob), legacyNoteData({ movement_name: 'Bottle in a tin' })));
    const notes = await assertSucceeds(teacherLegacyQuery(bob));
    assert.equal(notes.docs.length, 1);
  });

  test('non-approved relationship states and unauthenticated callers cannot create', async () => {
    for (const status of ['pending', 'rejected', 'cancelled', 'revoked']) {
      await testEnv.clearFirestore();
      await seed({ status });
      await assertFails(setDoc(notePath(bobDb(), status), legacyNoteData()));
    }
    await testEnv.clearFirestore();
    await seed();
    await assertFails(setDoc(notePath(testEnv.unauthenticatedContext().firestore(), 'anon'), legacyNoteData()));
  });

  test('create rejects spoofing, unrelated targets, invalid contents, and extra fields', async () => {
    await seed();
    const bob = bobDb();
    for (const [id, overrides] of [
      ['spoof', { teacher_id: 'eve' }], ['target', { trainee_id: 'carol' }],
      ['whitespace', { body: ' \n\t ' }], ['long', { body: 'a'.repeat(1001) }],
      ['movement', { movement_name: 'Bottle in a Tin' }], ['extra', { extra: true }],
    ]) await assertFails(setDoc(notePath(bob, id), legacyNoteData(overrides)));
  });

  test('author may update only mutable note fields while approved', async () => {
    await seed({ note: true });
    const bob = bobDb();
    await assertSucceeds(updateDoc(notePath(bob), { body: 'Use a softer catch.', updated_at: serverTimestamp() }));
    await assertSucceeds(updateDoc(notePath(bob), { movement_name: 'Hand Stall', updated_at: serverTimestamp() }));
    for (const patch of [
      { teacher_id: 'eve', updated_at: serverTimestamp() },
      { trainee_id: 'carol', updated_at: serverTimestamp() },
      { teacher_display_name: 'Eve', updated_at: serverTimestamp() },
      { created_at: serverTimestamp(), updated_at: serverTimestamp() },
      { movement_name: 'invalid', updated_at: serverTimestamp() },
    ]) await assertFails(updateDoc(notePath(bob), patch));
  });

  test('addressed trainee reads notes but cannot mutate, while unrelated users cannot read', async () => {
    await seed({ note: true });
    await assertSucceeds(getDoc(notePath(aliceDb())));
    await assertFails(updateDoc(notePath(aliceDb()), { body: 'forged', updated_at: serverTimestamp() }));
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(getDoc(notePath(eve)));
  });

  test('only the author can delete; relationship revoke blocks future author access but preserves trainee history', async () => {
    await seed({ note: true });
    const bob = bobDb();
    await assertSucceeds(deleteDoc(notePath(bob)));
    await seed({ note: true, status: 'revoked' });
    await assertFails(setDoc(notePath(bob, 'new'), legacyNoteData()));
    await assertFails(updateDoc(notePath(bob), { body: 'blocked', updated_at: serverTimestamp() }));
    await assertFails(deleteDoc(notePath(bob)));
    await assertSucceeds(getDoc(notePath(aliceDb())));
  });

  test('progress-sharing status is irrelevant to approved coaching authorization', async () => {
    await seed();
    await seedBypassingRules(async (admin) => {
      await updateDoc(doc(admin, 'teacher_student_links', linkId), { progress_access: 'none' });
    });
    await assertSucceeds(setDoc(notePath(bobDb()), legacyNoteData()));
  });

  test('broad or partial teacher collection queries are denied', async () => {
    await seed({ note: true });
    const bob = bobDb();
    await assertFails(getDocs(collection(bob, 'teacher_coaching_notes')));
    await assertFails(getDocs(query(collection(bob, 'teacher_coaching_notes'), where('teacher_id', '==', 'bob'))));
  });

  test('account-erasure cleanup can list and delete notes after its user document is gone', async () => {
    await seed({ note: true });
    const bob = bobDb();
    await assertSucceeds(deleteDoc(doc(bob, 'users', 'bob')));
    const notes = await assertSucceeds(getDocs(query(collection(bob, 'teacher_coaching_notes'), where('teacher_id', '==', 'bob'))));
    await assertSucceeds(deleteDoc(notes.docs[0].ref));
  });

  test('group-only approved trainee can create group-backed coaching note without a link', async () => {
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'users', 'bob'), { full_name: 'Bob Teacher', role: 'Teacher' });
      await setDoc(doc(admin, 'users', 'alice'), { full_name: 'Alice Trainee', role: 'Trainee' });
      await setDoc(doc(admin, 'groups', 'group-1'), {
        teacher_id: 'bob', name: 'Class A', status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', 'group-1_alice'), {
        group_id: 'group-1', teacher_id: 'bob', trainee_id: 'alice',
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status: 'approved', request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
    });
    const bob = bobDb();
    await assertSucceeds(setDoc(notePath(bob, 'group-note'), noteData({
      group_id: 'group-1',
    })));
    const saved = await assertSucceeds(getDoc(notePath(bob, 'group-note')));
    assert.equal(saved.data().group_id, 'group-1');
    await assertSucceeds(getDoc(notePath(aliceDb(), 'group-note')));
    const listed = await assertSucceeds(teacherGroupBackedQuery(bob));
    assert.equal(listed.docs.length, 1);
    assert.equal(listed.docs[0].id, 'group-note');
    const received = await assertSucceeds(traineeReceiveQuery(aliceDb()));
    assert.equal(received.docs.some((item) => item.id === 'group-note'), true);
    await assertFails(broadTeacherTraineeQuery(bob));
    await seedBypassingRules(async (admin) => {
      const linkSnap = await getDoc(doc(admin, 'teacher_student_links', 'bob_alice'));
      assert.equal(linkSnap.exists(), false);
    });
  });

  test('pending group membership does not authorize group-backed coaching', async () => {
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'users', 'bob'), { full_name: 'Bob Teacher', role: 'Teacher' });
      await setDoc(doc(admin, 'users', 'alice'), { full_name: 'Alice Trainee', role: 'Trainee' });
      await setDoc(doc(admin, 'groups', 'group-1'), {
        teacher_id: 'bob', name: 'Class A', status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', 'group-1_alice'), {
        group_id: 'group-1', teacher_id: 'bob', trainee_id: 'alice',
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status: 'pending', request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
    });
    await assertFails(setDoc(notePath(bobDb(), 'pending-note'), noteData({ group_id: 'group-1' })));
  });

  test('unrelated teacher cannot spoof group_id for another classroom', async () => {
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'users', 'bob'), { full_name: 'Bob Teacher', role: 'Teacher' });
      await setDoc(doc(admin, 'users', 'eve'), { full_name: 'Eve Teacher', role: 'Teacher' });
      await setDoc(doc(admin, 'users', 'alice'), { full_name: 'Alice Trainee', role: 'Trainee' });
      await setDoc(doc(admin, 'groups', 'group-1'), {
        teacher_id: 'bob', name: 'Class A', status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', 'group-1_alice'), {
        group_id: 'group-1', teacher_id: 'bob', trainee_id: 'alice',
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status: 'approved', request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
    });
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(setDoc(notePath(eve, 'spoof'), noteData({
      teacher_id: 'eve', group_id: 'group-1',
    })));
  });

  test('group_id is immutable on update for group-backed notes', async () => {
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'users', 'bob'), { full_name: 'Bob Teacher', role: 'Teacher' });
      await setDoc(doc(admin, 'users', 'alice'), { full_name: 'Alice Trainee', role: 'Trainee' });
      await setDoc(doc(admin, 'groups', 'group-1'), {
        teacher_id: 'bob', name: 'Class A', status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', 'group-1_alice'), {
        group_id: 'group-1', teacher_id: 'bob', trainee_id: 'alice',
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status: 'approved', request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(notePath(admin, 'group-note'), noteData({
        group_id: 'group-1', created_at: Timestamp.now(), updated_at: Timestamp.now(),
      }));
    });
    await assertFails(updateDoc(notePath(bobDb(), 'group-note'), {
      group_id: 'group-2', updated_at: serverTimestamp(),
    }));
  });

  async function seedGroupClassroom({
    groupId = 'group-1',
    teacherId = 'bob',
    traineeId = 'alice',
    status = 'approved',
    noteId = null,
    noteGroupId = groupId,
  } = {}) {
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'users', teacherId), { full_name: 'Bob Teacher', role: ROLE_TEACHER });
      await setDoc(doc(admin, 'users', 'eve'), { full_name: 'Eve Teacher', role: ROLE_TEACHER });
      await setDoc(doc(admin, 'users', traineeId), { full_name: 'Alice Trainee', role: ROLE_TRAINEE });
      await setDoc(doc(admin, 'groups', groupId), {
        teacher_id: teacherId, name: groupId, status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', `${groupId}_${traineeId}`), {
        group_id: groupId, teacher_id: teacherId, trainee_id: traineeId,
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status, request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      if (noteId) {
        await setDoc(notePath(admin, noteId), noteData({
          group_id: noteGroupId,
          created_at: Timestamp.now(),
          updated_at: Timestamp.now(),
        }));
      }
    });
  }

  test('group-backed production query returns the note and denies unrelated teachers', async () => {
    await seedGroupClassroom({ noteId: 'group-note' });
    const bob = bobDb();
    const listed = await assertSucceeds(teacherGroupBackedQuery(bob));
    assert.equal(listed.docs.map((item) => item.id).join(','), 'group-note');
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(teacherGroupBackedQuery(eve));
    await assertFails(teacherGroupBackedQuery(eve, { teacherId: 'eve' }));
  });

  test('owning teacher cannot list a group A note using group B', async () => {
    await seedGroupClassroom({ noteId: 'group-a-note', groupId: 'group-1' });
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'groups', 'group-2'), {
        teacher_id: 'bob', name: 'Class B', status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', 'group-2_alice'), {
        group_id: 'group-2', teacher_id: 'bob', trainee_id: 'alice',
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status: 'approved', request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
    });
    const bob = bobDb();
    const groupB = await assertSucceeds(teacherGroupBackedQuery(bob, { groupId: 'group-2' }));
    assert.equal(groupB.docs.length, 0);
    const groupA = await assertSucceeds(teacherGroupBackedQuery(bob, { groupId: 'group-1' }));
    assert.equal(groupA.docs.map((item) => item.id).join(','), 'group-a-note');
  });

  test('pending membership does not authorize the group-backed production query', async () => {
    await seedGroupClassroom({ status: 'pending', noteId: 'pending-note' });
    await assertFails(teacherGroupBackedQuery(bobDb()));
  });

  test('removed membership does not authorize the group-backed production query', async () => {
    await seedGroupClassroom({ status: 'removed', noteId: 'removed-note' });
    await assertFails(teacherGroupBackedQuery(bobDb()));
  });

  test('teacher plus trainee without provenance remains denied for mixed authorization types', async () => {
    await seed();
    await seedBypassingRules(async (admin) => {
      await setDoc(notePath(admin, 'legacy'), noteData({
        authorization_source: 'legacy_link',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      }));
      await setDoc(doc(admin, 'groups', 'group-1'), {
        teacher_id: 'bob', name: 'Class A', status: 'active', schema_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin, 'group_memberships', 'group-1_alice'), {
        group_id: 'group-1', teacher_id: 'bob', trainee_id: 'alice',
        teacher_display_name: 'Bob Teacher', trainee_display_name: 'Alice Trainee',
        status: 'approved', request_version: 1,
        created_at: Timestamp.now(), updated_at: Timestamp.now(),
      });
      await setDoc(notePath(admin, 'classroom'), noteData({
        group_id: 'group-1',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      }));
    });
    await assertFails(broadTeacherTraineeQuery(bobDb()));
  });

  test('legacy approved-link teacher query works and revoke blocks live author history', async () => {
    await seed();
    const bob = bobDb();
    await assertSucceeds(setDoc(notePath(bob, 'legacy-note'), legacyNoteData()));
    const listed = await assertSucceeds(teacherLegacyQuery(bob));
    assert.equal(listed.docs.map((item) => item.id).join(','), 'legacy-note');
    await seedBypassingRules(async (admin) => {
      await updateDoc(doc(admin, 'teacher_student_links', 'bob_alice'), { status: 'revoked' });
    });
    await assertFails(teacherLegacyQuery(bob));
    await assertFails(getDoc(notePath(bob, 'legacy-note')));
    await assertSucceeds(getDoc(notePath(aliceDb(), 'legacy-note')));
  });

  test('group-backed create does not write teacher_student_links', async () => {
    await seedGroupClassroom();
    await assertSucceeds(setDoc(notePath(bobDb(), 'classroom-note'), noteData({ group_id: 'group-1' })));
    await seedBypassingRules(async (admin) => {
      const link = await getDoc(doc(admin, 'teacher_student_links', 'bob_alice'));
      assert.equal(link.exists(), false);
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

// Every test builds boards/claims keyed off the *real* current instant (so
// the server-time-anchored rules accept them), which means two tests run in
// the same real second would otherwise collide on the same document id.
// Clearing between tests keeps each test's Firestore state independent.
beforeEach(async () => {
  await testEnv.clearFirestore();
});

function aliceDb() {
  return testEnv.authenticatedContext('alice').firestore();
}

function bobDb() {
  return testEnv.authenticatedContext('bob').firestore();
}

function boardData(userId, now = new Date()) {
  const dayKey = manilaDayKeyFor(now);
  const dayStart = manilaDayStartFor(now);
  return {
    id: `${userId}_${dayKey}`,
    data: {
      user_id: userId,
      day_key: dayKey,
      day_start: Timestamp.fromDate(dayStart),
      quest_ids: VALID_QUEST_IDS,
      created_at: Timestamp.fromDate(now),
      updated_at: Timestamp.fromDate(now),
    },
  };
}

function claimData({ userId, boardId, dayKey, dayStart, questId = CLAIM_QUEST_ID, xp = CLAIM_QUEST_XP }) {
  return {
    id: `${userId}_${dayKey}_${questId}`,
    data: {
      user_id: userId,
      board_id: boardId,
      day_key: dayKey,
      day_start: Timestamp.fromDate(dayStart),
      quest_id: questId,
      xp_awarded: xp,
      claimed_at: Timestamp.now(),
    },
  };
}

function leaderboardSeed(userId, overrides = {}) {
  return {
    user_id: userId,
    display_name: 'Alice',
    total_xp: 25,
    sessions_completed: 1,
    score_sum: 80,
    average_score: 80,
    best_score: 80,
    last_session_at: Timestamp.now(),
    updated_at: Timestamp.now(),
    last_awarded_session_id: 's1',
    quest_xp: 0,
    ...overrides,
  };
}

function periodFields({
  dayKey,
  dailyXp,
  dailySessions,
  dailyScoreSum,
  dailyAverageScore,
  dailyBestScore,
  monthKey = dayKey.slice(0, 6),
  monthlyXp = dailyXp,
  monthlySessions = dailySessions,
  monthlyScoreSum = dailyScoreSum,
  monthlyAverageScore = dailyAverageScore,
  monthlyBestScore = dailyBestScore,
}) {
  return {
    daily_key: dayKey,
    daily_xp: dailyXp,
    daily_sessions_completed: dailySessions,
    daily_score_sum: dailyScoreSum,
    daily_average_score: dailyAverageScore,
    daily_best_score: dailyBestScore,
    monthly_key: monthKey,
    monthly_xp: monthlyXp,
    monthly_sessions_completed: monthlySessions,
    monthly_score_sum: monthlyScoreSum,
    monthly_average_score: monthlyAverageScore,
    monthly_best_score: monthlyBestScore,
  };
}

function sessionPeriodFields(createdAt, score) {
  const date = createdAt instanceof Timestamp ? createdAt.toDate() : createdAt;
  return periodFields({
    dayKey: manilaDayKeyFor(date),
    dailyXp: 25,
    dailySessions: 1,
    dailyScoreSum: score,
    dailyAverageScore: score,
    dailyBestScore: score,
    monthKey: manilaMonthKeyFor(date),
  });
}

function questPeriodFields(dayKey, xp) {
  return periodFields({
    dayKey,
    dailyXp: xp,
    dailySessions: 0,
    dailyScoreSum: 0,
    dailyAverageScore: 0,
    dailyBestScore: 0,
  });
}

function commitSessionAward(db, { sessionId, score, leaderboardUpdate }) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'leaderboard_processed_sessions', sessionId), {
    session_id: sessionId,
    user_id: 'alice',
    score,
    xp_awarded: 25,
    processed_at: serverTimestamp(),
  });
  batch.set(doc(db, 'leaderboard', 'alice'), leaderboardUpdate, { merge: true });
  return batch.commit();
}

async function seedBypassingRules(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

function rubricSessionFields({
  technique = 3,
  stability = 2,
  completion = 3,
  propPositioning = 2,
} = {}) {
  const total = technique + stability + completion + propPositioning;
  const performanceLevel =
    total <= 3
      ? 'beginning'
      : total <= 6
        ? 'developing'
        : total <= 9
          ? 'competent'
          : total <= 11
            ? 'proficient'
            : 'mastered';
  return {
    assessment_version: 2,
    rubric: {
      technique,
      stability,
      completion,
      prop_positioning: propPositioning,
    },
    rubric_total: total,
    performance_level: performanceLevel,
  };
}

describe('session authoritative timestamps', () => {
  test('session create accepts a server timestamp and rejects a client-supplied timestamp', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'server-stamped'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 60,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: serverTimestamp(),
      }),
    );

    await assertFails(
      setDoc(doc(db, 'sessions', 'spoofed-time'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 60,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
      }),
    );
  });

  test('session update cannot move created_at or alter the awarded assessment', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'immutable-source'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 60,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: serverTimestamp(),
      }),
    );

    await assertFails(
      setDoc(
        doc(db, 'sessions', 'immutable-source'),
        { created_at: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')) },
        { merge: true },
      ),
    );
    await assertFails(
      setDoc(
        doc(db, 'sessions', 'immutable-source'),
        { rubric_total: 12, performance_level: 'mastered' },
        { merge: true },
      ),
    );
  });
});

describe('assessment v2 rubric sessions', () => {
  test('valid rubric session create succeeds', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'v2-ok'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: serverTimestamp(),
      }),
    );
  });

  test('criterion above 3 is rejected', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'v2-high'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        assessment_version: 2,
        rubric: {
          technique: 4,
          stability: 2,
          completion: 3,
          prop_positioning: 2,
        },
        rubric_total: 11,
        performance_level: 'proficient',
        created_at: serverTimestamp(),
      }),
    );
  });

  test('negative criterion is rejected', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'v2-neg'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        assessment_version: 2,
        rubric: {
          technique: -1,
          stability: 2,
          completion: 3,
          prop_positioning: 2,
        },
        rubric_total: 6,
        performance_level: 'developing',
        created_at: serverTimestamp(),
      }),
    );
  });

  test('incorrect rubric_total is rejected', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'v2-bad-total'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        rubric_total: 12,
        created_at: serverTimestamp(),
      }),
    );
  });

  test('mismatched performance_level is rejected', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'v2-bad-level'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        performance_level: 'beginning',
        created_at: serverTimestamp(),
      }),
    );
  });

  test('client cannot mutate authoritative completed assessment', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'v2-locked'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(
        doc(db, 'sessions', 'v2-locked'),
        {
          rubric: {
            technique: 3,
            stability: 3,
            completion: 3,
            prop_positioning: 3,
          },
          rubric_total: 12,
          performance_level: 'mastered',
        },
        { merge: true },
      ),
    );
  });

  test('XP award remains idempotent for V2 sessions', async () => {
    const awardedAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'v2-award'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: awardedAt,
      });
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'leaderboard_processed_sessions', 'v2-award'), {
      session_id: 'v2-award',
      user_id: 'alice',
      rubric_total: 10,
      xp_awarded: 25,
      processed_at: Timestamp.now(),
    });
    batch.set(doc(db, 'leaderboard', 'alice'), {
      user_id: 'alice',
      display_name: 'Alice',
      total_xp: 25,
      sessions_completed: 1,
      score_sum: 0,
      average_score: 0,
      best_score: 0,
      last_session_at: awardedAt,
      updated_at: Timestamp.now(),
      last_awarded_session_id: 'v2-award',
      daily_key: manilaDayKeyFor(awardedAt.toDate()),
      daily_xp: 25,
      daily_sessions_completed: 1,
      daily_score_sum: 0,
      daily_average_score: 0,
      daily_best_score: 0,
      monthly_key: manilaMonthKeyFor(awardedAt.toDate()),
      monthly_xp: 25,
      monthly_sessions_completed: 1,
      monthly_score_sum: 0,
      monthly_average_score: 0,
      monthly_best_score: 0,
    });
    await assertSucceeds(batch.commit());

    // Replay with the same marker session id must fail (marker already exists;
    // create is the only marker write path and update is denied).
    await assertFails(
      setDoc(doc(db, 'leaderboard_processed_sessions', 'v2-award'), {
        session_id: 'v2-award',
        user_id: 'alice',
        rubric_total: 10,
        xp_awarded: 25,
        processed_at: Timestamp.now(),
      }),
    );
  });

  test('another user cannot alter the session', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'v2-owned'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: serverTimestamp(),
      }),
    );
    const bob = bobDb();
    await assertFails(
      setDoc(
        doc(bob, 'sessions', 'v2-owned'),
        { duration_seconds: 1 },
        { merge: true },
      ),
    );
    await assertFails(
      setDoc(doc(bob, 'sessions', 'v2-bob-forged'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Medium',
        duration_seconds: 90,
        prop_type: 'bottle',
        ...rubricSessionFields(),
        created_at: serverTimestamp(),
      }),
    );
  });

  test('legacy score create is rejected (V2-only writes)', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'legacy-create'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 82,
        created_at: serverTimestamp(),
      }),
    );
  });
});

describe('official ELIXR movement XP gate', () => {
  function v2SessionDoc(movementName, createdAt = serverTimestamp()) {
    return {
      user_id: 'alice',
      movement_name: movementName,
      difficulty: 'Medium',
      duration_seconds: 90,
      prop_type: 'bottle',
      ...rubricSessionFields(),
      created_at: createdAt,
    };
  }

  function v2Marker(sessionId) {
    return {
      session_id: sessionId,
      user_id: 'alice',
      rubric_total: 10,
      xp_awarded: 25,
      processed_at: Timestamp.now(),
    };
  }

  function v2LeaderboardCreate(sessionId, createdAt) {
    return {
      user_id: 'alice',
      display_name: 'Alice',
      total_xp: 25,
      sessions_completed: 1,
      score_sum: 0,
      average_score: 0,
      best_score: 0,
      last_session_at: createdAt,
      updated_at: Timestamp.now(),
      last_awarded_session_id: sessionId,
      daily_key: manilaDayKeyFor(createdAt.toDate()),
      daily_xp: 25,
      daily_sessions_completed: 1,
      daily_score_sum: 0,
      daily_average_score: 0,
      daily_best_score: 0,
      monthly_key: manilaMonthKeyFor(createdAt.toDate()),
      monthly_xp: 25,
      monthly_sessions_completed: 1,
      monthly_score_sum: 0,
      monthly_average_score: 0,
      monthly_best_score: 0,
    };
  }

  test('official V2 movement create succeeds', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'official-create'), v2SessionDoc('Hand Stall')),
    );
  });

  test('unknown movement create fails', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'unknown-create'), v2SessionDoc('Not A Real Move')),
    );
  });

  test('Wrist Stall create fails', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'wrist-create'), v2SessionDoc('Wrist Stall')),
    );
  });

  test('Arm Stall create fails', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'sessions', 'arm-create'), v2SessionDoc('Arm Stall')),
    );
  });

  test('Upper Forearm Stall create fails', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'sessions', 'upper-forearm-create'),
        v2SessionDoc('Upper Forearm Stall'),
      ),
    );
  });

  test('historical non-official session cannot create a processed marker', async () => {
    const createdAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'legacy-arm'),
        v2SessionDoc('Arm Stall', createdAt),
      );
    });

    const db = aliceDb();
    await assertFails(
      setDoc(doc(db, 'leaderboard_processed_sessions', 'legacy-arm'), v2Marker('legacy-arm')),
    );
  });

  test('historical non-official session cannot create a leaderboard award', async () => {
    const createdAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'legacy-wrist'),
        v2SessionDoc('Wrist Stall', createdAt),
      );
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'leaderboard_processed_sessions', 'legacy-wrist'), v2Marker('legacy-wrist'));
    batch.set(doc(db, 'leaderboard', 'alice'), v2LeaderboardCreate('legacy-wrist', createdAt));
    await assertFails(batch.commit());
  });

  test('historical non-official session cannot increment an existing leaderboard', async () => {
    const firstAt = Timestamp.fromMillis(Date.now() - 60_000);
    const secondAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'official-first'),
        v2SessionDoc('Hand Stall', firstAt),
      );
      await setDoc(
        doc(adminDb, 'sessions', 'legacy-upper'),
        v2SessionDoc('Upper Forearm Stall', secondAt),
      );
      await setDoc(
        doc(adminDb, 'leaderboard_processed_sessions', 'official-first'),
        v2Marker('official-first'),
      );
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        {
          ...v2LeaderboardCreate('official-first', firstAt),
          updated_at: firstAt,
        },
      );
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'leaderboard_processed_sessions', 'legacy-upper'),
      v2Marker('legacy-upper'),
    );
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        user_id: 'alice',
        display_name: 'Alice',
        total_xp: 50,
        sessions_completed: 2,
        score_sum: 0,
        average_score: 0,
        best_score: 0,
        last_session_at: secondAt,
        updated_at: Timestamp.now(),
        last_awarded_session_id: 'legacy-upper',
        daily_key: manilaDayKeyFor(secondAt.toDate()),
        daily_xp: 50,
        daily_sessions_completed: 2,
        daily_score_sum: 0,
        daily_average_score: 0,
        daily_best_score: 0,
        monthly_key: manilaMonthKeyFor(secondAt.toDate()),
        monthly_xp: 50,
        monthly_sessions_completed: 2,
        monthly_score_sum: 0,
        monthly_average_score: 0,
        monthly_best_score: 0,
      },
      { merge: true },
    );
    await assertFails(batch.commit());
  });

  test('historical Arm Stall cannot be renamed to Hand Stall', async () => {
    const createdAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'arm-rename'),
        v2SessionDoc('Arm Stall', createdAt),
      );
    });

    const db = aliceDb();
    await assertFails(
      updateDoc(doc(db, 'sessions', 'arm-rename'), { movement_name: 'Hand Stall' }),
    );

    const after = await getDoc(doc(db, 'sessions', 'arm-rename'));
    assert.equal(after.data().movement_name, 'Arm Stall');

    const batch = writeBatch(db);
    batch.set(doc(db, 'leaderboard_processed_sessions', 'arm-rename'), v2Marker('arm-rename'));
    batch.set(doc(db, 'leaderboard', 'alice'), v2LeaderboardCreate('arm-rename', createdAt));
    await assertFails(batch.commit());
  });

  test('historical Upper Forearm Stall cannot be renamed to an official movement', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'upper-rename'),
        v2SessionDoc('Upper Forearm Stall'),
      );
    });

    await assertFails(
      updateDoc(doc(aliceDb(), 'sessions', 'upper-rename'), {
        movement_name: 'Reverse Forearm Stall',
      }),
    );
  });

  test('historical custom movement cannot be renamed to an official movement', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'custom-rename'),
        v2SessionDoc('Classroom Custom Flip'),
      );
    });

    await assertFails(
      updateDoc(doc(aliceDb(), 'sessions', 'custom-rename'), {
        movement_name: 'Hand Stall',
      }),
    );
  });

  test('official Hand Stall cannot be renamed to another official movement', async () => {
    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'official-rename'), v2SessionDoc('Hand Stall')),
    );
    await assertFails(
      updateDoc(doc(db, 'sessions', 'official-rename'), {
        movement_name: 'Normal Grip',
      }),
    );
  });

  test('owner can still remove session evidence without changing movement_name', async () => {
    const createdAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'evidence-remove'), {
        ...v2SessionDoc('Hand Stall', createdAt),
        evidence_storage_path: 'users/alice/session_evidence/evidence-remove.jpg',
        evidence_kind: 'hold_confirmed',
        evidence_size_bytes: 2048,
      });
    });

    const db = aliceDb();
    await assertSucceeds(
      updateDoc(doc(db, 'sessions', 'evidence-remove'), {
        evidence_storage_path: deleteField(),
        evidence_kind: deleteField(),
        evidence_size_bytes: deleteField(),
      }),
    );

    const after = await getDoc(doc(db, 'sessions', 'evidence-remove'));
    assert.equal(after.data().movement_name, 'Hand Stall');
    assert.equal(after.data().evidence_storage_path, undefined);
    assert.equal(after.data().evidence_kind, undefined);
    assert.equal(after.data().evidence_size_bytes, undefined);
  });

  test('official session still awards exactly once', async () => {
    const awardedAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'official-once'),
        v2SessionDoc('Hand Stall', awardedAt),
      );
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'leaderboard_processed_sessions', 'official-once'),
      v2Marker('official-once'),
    );
    batch.set(doc(db, 'leaderboard', 'alice'), v2LeaderboardCreate('official-once', awardedAt));
    await assertSucceeds(batch.commit());

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().total_xp, 25);
    assert.equal(after.data().sessions_completed, 1);
    assert.equal(after.data().quest_xp ?? 0, 0);
    assert.equal(
      after.data().total_xp,
      after.data().sessions_completed * 25 + (after.data().quest_xp ?? 0),
    );

    await assertFails(
      setDoc(doc(db, 'leaderboard_processed_sessions', 'official-once'), v2Marker('official-once')),
    );
  });

  test('quest XP and total_xp identity remain valid after an official session award', async () => {
    const awardedAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'sessions', 'official-quest'),
        v2SessionDoc('Normal Grip', awardedAt),
      );
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          total_xp: 15,
          sessions_completed: 0,
          score_sum: 0,
          average_score: 0,
          best_score: 0,
          last_awarded_session_id: 'seed',
          quest_xp: 15,
        }),
      );
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'leaderboard_processed_sessions', 'official-quest'),
      v2Marker('official-quest'),
    );
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        user_id: 'alice',
        display_name: 'Alice',
        total_xp: 40,
        sessions_completed: 1,
        score_sum: 0,
        average_score: 0,
        best_score: 0,
        last_session_at: awardedAt,
        updated_at: Timestamp.now(),
        last_awarded_session_id: 'official-quest',
        quest_xp: 15,
        daily_key: manilaDayKeyFor(awardedAt.toDate()),
        daily_xp: 25,
        daily_sessions_completed: 1,
        daily_score_sum: 0,
        daily_average_score: 0,
        daily_best_score: 0,
        monthly_key: manilaMonthKeyFor(awardedAt.toDate()),
        monthly_xp: 25,
        monthly_sessions_completed: 1,
        monthly_score_sum: 0,
        monthly_average_score: 0,
        monthly_best_score: 0,
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().quest_xp, 15);
    assert.equal(after.data().sessions_completed, 1);
    assert.equal(after.data().total_xp, 40);
    assert.equal(
      after.data().total_xp,
      after.data().sessions_completed * 25 + after.data().quest_xp,
    );
  });
});

describe('daily_quest_boards', () => {
  test('own missing board GET succeeds before creation', async () => {
    const db = aliceDb();
    const { id } = boardData('alice');
    await assertSucceeds(getDoc(doc(db, 'daily_quest_boards', id)));
  });

  test('own valid canonical board creation succeeds', async () => {
    const db = aliceDb();
    const { id, data } = boardData('alice');
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', id), data));
  });

  test('cross-user cannot create another user\'s board (missing-doc GET is a documented, deliberate exception)', async () => {
    const bob = bobDb();
    const { id, data } = boardData('alice', new Date(Date.now() + 3_600_000));
    // A GET of a *nonexistent* board succeeds for any signed-in user, by the
    // same deliberate design as the existing leaderboard_processed_sessions
    // missing-marker rule: resource is null, so there is no owner data to
    // check yet, and this only reveals doc-existence (never content). The
    // real security boundary is create/update, asserted below.
    await assertSucceeds(getDoc(doc(bob, 'daily_quest_boards', id)));
    await assertFails(setDoc(doc(bob, 'daily_quest_boards', id), { ...data, user_id: 'bob' }));
  });

  test('board with an unknown quest id is rejected', async () => {
    const db = aliceDb();
    const { id, data } = boardData('alice', new Date(Date.now() + 7_200_000));
    const badIds = [...VALID_QUEST_IDS];
    badIds[0] = 'not_a_real_quest';
    await assertFails(setDoc(doc(db, 'daily_quest_boards', id), { ...data, quest_ids: badIds }));
  });

  test('board with a duplicate quest id is rejected', async () => {
    const db = aliceDb();
    const { id, data } = boardData('alice', new Date(Date.now() + 10_800_000));
    const dupIds = [...VALID_QUEST_IDS];
    dupIds[4] = dupIds[0];
    await assertFails(setDoc(doc(db, 'daily_quest_boards', id), { ...data, quest_ids: dupIds }));
  });

  test('board with valid day fields but a fabricated board id is rejected', async () => {
    const db = aliceDb();
    const { data } = boardData('alice', new Date(Date.now() + 14_400_000));
    await assertFails(setDoc(doc(db, 'daily_quest_boards', 'alice_FAKEID99'), data));
  });

  test('past-day board creation fails', async () => {
    const db = aliceDb();
    const past = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
    const dayKey = manilaDayKeyFor(past);
    const dayStart = manilaDayStartFor(past);
    await assertFails(
      setDoc(doc(db, 'daily_quest_boards', `alice_${dayKey}`), {
        user_id: 'alice',
        day_key: dayKey,
        day_start: Timestamp.fromDate(dayStart),
        quest_ids: VALID_QUEST_IDS,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      }),
    );
  });

  test('future-day board creation fails', async () => {
    const db = aliceDb();
    const future = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const dayKey = manilaDayKeyFor(future);
    const dayStart = manilaDayStartFor(future);
    await assertFails(
      setDoc(doc(db, 'daily_quest_boards', `alice_${dayKey}`), {
        user_id: 'alice',
        day_key: dayKey,
        day_start: Timestamp.fromDate(dayStart),
        quest_ids: VALID_QUEST_IDS,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      }),
    );
  });

  test('board is fully immutable after creation', async () => {
    const db = aliceDb();
    const { id, data } = boardData('alice', new Date(Date.now() + 18_000_000));
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', id), data));
    await assertFails(
      setDoc(doc(db, 'daily_quest_boards', id), { ...data, quest_ids: [...VALID_QUEST_IDS].reverse() }),
    );
  });
});

describe('daily_quest_claims + leaderboard quest_xp', () => {
  test('atomic claim + leaderboard update succeeds together', async () => {
    const db = aliceDb();
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', boardId), board));

    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now, // recomputed inside claimData via manilaDayStartFor semantics below
    });
    // Use the *board's* day_start exactly, not a re-derived one, to avoid
    // any millisecond drift between two separate `new Date()` calls.
    claim.day_start = board.day_start;

    const batch = writeBatch(db);
    batch.set(doc(db, 'daily_quest_claims', claimId), claim);
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        quest_xp: CLAIM_QUEST_XP,
        total_xp: 25 + CLAIM_QUEST_XP,
        last_claim_id: claimId,
        ...questPeriodFields(board.day_key, CLAIM_QUEST_XP),
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().quest_xp, CLAIM_QUEST_XP);
    assert.equal(after.data().total_xp, 25 + CLAIM_QUEST_XP);
  });

  test('claim-only write without a matching leaderboard bump is rejected', async () => {
    const db = aliceDb();
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', boardId), board));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
      questId: 'use_shaker',
      xp: 10,
    });
    claim.day_start = board.day_start;

    await assertFails(setDoc(doc(db, 'daily_quest_claims', claimId), claim));
  });

  test('reusing an already-existing claim id (replay) is rejected', async () => {
    const db = aliceDb();
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', boardId), board));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
      questId: 'distinct_props_2',
      xp: 15,
    });
    claim.day_start = board.day_start;

    const firstBatch = writeBatch(db);
    firstBatch.set(doc(db, 'daily_quest_claims', claimId), claim);
    firstBatch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        quest_xp: 15,
        total_xp: 40,
        last_claim_id: claimId,
        ...questPeriodFields(board.day_key, 15),
      },
      { merge: true },
    );
    await assertSucceeds(firstBatch.commit());

    // Second write reuses claimId as last_claim_id without recreating the
    // claim document (it already exists) — must be rejected.
    await assertFails(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { quest_xp: 30, total_xp: 55, last_claim_id: claimId },
        { merge: true },
      ),
    );
  });

  test('duplicate claim create (second write to the same claim id) is rejected', async () => {
    const db = aliceDb();
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', boardId), board));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
      questId: 'three_movements',
      xp: 15,
    });
    claim.day_start = board.day_start;

    const batch = writeBatch(db);
    batch.set(doc(db, 'daily_quest_claims', claimId), claim);
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        quest_xp: 15,
        total_xp: 40,
        last_claim_id: claimId,
        ...questPeriodFields(board.day_key, 15),
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());

    await assertFails(setDoc(doc(db, 'daily_quest_claims', claimId), claim));
  });

  test('claim with mismatched board/claim day_start is rejected', async () => {
    const db = aliceDb();
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await assertSucceeds(setDoc(doc(db, 'daily_quest_boards', boardId), board));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
      questId: 'practice_hard_movement',
      xp: 20,
    });
    // Deliberately mismatched: 24h off from the board's real day_start.
    claim.day_start = Timestamp.fromMillis(board.day_start.toMillis() + 24 * 60 * 60 * 1000);

    await assertFails(setDoc(doc(db, 'daily_quest_claims', claimId), claim));
  });

  test('claim for a valid but expired (yesterday\'s) board is rejected after Manila midnight', async () => {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dayKey = manilaDayKeyFor(yesterday);
    const dayStart = manilaDayStartFor(yesterday);
    const boardId = `alice_${dayKey}`;

    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), {
        user_id: 'alice',
        day_key: dayKey,
        day_start: Timestamp.fromDate(dayStart),
        quest_ids: VALID_QUEST_IDS,
        created_at: Timestamp.fromDate(yesterday),
        updated_at: Timestamp.fromDate(yesterday),
      });
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const db = aliceDb();
    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey,
      dayStart: yesterday,
      questId: 'session_count_1',
      xp: 10,
    });
    claim.day_start = Timestamp.fromDate(dayStart);

    await assertFails(setDoc(doc(db, 'daily_quest_claims', claimId), claim));
  });

  test('cross-user cannot create a claim against another user\'s board', async () => {
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), board);
      await setDoc(doc(adminDb, 'leaderboard', 'bob'), leaderboardSeed('bob'));
    });

    const bob = bobDb();
    const { id: claimId, data: claim } = claimData({
      userId: 'bob',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
      questId: 'use_shaker',
      xp: 10,
    });
    claim.day_start = board.day_start;

    await assertFails(setDoc(doc(bob, 'daily_quest_claims', claimId), claim));
  });

  test('claims list query is restricted to the caller\'s own user_id', async () => {
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), board);
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
      await setDoc(doc(adminDb, 'daily_quest_claims', `alice_${board.day_key}_use_shaker`), {
        user_id: 'alice',
        board_id: boardId,
        day_key: board.day_key,
        day_start: board.day_start,
        quest_id: 'use_shaker',
        xp_awarded: 10,
        claimed_at: Timestamp.now(),
      });
    });

    const bob = bobDb();
    const q = query(collection(bob, 'daily_quest_claims'), where('user_id', '==', 'alice'));
    await assertFails(getDocs(q));

    const alice = aliceDb();
    const ownQuery = query(collection(alice, 'daily_quest_claims'), where('user_id', '==', 'alice'));
    await assertSucceeds(getDocs(ownQuery));
  });
});

describe('leaderboard quest_xp preservation', () => {
  test('session award preserves an existing quest_xp value', async () => {
    const awardedAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's1'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 80,
        created_at: Timestamp.now(),
      });
      await setDoc(doc(adminDb, 'sessions', 's2'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 100,
        created_at: awardedAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          total_xp: 40,
          sessions_completed: 1,
          score_sum: 80,
          average_score: 80,
          best_score: 80,
          last_awarded_session_id: 's1',
          quest_xp: 15,
        }),
      );
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'leaderboard_processed_sessions', 's2'), {
      session_id: 's2',
      user_id: 'alice',
      score: 100,
      xp_awarded: 25,
      processed_at: Timestamp.now(),
    });
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        user_id: 'alice',
        display_name: 'Alice',
        total_xp: 65,
        sessions_completed: 2,
        score_sum: 180,
        average_score: 90,
        best_score: 100,
        last_session_at: Timestamp.now(),
        updated_at: Timestamp.now(),
        last_awarded_session_id: 's2',
        quest_xp: 15,
        ...sessionPeriodFields(awardedAt, 100),
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().quest_xp, 15);
    assert.equal(after.data().total_xp, 65);
  });

  test('public-profile update preserves quest_xp and last_claim_id', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        // total_xp must satisfy sessions*25+quest_xp for the update rule's
        // invariant check to be reachable at all (seeding bypasses rules,
        // but the *update* below does not).
        leaderboardSeed('alice', {
          total_xp: 45,
          quest_xp: 20,
          last_claim_id: 'alice_20260101_use_shaker',
        }),
      );
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'leaderboard', 'alice'), { display_name: 'Alice Updated' }, { merge: true }),
    );

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().quest_xp, 20);
    assert.equal(after.data().last_claim_id, 'alice_20260101_use_shaker');
    assert.equal(after.data().display_name, 'Alice Updated');
  });

  test('legacy leaderboard document without quest_xp still accepts a session award', async () => {
    const awardedAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's3'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 70,
        created_at: Timestamp.now(),
      });
      await setDoc(doc(adminDb, 'sessions', 's4'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 90,
        created_at: awardedAt,
      });
      // Legacy doc: no quest_xp / last_claim_id fields at all.
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), {
        user_id: 'alice',
        display_name: 'Alice',
        total_xp: 25,
        sessions_completed: 1,
        score_sum: 70,
        average_score: 70,
        best_score: 70,
        last_session_at: Timestamp.now(),
        updated_at: Timestamp.now(),
        last_awarded_session_id: 's3',
      });
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'leaderboard_processed_sessions', 's4'), {
      session_id: 's4',
      user_id: 'alice',
      score: 90,
      xp_awarded: 25,
      processed_at: Timestamp.now(),
    });
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        user_id: 'alice',
        display_name: 'Alice',
        total_xp: 50,
        sessions_completed: 2,
        score_sum: 160,
        average_score: 80,
        best_score: 90,
        last_session_at: Timestamp.now(),
        updated_at: Timestamp.now(),
        last_awarded_session_id: 's4',
        ...sessionPeriodFields(awardedAt, 90),
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());
  });
});

describe('leaderboard daily/monthly period aggregates', () => {
  test('first session award uses source created_at across the Manila year boundary', async () => {
    const createdAt = Timestamp.fromDate(new Date('2025-12-31T16:00:00.000Z'));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'boundary-session'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 88,
        created_at: createdAt,
      });
    });

    const db = aliceDb();
    await assertSucceeds(
      commitSessionAward(db, {
        sessionId: 'boundary-session',
        score: 88,
        leaderboardUpdate: leaderboardSeed('alice', {
          last_awarded_session_id: 'boundary-session',
          last_session_at: createdAt,
          score_sum: 88,
          average_score: 88,
          best_score: 88,
          ...sessionPeriodFields(createdAt, 88),
        }),
      }),
    );

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().daily_key, '20260101');
    assert.equal(after.data().monthly_key, '202601');
  });

  test('same-period session accumulates XP and session score metrics', async () => {
    const firstAt = Timestamp.fromDate(new Date('2026-05-02T01:00:00.000Z'));
    const secondAt = Timestamp.fromDate(new Date('2026-05-02T09:00:00.000Z'));
    const dayKey = manilaDayKeyFor(secondAt.toDate());
    const monthKey = manilaMonthKeyFor(secondAt.toDate());
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'same-period-2'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 90,
        created_at: secondAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          total_xp: 35,
          quest_xp: 10,
          last_awarded_session_id: 'same-period-1',
          last_session_at: firstAt,
          score_sum: 70,
          average_score: 70,
          best_score: 70,
          ...periodFields({
            dayKey,
            dailyXp: 35,
            dailySessions: 1,
            dailyScoreSum: 70,
            dailyAverageScore: 70,
            dailyBestScore: 70,
            monthKey,
          }),
        }),
      );
    });

    const db = aliceDb();
    const accumulated = periodFields({
      dayKey,
      dailyXp: 60,
      dailySessions: 2,
      dailyScoreSum: 160,
      dailyAverageScore: 80,
      dailyBestScore: 90,
      monthKey,
    });
    await assertSucceeds(
      commitSessionAward(db, {
        sessionId: 'same-period-2',
        score: 90,
        leaderboardUpdate: {
          total_xp: 60,
          quest_xp: 10,
          sessions_completed: 2,
          score_sum: 160,
          average_score: 80,
          best_score: 90,
          last_session_at: secondAt,
          updated_at: serverTimestamp(),
          last_awarded_session_id: 'same-period-2',
          ...accumulated,
        },
      }),
    );

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().daily_xp, 60);
    assert.equal(after.data().daily_sessions_completed, 2);
    assert.equal(after.data().daily_average_score, 80);
    assert.equal(after.data().monthly_xp, 60);
  });

  test('new Manila day in the same month resets daily and accumulates monthly', async () => {
    const oldAt = Timestamp.fromDate(new Date('2026-05-01T04:00:00.000Z'));
    const newAt = Timestamp.fromDate(new Date('2026-05-02T04:00:00.000Z'));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'new-day-session'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 90,
        created_at: newAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          last_awarded_session_id: 'old-day-session',
          last_session_at: oldAt,
          ...sessionPeriodFields(oldAt, 80),
        }),
      );
    });

    const db = aliceDb();
    await assertSucceeds(
      commitSessionAward(db, {
        sessionId: 'new-day-session',
        score: 90,
        leaderboardUpdate: {
          total_xp: 50,
          quest_xp: 0,
          sessions_completed: 2,
          score_sum: 170,
          average_score: 85,
          best_score: 90,
          last_session_at: newAt,
          updated_at: serverTimestamp(),
          last_awarded_session_id: 'new-day-session',
          ...periodFields({
            dayKey: manilaDayKeyFor(newAt.toDate()),
            dailyXp: 25,
            dailySessions: 1,
            dailyScoreSum: 90,
            dailyAverageScore: 90,
            dailyBestScore: 90,
            monthKey: manilaMonthKeyFor(newAt.toDate()),
            monthlyXp: 50,
            monthlySessions: 2,
            monthlyScoreSum: 170,
            monthlyAverageScore: 85,
            monthlyBestScore: 90,
          }),
        },
      }),
    );

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().daily_sessions_completed, 1);
    assert.equal(after.data().daily_score_sum, 90);
    assert.equal(after.data().monthly_sessions_completed, 2);
    assert.equal(after.data().monthly_score_sum, 170);
  });

  test('newer session period resets both daily and monthly aggregates', async () => {
    const oldAt = Timestamp.fromDate(new Date('2026-01-31T10:00:00.000Z'));
    const newAt = Timestamp.fromDate(new Date('2026-01-31T16:00:00.000Z'));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'new-month-session'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 90,
        created_at: newAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          last_awarded_session_id: 'old-month-session',
          last_session_at: oldAt,
          score_sum: 70,
          average_score: 70,
          best_score: 70,
          ...sessionPeriodFields(oldAt, 70),
        }),
      );
    });

    const db = aliceDb();
    await assertSucceeds(
      commitSessionAward(db, {
        sessionId: 'new-month-session',
        score: 90,
        leaderboardUpdate: {
          total_xp: 50,
          quest_xp: 0,
          sessions_completed: 2,
          score_sum: 160,
          average_score: 80,
          best_score: 90,
          last_session_at: newAt,
          updated_at: serverTimestamp(),
          last_awarded_session_id: 'new-month-session',
          ...sessionPeriodFields(newAt, 90),
        },
      }),
    );

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().daily_key, '20260201');
    assert.equal(after.data().daily_sessions_completed, 1);
    assert.equal(after.data().monthly_key, '202602');
    assert.equal(after.data().monthly_sessions_completed, 1);
  });

  test('older backfilled session preserves the newer daily/monthly period state', async () => {
    const backfillAt = Timestamp.fromDate(new Date('2026-07-10T02:00:00.000Z'));
    const newerFields = periodFields({
      dayKey: '20260801',
      dailyXp: 50,
      dailySessions: 2,
      dailyScoreSum: 150,
      dailyAverageScore: 75,
      dailyBestScore: 80,
      monthKey: '202608',
    });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'backfilled-session'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 100,
        created_at: backfillAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          total_xp: 50,
          sessions_completed: 2,
          score_sum: 150,
          average_score: 75,
          best_score: 80,
          last_awarded_session_id: 'newer-session',
          ...newerFields,
        }),
      );
    });

    const db = aliceDb();
    await assertSucceeds(
      commitSessionAward(db, {
        sessionId: 'backfilled-session',
        score: 100,
        leaderboardUpdate: {
          total_xp: 75,
          quest_xp: 0,
          sessions_completed: 3,
          score_sum: 250,
          average_score: 250 / 3,
          best_score: 100,
          last_session_at: backfillAt,
          updated_at: serverTimestamp(),
          last_awarded_session_id: 'backfilled-session',
          ...newerFields,
        },
      }),
    );

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().daily_key, '20260801');
    assert.equal(after.data().daily_xp, 50);
    assert.equal(after.data().monthly_key, '202608');
    assert.equal(after.data().monthly_xp, 50);
  });

  test('cannot toggle among existing processed-session markers to replay awards', async () => {
    const createdAt = Timestamp.fromMillis(Date.now() - 60_000);
    const dayKey = manilaDayKeyFor(createdAt.toDate());
    const monthKey = manilaMonthKeyFor(createdAt.toDate());
    const replayCandidates = [
      { sessionId: 'processed-a', score: 90 },
      { sessionId: 'processed-b', score: 70 },
    ];
    await seedBypassingRules(async (adminDb) => {
      for (const candidate of replayCandidates) {
        await setDoc(doc(adminDb, 'sessions', candidate.sessionId), {
          user_id: 'alice',
          movement_name: 'Hand Stall',
          score: candidate.score,
          created_at: createdAt,
        });
        await setDoc(
          doc(adminDb, 'leaderboard_processed_sessions', candidate.sessionId),
          {
            session_id: candidate.sessionId,
            user_id: 'alice',
            score: candidate.score,
            xp_awarded: 25,
            processed_at: createdAt,
          },
        );
      }
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          last_awarded_session_id: 'seed-session',
          last_session_at: createdAt,
          ...sessionPeriodFields(createdAt, 80),
        }),
      );
    });

    const db = aliceDb();
    for (const candidate of replayCandidates) {
      const scoreSum = 80 + candidate.score;
      const bestScore = Math.max(80, candidate.score);
      await assertFails(
        setDoc(
          doc(db, 'leaderboard', 'alice'),
          {
            total_xp: 50,
            quest_xp: 0,
            sessions_completed: 2,
            score_sum: scoreSum,
            average_score: scoreSum / 2,
            best_score: bestScore,
            last_session_at: createdAt,
            updated_at: serverTimestamp(),
            last_awarded_session_id: candidate.sessionId,
            ...periodFields({
              dayKey,
              dailyXp: 50,
              dailySessions: 2,
              dailyScoreSum: scoreSum,
              dailyAverageScore: scoreSum / 2,
              dailyBestScore: bestScore,
              monthKey,
            }),
          },
          { merge: true },
        ),
      );
    }
  });

  test('session award against a legacy doc must initialize the complete period block', async () => {
    const createdAt = Timestamp.fromDate(new Date('2026-06-01T04:00:00.000Z'));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'missing-period-session'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 90,
        created_at: createdAt,
      });
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const db = aliceDb();
    await assertFails(
      commitSessionAward(db, {
        sessionId: 'missing-period-session',
        score: 90,
        leaderboardUpdate: {
          total_xp: 50,
          quest_xp: 0,
          sessions_completed: 2,
          score_sum: 170,
          average_score: 85,
          best_score: 90,
          last_session_at: createdAt,
          updated_at: serverTimestamp(),
          last_awarded_session_id: 'missing-period-session',
        },
      }),
    );
  });

  test('session award rejects forged period XP, keys, counts, averages, and best score', async () => {
    const createdAt = Timestamp.fromDate(new Date('2026-06-01T04:00:00.000Z'));
    const oldFields = sessionPeriodFields(createdAt, 80);
    const validFields = periodFields({
      dayKey: oldFields.daily_key,
      dailyXp: 50,
      dailySessions: 2,
      dailyScoreSum: 170,
      dailyAverageScore: 85,
      dailyBestScore: 90,
      monthKey: oldFields.monthly_key,
    });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 'forged-period-session'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 90,
        created_at: createdAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', { ...oldFields }),
      );
    });

    const baseUpdate = {
      total_xp: 50,
      quest_xp: 0,
      sessions_completed: 2,
      score_sum: 170,
      average_score: 85,
      best_score: 90,
      last_session_at: createdAt,
      updated_at: serverTimestamp(),
      last_awarded_session_id: 'forged-period-session',
      ...validFields,
    };
    const forgeries = [
      { daily_xp: 999 },
      { daily_key: '20260602' },
      { daily_sessions_completed: 99 },
      { daily_average_score: 99 },
      { monthly_best_score: 100 },
    ];
    const db = aliceDb();
    for (const forgery of forgeries) {
      await assertFails(
        commitSessionAward(db, {
          sessionId: 'forged-period-session',
          score: 90,
          leaderboardUpdate: { ...baseUpdate, ...forgery },
        }),
      );
    }
  });

  test('same-period quest adds only XP and preserves session metrics', async () => {
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    const sessionMetrics = periodFields({
      dayKey: board.day_key,
      dailyXp: 25,
      dailySessions: 1,
      dailyScoreSum: 80,
      dailyAverageScore: 80,
      dailyBestScore: 80,
    });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), board);
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', { ...sessionMetrics }),
      );
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
    });
    claim.day_start = board.day_start;
    const nextPeriods = { ...sessionMetrics, daily_xp: 35, monthly_xp: 35 };
    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'daily_quest_claims', claimId), claim);
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        quest_xp: 10,
        total_xp: 35,
        last_claim_id: claimId,
        ...nextPeriods,
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());

    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().daily_xp, 35);
    assert.equal(after.data().daily_sessions_completed, 1);
    assert.equal(after.data().daily_score_sum, 80);
    assert.equal(after.data().monthly_sessions_completed, 1);
  });

  test('quest update rejects omitted, forged, or fabricated period state', async () => {
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    const currentPeriods = periodFields({
      dayKey: board.day_key,
      dailyXp: 25,
      dailySessions: 1,
      dailyScoreSum: 80,
      dailyAverageScore: 80,
      dailyBestScore: 80,
    });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), board);
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', { ...currentPeriods }),
      );
    });

    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
    });
    claim.day_start = board.day_start;
    const validPeriods = { ...currentPeriods, daily_xp: 35, monthly_xp: 35 };
    const attempts = [
      {},
      { ...validPeriods, daily_xp: 999 },
      { ...validPeriods, daily_key: '19990101' },
      { ...validPeriods, daily_sessions_completed: 2 },
      { ...validPeriods, monthly_score_sum: 90 },
    ];
    const db = aliceDb();
    for (const periodAttempt of attempts) {
      const batch = writeBatch(db);
      batch.set(doc(db, 'daily_quest_claims', claimId), claim);
      batch.set(
        doc(db, 'leaderboard', 'alice'),
        {
          quest_xp: 10,
          total_xp: 35,
          last_claim_id: claimId,
          ...periodAttempt,
        },
        { merge: true },
      );
      await assertFails(batch.commit());
    }
  });
});

describe('achievement claims + user cosmetics + equipped borders', () => {
  function achievementClaimPayload(userId, achievementId, rewardBorderId) {
    return {
      user_id: userId,
      achievement_id: achievementId,
      reward_border_id: rewardBorderId,
      claimed_at: serverTimestamp(),
    };
  }

  function cosmeticsCreatePayload(userId, borderIds, claimId) {
    return {
      user_id: userId,
      unlocked_border_ids: borderIds,
      last_achievement_claim_id: claimId,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    };
  }

  function cosmeticsUpdatePayload(userId, borderIds, claimId, createdAt) {
    return {
      user_id: userId,
      unlocked_border_ids: borderIds,
      last_achievement_claim_id: claimId,
      created_at: createdAt,
      updated_at: serverTimestamp(),
    };
  }

  async function claimFirstSteps(db) {
    const claimId = 'alice_first_steps';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'first_steps', 'starter_glow'));
    batch.set(doc(db, 'user_cosmetics', 'alice'), cosmeticsCreatePayload('alice', ['starter_glow'], claimId));
    await assertSucceeds(batch.commit());
  }

  test('1 valid achievement claim plus first cosmetics creation succeeds', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const cosmetics = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    assert.deepEqual(cosmetics.data().unlocked_border_ids, ['starter_glow']);
  });

  test('2 valid later claim appends exactly one border', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const before = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    const createdAt = before.data().created_at;
    const claimId = 'alice_sharp_pour';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'sharp_pour', 'cyan_orbit'));
    batch.set(
      doc(db, 'user_cosmetics', 'alice'),
      cosmeticsUpdatePayload('alice', ['starter_glow', 'cyan_orbit'], claimId, createdAt),
    );
    await assertSucceeds(batch.commit());
    const after = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    assert.deepEqual(after.data().unlocked_border_ids, ['starter_glow', 'cyan_orbit']);
  });

  test('3 standalone achievement claim is rejected', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'achievement_claims', 'alice_first_steps'),
        achievementClaimPayload('alice', 'first_steps', 'starter_glow'),
      ),
    );
  });

  test('4 cosmetics unlock without a fresh claim is rejected', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'user_cosmetics', 'alice'),
        cosmeticsCreatePayload('alice', ['starter_glow'], 'alice_first_steps'),
      ),
    );
  });

  test('5 unknown achievement is rejected', async () => {
    const db = aliceDb();
    const claimId = 'alice_not_real';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'not_real', 'starter_glow'));
    batch.set(doc(db, 'user_cosmetics', 'alice'), cosmeticsCreatePayload('alice', ['starter_glow'], claimId));
    await assertFails(batch.commit());
  });

  test('6 mismatched achievement-to-border reward is rejected', async () => {
    const db = aliceDb();
    const claimId = 'alice_first_steps';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'achievement_claims', claimId),
      achievementClaimPayload('alice', 'first_steps', 'gold_mastery'),
    );
    batch.set(doc(db, 'user_cosmetics', 'alice'), cosmeticsCreatePayload('alice', ['gold_mastery'], claimId));
    await assertFails(batch.commit());
  });

  test('7 duplicate achievement claim is rejected', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const before = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    const claimId = 'alice_first_steps';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'first_steps', 'starter_glow'));
    batch.set(
      doc(db, 'user_cosmetics', 'alice'),
      cosmeticsUpdatePayload('alice', ['starter_glow', 'bronze_ember'], 'alice_getting_started', before.data().created_at),
    );
    await assertFails(batch.commit());
  });

  test('8 replaying an old achievement claim is rejected', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const before = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    // Try to append a new border while pointing last_achievement_claim_id at the already-existing claim.
    await assertFails(
      setDoc(
        doc(db, 'user_cosmetics', 'alice'),
        cosmeticsUpdatePayload(
          'alice',
          ['starter_glow', 'cyan_orbit'],
          'alice_first_steps',
          before.data().created_at,
        ),
      ),
    );
  });

  test('9 removing an unlocked border is rejected', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const before = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    const claimId = 'alice_sharp_pour';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'sharp_pour', 'cyan_orbit'));
    batch.set(
      doc(db, 'user_cosmetics', 'alice'),
      cosmeticsUpdatePayload('alice', ['cyan_orbit'], claimId, before.data().created_at),
    );
    await assertFails(batch.commit());
  });

  test('10 replacing the unlocked list is rejected', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const before = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    const claimId = 'alice_sharp_pour';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'sharp_pour', 'cyan_orbit'));
    batch.set(
      doc(db, 'user_cosmetics', 'alice'),
      cosmeticsUpdatePayload('alice', ['bronze_ember', 'cyan_orbit'], claimId, before.data().created_at),
    );
    await assertFails(batch.commit());
  });

  test('11 adding two borders from one claim is rejected', async () => {
    const db = aliceDb();
    await claimFirstSteps(db);
    const before = await getDoc(doc(db, 'user_cosmetics', 'alice'));
    const claimId = 'alice_sharp_pour';
    const batch = writeBatch(db);
    batch.set(doc(db, 'achievement_claims', claimId), achievementClaimPayload('alice', 'sharp_pour', 'cyan_orbit'));
    batch.set(
      doc(db, 'user_cosmetics', 'alice'),
      cosmeticsUpdatePayload(
        'alice',
        ['starter_glow', 'cyan_orbit', 'gold_mastery'],
        claimId,
        before.data().created_at,
      ),
    );
    await assertFails(batch.commit());
  });

  test('12 cross-user cosmetics read/write is rejected', async () => {
    const alice = aliceDb();
    await claimFirstSteps(alice);

    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'user_cosmetics', 'alice')));
    await assertFails(
      setDoc(
        doc(bob, 'user_cosmetics', 'alice'),
        cosmeticsCreatePayload('alice', ['starter_glow'], 'alice_first_steps'),
      ),
    );
  });

  test('13 equipping a locked border is rejected', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice', { equipped_border_id: '' }));
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { equipped_border_id: 'gold_mastery', updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('14 equipping an unlocked border succeeds', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice', { equipped_border_id: '' }));
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { equipped_border_id: 'starter_glow', updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('15 unequipping succeeds', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', { equipped_border_id: 'starter_glow' }),
      );
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { equipped_border_id: '', updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('16 equip update cannot change total_xp', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice', { equipped_border_id: '' }));
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { equipped_border_id: 'starter_glow', total_xp: 999, updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('17 equip update cannot change quest_xp', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', { total_xp: 40, quest_xp: 15, equipped_border_id: '' }),
      );
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { equipped_border_id: 'starter_glow', quest_xp: 99, updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('18 equip update cannot change sessions_completed', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice', { equipped_border_id: '' }));
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'leaderboard', 'alice'),
        { equipped_border_id: 'starter_glow', sessions_completed: 99, updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('19 session award preserves equipped_border_id', async () => {
    const awardedAt = Timestamp.now();
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's1'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 80,
        created_at: Timestamp.now(),
      });
      await setDoc(doc(adminDb, 'sessions', 's2'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 100,
        created_at: awardedAt,
      });
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          total_xp: 25,
          sessions_completed: 1,
          score_sum: 80,
          average_score: 80,
          best_score: 80,
          last_awarded_session_id: 's1',
          quest_xp: 0,
          equipped_border_id: 'starter_glow',
        }),
      );
    });

    const db = aliceDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'leaderboard_processed_sessions', 's2'), {
      session_id: 's2',
      user_id: 'alice',
      score: 100,
      xp_awarded: 25,
      processed_at: Timestamp.now(),
    });
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        user_id: 'alice',
        display_name: 'Alice',
        total_xp: 50,
        sessions_completed: 2,
        score_sum: 180,
        average_score: 90,
        best_score: 100,
        last_session_at: Timestamp.now(),
        updated_at: Timestamp.now(),
        last_awarded_session_id: 's2',
        quest_xp: 0,
        equipped_border_id: 'starter_glow',
        ...sessionPeriodFields(awardedAt, 100),
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());
    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().equipped_border_id, 'starter_glow');
  });

  test('20 daily quest claim preserves equipped_border_id', async () => {
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), board);
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', {
          total_xp: 25,
          quest_xp: 0,
          equipped_border_id: 'starter_glow',
        }),
      );
    });

    const db = aliceDb();
    const { id: claimId, data: claim } = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: now,
    });
    claim.day_start = board.day_start;
    const batch = writeBatch(db);
    batch.set(doc(db, 'daily_quest_claims', claimId), claim);
    batch.set(
      doc(db, 'leaderboard', 'alice'),
      {
        quest_xp: CLAIM_QUEST_XP,
        total_xp: 25 + CLAIM_QUEST_XP,
        last_claim_id: claimId,
        equipped_border_id: 'starter_glow',
        ...questPeriodFields(board.day_key, CLAIM_QUEST_XP),
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());
    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().equipped_border_id, 'starter_glow');
  });

  test('21 public profile metadata update preserves equipped_border_id', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'leaderboard', 'alice'),
        leaderboardSeed('alice', { equipped_border_id: 'starter_glow' }),
      );
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'leaderboard', 'alice'), { display_name: 'Alice Renamed' }, { merge: true }),
    );
    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().equipped_border_id, 'starter_glow');
    assert.equal(after.data().display_name, 'Alice Renamed');
  });

  test('22 legacy leaderboard documents without equipped_border_id still validate normally', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'leaderboard', 'alice'), { display_name: 'Alice Legacy' }, { merge: true }),
    );
    const after = await getDoc(doc(db, 'leaderboard', 'alice'));
    assert.equal(after.data().display_name, 'Alice Legacy');
    assert.equal(after.data().equipped_border_id, undefined);
  });
});

function publicProfileRoot(userId, overrides = {}) {
  return {
    user_id: userId,
    display_name: 'Alice',
    visibility: 'private',
    created_at: Timestamp.now(),
    updated_at: Timestamp.now(),
    schema_version: 1,
    ...overrides,
  };
}

function publicProfileSummary(overrides = {}) {
  return {
    total_duration_seconds: 120,
    completed_movement_names: ['basic_pour'],
    updated_at: Timestamp.now(),
    ...overrides,
  };
}

function publicProfileSession(userId, sessionId, overrides = {}) {
  return {
    session_id: sessionId,
    user_id: userId,
    movement_name: 'basic_pour',
    difficulty: 'easy',
    score: 85,
    duration_seconds: 60,
    prop_type: 'bottle',
    created_at: Timestamp.now(),
    ...overrides,
  };
}

function profileVisit(profileOwnerId, viewerId, overrides = {}) {
  const now = Timestamp.now();
  return {
    profile_owner_id: profileOwnerId,
    viewer_id: viewerId,
    first_viewed_at: now,
    last_viewed_at: now,
    ...overrides,
  };
}

async function seedViewerRole(role) {
  await seedBypassingRules(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', 'bob'),
      role == null ? {} : { role },
    );
  });
}

async function seedProtectedProgressScenario({
  visibility = 'public',
  viewerRole = ROLE_TEACHER,
  link = null,
} = {}) {
  await seedBypassingRules(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', 'bob'),
      viewerRole == null ? {} : { role: viewerRole },
    );
    await setDoc(
      doc(adminDb, 'public_profiles', 'alice'),
      publicProfileRoot('alice', { visibility }),
    );
    await setDoc(
      doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'),
      publicProfileSummary(),
    );
    await setDoc(doc(adminDb, 'sessions', 'alice-session'), { user_id: 'alice' });
    await setDoc(
      doc(adminDb, 'public_profiles', 'alice', 'sessions', 'alice-session'),
      publicProfileSession('alice', 'alice-session'),
    );
    await setDoc(
      doc(adminDb, 'public_profiles', 'alice', 'achievements', 'first_steps'),
      {
        user_id: 'alice',
        achievement_id: 'first_steps',
        claimed_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      },
    );
    if (link != null) {
      await setDoc(doc(adminDb, 'teacher_student_links', 'bob_alice'), {
        teacher_id: 'bob',
        trainee_id: 'alice',
        status: 'approved',
        progress_access: link,
        ...(link === 'granted'
          ? {
              progress_access_version: 1,
              progress_access_granted_at: Timestamp.now(),
            }
          : {}),
      });
    }
  });
}

describe('public_profiles', () => {
  test('signed-in user can read any public profile root', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice')));
  });

  test('owner can create a valid public profile root', async () => {
    const db = aliceDb();
    await assertSucceeds(setDoc(doc(db, 'public_profiles', 'alice'), publicProfileRoot('alice')));
  });

  test('cross-user cannot create another user public profile root', async () => {
    const bob = bobDb();
    await assertFails(setDoc(doc(bob, 'public_profiles', 'alice'), publicProfileRoot('alice')));
  });

  test('owner can update visibility to public', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(
        doc(db, 'public_profiles', 'alice'),
        { visibility: 'public', updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('cross-user cannot update another user public profile root', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const bob = bobDb();
    await assertFails(
      setDoc(
        doc(bob, 'public_profiles', 'alice'),
        { visibility: 'public', updated_at: Timestamp.now() },
        { merge: true },
      ),
    );
  });

  test('owner can read summary for private profile', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      );
    });

    const db = aliceDb();
    await assertSucceeds(getDoc(doc(db, 'public_profiles', 'alice', 'details', 'summary')));
  });

  test('Trainee cannot read another user private profile summary', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      );
    });

    await seedViewerRole(ROLE_TRAINEE);
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
  });

  test('Trainee with canonical role casing can read another user public profile summary', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice'),
        publicProfileRoot('alice', { visibility: 'public' }),
      );
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      );
    });

    await seedViewerRole(ROLE_TRAINEE);
    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
  });

  test('owner can write summary projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'public_profiles', 'alice', 'details', 'summary'), publicProfileSummary()),
    );
  });

  test('owner canonical replacement of a legacy summary succeeds without loosening keys', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'), {
        ...publicProfileSummary(),
        legacy_unknown_field: 1,
      });
    });

    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
        { merge: true },
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(db, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      ),
    );
    const bob = bobDb();
    await assertFails(
      setDoc(
        doc(bob, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      ),
    );
  });

  test('cross-user cannot write summary projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const bob = bobDb();
    await assertFails(
      setDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary'), publicProfileSummary()),
    );
  });

  test('session projection requires backing session document', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'public_profiles', 'alice', 'sessions', 's1'),
        publicProfileSession('alice', 's1'),
      ),
    );
  });

  test('owner can write session projection when session exists', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(doc(adminDb, 'sessions', 's1'), { user_id: 'alice', score: 85 });
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(
        doc(db, 'public_profiles', 'alice', 'sessions', 's1'),
        publicProfileSession('alice', 's1'),
      ),
    );
  });

  test('Trainee cannot read another user private session projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(doc(adminDb, 'sessions', 's1'), { user_id: 'alice', score: 85 });
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'sessions', 's1'),
        publicProfileSession('alice', 's1'),
      );
    });

    await seedViewerRole(ROLE_TRAINEE);
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 's1')));
  });

  test('Trainee with canonical role casing can read another user public session projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice'),
        publicProfileRoot('alice', { visibility: 'public' }),
      );
      await setDoc(doc(adminDb, 'sessions', 's1'), { user_id: 'alice', score: 85 });
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'sessions', 's1'),
        publicProfileSession('alice', 's1'),
      );
    });

    await seedViewerRole(ROLE_TRAINEE);
    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 's1')));
  });

  test('Teacher cannot use a public profile to read protected summary or sessions', async () => {
    await seedProtectedProgressScenario();
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertFails(
      getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 'alice-session')),
    );
  });

  test('Teacher cannot read protected private progress without consent', async () => {
    await seedProtectedProgressScenario({ visibility: 'private' });
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertFails(
      getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 'alice-session')),
    );
  });

  test('approved Teacher relationship without progress consent cannot read protected progress', async () => {
    await seedProtectedProgressScenario({ visibility: 'private', link: 'none' });
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertFails(
      getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 'alice-session')),
    );
  });

  test('approved Teacher relationship with explicit supported consent reads only sanitized progress', async () => {
    await seedProtectedProgressScenario({ visibility: 'private', link: 'granted' });
    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertSucceeds(
      getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 'alice-session')),
    );
    await assertFails(getDoc(doc(bob, 'sessions', 'alice-session')));
    await assertFails(
      getDoc(doc(bob, 'public_profiles', 'alice', 'achievements', 'first_steps')),
    );
  });

  test('unknown role fails closed for protected public-profile data', async () => {
    await seedProtectedProgressScenario({ viewerRole: ROLE_ADMIN });
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertFails(
      getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 'alice-session')),
    );
  });

  test('missing legacy role remains Trainee-compatible for public profile data', async () => {
    await seedProtectedProgressScenario({ viewerRole: null });
    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertSucceeds(
      getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 'alice-session')),
    );
  });

  test('owner can write achievement projection with known achievement id', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const db = aliceDb();
    await assertSucceeds(
      setDoc(doc(db, 'public_profiles', 'alice', 'achievements', 'first_steps'), {
        user_id: 'alice',
        achievement_id: 'first_steps',
        claimed_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      }),
    );
  });

  test('other user cannot write achievement projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
    });

    const bob = bobDb();
    await assertFails(
      setDoc(doc(bob, 'public_profiles', 'alice', 'achievements', 'first_steps'), {
        user_id: 'alice',
        achievement_id: 'first_steps',
        claimed_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      }),
    );
  });

  test('other user cannot read private achievement projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(doc(adminDb, 'public_profiles', 'alice', 'achievements', 'first_steps'), {
        user_id: 'alice',
        achievement_id: 'first_steps',
        claimed_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'achievements', 'first_steps')));
  });

  test('other user can read public achievement projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice'),
        publicProfileRoot('alice', { visibility: 'public' }),
      );
      await setDoc(doc(adminDb, 'public_profiles', 'alice', 'achievements', 'first_steps'), {
        user_id: 'alice',
        achievement_id: 'first_steps',
        claimed_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    await seedViewerRole(ROLE_TRAINEE);
    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice', 'achievements', 'first_steps')));
  });
});

describe('profile_visits', () => {
  test('viewer can create a visit record for another profile', async () => {
    const bob = bobDb();
    await assertSucceeds(
      setDoc(
        doc(bob, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob'),
      ),
    );
  });

  test('user cannot create a self-visit record', async () => {
    const db = aliceDb();
    await assertFails(
      setDoc(
        doc(db, 'profile_visits', 'alice', 'visitors', 'alice'),
        profileVisit('alice', 'alice'),
      ),
    );
  });

  test('profile owner can list visitors', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob'),
      );
    });

    const db = aliceDb();
    await assertSucceeds(getDocs(collection(db, 'profile_visits', 'alice', 'visitors')));
  });

  test('non-owner cannot list another user visitors', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob'),
      );
    });

    const bob = bobDb();
    await assertFails(getDocs(collection(bob, 'profile_visits', 'alice', 'visitors')));
  });

  test('viewer can read own visit record', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob'),
      );
    });

    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'profile_visits', 'alice', 'visitors', 'bob')));
  });

  test('viewer can update last_viewed_at while preserving first_viewed_at', async () => {
    const firstViewedAt = Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'));
    const lastViewedAt = Timestamp.fromDate(new Date('2026-01-02T00:00:00Z'));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob', {
          first_viewed_at: firstViewedAt,
          last_viewed_at: firstViewedAt,
        }),
      );
    });

    const bob = bobDb();
    await assertSucceeds(
      setDoc(
        doc(bob, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob', {
          first_viewed_at: firstViewedAt,
          last_viewed_at: lastViewedAt,
        }),
      ),
    );
  });

  test('viewer cannot change first_viewed_at on update', async () => {
    const firstViewedAt = Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'));
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob', { first_viewed_at: firstViewedAt }),
      );
    });

    const bob = bobDb();
    await assertFails(
      setDoc(
        doc(bob, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob', {
          first_viewed_at: Timestamp.fromDate(new Date('2026-02-01T00:00:00Z')),
        }),
      ),
    );
  });
});

describe('account self-erasure deletes', () => {
  test('owner can delete own leaderboard doc; other user cannot', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard', 'alice'), leaderboardSeed('alice'));
    });

    const bob = bobDb();
    await assertFails(deleteDoc(doc(bob, 'leaderboard', 'alice')));

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'leaderboard', 'alice')));
  });

  test('owner can delete own leaderboard_processed_sessions marker; other user cannot', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'leaderboard_processed_sessions', 's1'), {
        session_id: 's1',
        user_id: 'alice',
        movement_name: 'Hand Stall',
        score: 80,
        xp_awarded: 25,
        processed_at: Timestamp.now(),
      });
    });

    const bob = bobDb();
    await assertFails(deleteDoc(doc(bob, 'leaderboard_processed_sessions', 's1')));

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'leaderboard_processed_sessions', 's1')));
  });

  test('owner can delete an existing own daily_quest_board', async () => {
    const { id, data } = boardData('alice');
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', id), data);
    });

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'daily_quest_boards', id)));
  });

  test('owner can delete a nonexistent canonical own daily_quest_board (idempotent purge)', async () => {
    // Account erasure enumerates deterministic board IDs from created_at→today.
    // Many of those docs never existed; delete must still succeed as a no-op.
    const missingOwnBoardId = 'alice_20240102';
    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'daily_quest_boards', missingOwnBoardId)));
  });

  test('alice cannot delete a nonexistent canonical board belonging to bob', async () => {
    const missingBobBoardId = 'bob_20240102';
    const alice = aliceDb();
    await assertFails(deleteDoc(doc(alice, 'daily_quest_boards', missingBobBoardId)));
  });

  test('alice cannot delete bob existing daily_quest_board', async () => {
    const { id, data } = boardData('bob');
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', id), data);
    });

    const alice = aliceDb();
    await assertFails(deleteDoc(doc(alice, 'daily_quest_boards', id)));
  });

  test('daily_quest_boards list/query remains denied during account erasure coverage', async () => {
    const { id, data } = boardData('alice');
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', id), data);
    });

    const alice = aliceDb();
    await assertFails(
      getDocs(query(collection(alice, 'daily_quest_boards'), where('user_id', '==', 'alice'))),
    );
  });

  test('owner can idempotently delete already-missing own cosmetics/leaderboard/public/users docs', async () => {
    // Path-owned deletes must tolerate retry after a partial purge.
    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'user_cosmetics', 'alice')));
    await assertSucceeds(deleteDoc(doc(alice, 'leaderboard', 'alice')));
    await assertSucceeds(deleteDoc(doc(alice, 'public_profiles', 'alice', 'details', 'summary')));
    await assertSucceeds(deleteDoc(doc(alice, 'public_profiles', 'alice')));
    await assertSucceeds(deleteDoc(doc(alice, 'users', 'alice')));
  });

  test('alice cannot delete bob missing cosmetics/leaderboard/public/users docs', async () => {
    const alice = aliceDb();
    await assertFails(deleteDoc(doc(alice, 'user_cosmetics', 'bob')));
    await assertFails(deleteDoc(doc(alice, 'leaderboard', 'bob')));
    await assertFails(deleteDoc(doc(alice, 'public_profiles', 'bob', 'details', 'summary')));
    await assertFails(deleteDoc(doc(alice, 'public_profiles', 'bob')));
    await assertFails(deleteDoc(doc(alice, 'users', 'bob')));
  });

  test('owner can delete own daily_quest_claim; other user cannot', async () => {
    const now = new Date();
    const { id: boardId, data: board } = boardData('alice', now);
    const claim = claimData({
      userId: 'alice',
      boardId,
      dayKey: board.day_key,
      dayStart: board.day_start.toDate(),
    });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', boardId), board);
      await setDoc(doc(adminDb, 'daily_quest_claims', claim.id), claim.data);
    });

    const bob = bobDb();
    await assertFails(deleteDoc(doc(bob, 'daily_quest_claims', claim.id)));

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'daily_quest_claims', claim.id)));
  });

  test('owner can delete own achievement_claim and user_cosmetics', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'achievement_claims', 'alice_first_steps'), {
        user_id: 'alice',
        achievement_id: 'first_steps',
        reward_border_id: 'starter_glow',
        claimed_at: Timestamp.now(),
      });
      await setDoc(doc(adminDb, 'user_cosmetics', 'alice'), {
        user_id: 'alice',
        unlocked_border_ids: ['starter_glow'],
        last_achievement_claim_id: 'alice_first_steps',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const bob = bobDb();
    await assertFails(deleteDoc(doc(bob, 'achievement_claims', 'alice_first_steps')));
    await assertFails(deleteDoc(doc(bob, 'user_cosmetics', 'alice')));

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'achievement_claims', 'alice_first_steps')));
    await assertSucceeds(deleteDoc(doc(alice, 'user_cosmetics', 'alice')));
  });

  test('owner can delete public_profiles root and subdocs', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      );
      await setDoc(doc(adminDb, 'public_profiles', 'alice', 'achievements', 'first_steps'), {
        user_id: 'alice',
        achievement_id: 'first_steps',
        claimed_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });

    const bob = bobDb();
    await assertFails(deleteDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
    await assertFails(deleteDoc(doc(bob, 'public_profiles', 'alice')));

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'public_profiles', 'alice', 'details', 'summary')));
    await assertSucceeds(
      deleteDoc(doc(alice, 'public_profiles', 'alice', 'achievements', 'first_steps')),
    );
    await assertSucceeds(deleteDoc(doc(alice, 'public_profiles', 'alice')));
  });

  test('session owner can delete feedback while session exists; non-owner cannot', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's1'), {
        user_id: 'alice',
        movement_name: 'Hand Stall',
        difficulty: 'Easy',
        score: 80,
        duration_seconds: 60,
        prop_type: 'Bottle',
        created_at: Timestamp.now(),
      });
      await setDoc(doc(adminDb, 'feedbacks', 'f1'), {
        session_id: 's1',
        message: 'Nice',
        feedback_type: 'positive',
        created_at: Timestamp.now(),
      });
    });

    const bob = bobDb();
    await assertFails(deleteDoc(doc(bob, 'feedbacks', 'f1')));

    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'feedbacks', 'f1')));
  });

  test('profile owner and viewer can delete visit rows; third party cannot', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'alice', 'visitors', 'bob'),
        profileVisit('alice', 'bob'),
      );
      await setDoc(
        doc(adminDb, 'profile_visits', 'carol', 'visitors', 'alice'),
        profileVisit('carol', 'alice'),
      );
    });

    // Third party cannot delete alice's inbound visit from bob.
    // (Use a fresh auth context for carol.)
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(deleteDoc(doc(carol, 'profile_visits', 'alice', 'visitors', 'bob')));

    // Owner can delete inbound visitor row.
    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'profile_visits', 'alice', 'visitors', 'bob')));

    // Viewer can delete own outbound row on another profile.
    await assertSucceeds(deleteDoc(doc(alice, 'profile_visits', 'carol', 'visitors', 'alice')));
  });

  test('viewer can collection-group list own outbound visits', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(
        doc(adminDb, 'profile_visits', 'bob', 'visitors', 'alice'),
        profileVisit('bob', 'alice'),
      );
      await setDoc(
        doc(adminDb, 'profile_visits', 'carol', 'visitors', 'alice'),
        profileVisit('carol', 'alice'),
      );
    });

    const alice = aliceDb();
    const q = query(collectionGroup(alice, 'visitors'), where('viewer_id', '==', 'alice'));
    await assertSucceeds(getDocs(q));
  });
});

describe('users role constraints', () => {
  function userProfile(role) {
    return {
      first_name: 'Ada',
      last_name: 'Lovelace',
      full_name: 'Ada Lovelace',
      email: 'ada@example.com',
      role,
    };
  }

  test('owner can create a Trainee profile', async () => {
    const alice = aliceDb();
    await assertSucceeds(setDoc(doc(alice, 'users', 'alice'), userProfile(ROLE_TRAINEE)));
  });

  test('owner can create a Teacher profile', async () => {
    const bob = bobDb();
    await assertSucceeds(setDoc(doc(bob, 'users', 'bob'), userProfile(ROLE_TEACHER)));
  });

  test('owner cannot create an Admin profile', async () => {
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, 'users', 'carol'), userProfile(ROLE_ADMIN)));
  });

  test('non-owner cannot create another user document', async () => {
    const alice = aliceDb();
    await assertFails(setDoc(doc(alice, 'users', 'bob'), userProfile(ROLE_TRAINEE)));
  });

  test('owner can update other fields while role stays unchanged', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'alice'), userProfile(ROLE_TRAINEE));
    });

    const alice = aliceDb();
    await assertSucceeds(
      updateDoc(doc(alice, 'users', 'alice'), { first_name: 'Augusta' }),
    );
  });

  test('owner cannot change role on update, including to Admin or Teacher', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'alice'), userProfile(ROLE_TRAINEE));
    });

    const alice = aliceDb();
    await assertFails(updateDoc(doc(alice, 'users', 'alice'), { role: ROLE_TEACHER }));
    await assertFails(updateDoc(doc(alice, 'users', 'alice'), { role: ROLE_ADMIN }));
  });

  test('non-owner cannot read or update a user document', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'alice'), userProfile(ROLE_TRAINEE));
    });

    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'users', 'alice')));
    await assertFails(updateDoc(doc(bob, 'users', 'alice'), { first_name: 'Eve' }));
  });
});

describe.skip('retired trainee-owned invites and links (Phase 2A)', () => {
  const INVITE_ID = '7KPMXR4DQ2WT';
  const LINK_ID = 'bob_alice';

  function verifiedUser(uid, email = `${uid}@school.edu`) {
    return testEnv.authenticatedContext(uid, {
      email,
      email_verified: true,
    }).firestore();
  }

  function unverifiedUser(uid) {
    return testEnv.authenticatedContext(uid, {
      email: `${uid}@school.edu`,
      email_verified: false,
    }).firestore();
  }

  function traineeProfile(overrides = {}) {
    return {
      first_name: 'Ada',
      last_name: 'Lovelace',
      full_name: 'Ada Lovelace',
      email: 'ada@example.com',
      role: ROLE_TRAINEE,
      ...overrides,
    };
  }

  function teacherProfile(overrides = {}) {
    return {
      first_name: 'Grace',
      last_name: 'Hopper',
      full_name: 'Grace Hopper',
      email: 'grace@example.com',
      role: ROLE_TEACHER,
      ...overrides,
    };
  }

  function inviteData(overrides = {}) {
    const created = new Date();
    return {
      trainee_id: 'alice',
      trainee_display_name: 'Ada Lovelace',
      created_at: Timestamp.fromDate(created),
      expires_at: Timestamp.fromDate(new Date(created.getTime() + 7 * 24 * 60 * 60 * 1000)),
      ...overrides,
    };
  }

  function linkData(overrides = {}) {
    const created = new Date();
    return {
      teacher_id: 'bob',
      trainee_id: 'alice',
      teacher_display_name: 'Grace Hopper',
      trainee_display_name: 'Ada Lovelace',
      status: 'pending',
      invite_id: INVITE_ID,
      created_at: Timestamp.fromDate(created),
      updated_at: Timestamp.fromDate(created),
      ...overrides,
    };
  }

  async function seedRoster({
    invite = true,
    inviteOverrides = {},
    link = false,
    linkOverrides = {},
    session = false,
  } = {}) {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'alice'), traineeProfile());
      await setDoc(doc(adminDb, 'users', 'bob'), teacherProfile());
      await setDoc(doc(adminDb, 'users', 'carol'), traineeProfile({
        first_name: 'Carol',
        last_name: 'Shaw',
        full_name: 'Carol Shaw',
        email: 'carol@example.com',
      }));
      if (invite) {
        await setDoc(doc(adminDb, 'teacher_invites', INVITE_ID), inviteData(inviteOverrides));
      }
      if (link) {
        await setDoc(doc(adminDb, 'teacher_student_links', LINK_ID), linkData(linkOverrides));
      }
      if (session) {
        await setDoc(doc(adminDb, 'sessions', 'alice-session'), {
          user_id: 'alice',
          movement_name: 'Hand Stall',
          difficulty: 'Easy',
          duration_seconds: 60,
          prop_type: 'bottle',
          created_at: Timestamp.now(),
          assessment_version: 2,
          rubric: {
            technique: 2,
            stability: 2,
            completion: 2,
            prop_positioning: 2,
          },
          rubric_total: 8,
          performance_level: 'competent',
        });
      }
    });
  }

  test('trainee can create own invite with matching profile snapshot', async () => {
    await seedRoster({ invite: false });
    const alice = aliceDb();
    const created = new Date();
    await assertSucceeds(setDoc(doc(alice, 'teacher_invites', INVITE_ID), {
      trainee_id: 'alice',
      trainee_display_name: 'Ada Lovelace',
      created_at: serverTimestamp(),
      expires_at: Timestamp.fromDate(new Date(created.getTime() + 7 * 24 * 60 * 60 * 1000)),
    }));
  });

  test('trainee cannot create invite for another trainee', async () => {
    await seedRoster({ invite: false });
    const alice = aliceDb();
    const created = new Date();
    await assertFails(setDoc(doc(alice, 'teacher_invites', INVITE_ID), {
      trainee_id: 'carol',
      trainee_display_name: 'Carol Shaw',
      created_at: serverTimestamp(),
      expires_at: Timestamp.fromDate(new Date(created.getTime() + 7 * 24 * 60 * 60 * 1000)),
    }));
  });

  test('trainee cannot invent another person display name on own invite', async () => {
    await seedRoster({ invite: false });
    const alice = aliceDb();
    const created = new Date();
    await assertFails(setDoc(doc(alice, 'teacher_invites', INVITE_ID), {
      trainee_id: 'alice',
      trainee_display_name: 'Carol Shaw',
      created_at: serverTimestamp(),
      expires_at: Timestamp.fromDate(new Date(created.getTime() + 7 * 24 * 60 * 60 * 1000)),
    }));
  });

  test('another account cannot modify or revoke the invite', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    await assertFails(updateDoc(doc(bob, 'teacher_invites', INVITE_ID), {
      trainee_id: 'bob',
    }));
    await assertFails(deleteDoc(doc(bob, 'teacher_invites', INVITE_ID)));
    const alice = aliceDb();
    await assertSucceeds(deleteDoc(doc(alice, 'teacher_invites', INVITE_ID)));
  });

  test('invite collection cannot be listed', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    await assertFails(getDocs(collection(bob, 'teacher_invites')));
    const alice = aliceDb();
    await assertFails(getDocs(collection(alice, 'teacher_invites')));
  });

  test('exact valid invite can be resolved by a signed-in user', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    await assertSucceeds(getDoc(doc(bob, 'teacher_invites', INVITE_ID)));
  });

  test('existing invite cannot be overwritten by a later set', async () => {
    await seedRoster();
    const alice = aliceDb();
    const bob = verifiedUser('bob');
    const created = new Date();
    const payload = {
      trainee_id: 'alice',
      trainee_display_name: 'Ada Lovelace',
      created_at: serverTimestamp(),
      expires_at: Timestamp.fromDate(new Date(created.getTime() + 7 * 24 * 60 * 60 * 1000)),
    };
    // set() on an existing invite is an update; updates are denied, which is
    // the TOCTOU protection for createOrRotateInvite collision retries.
    await assertFails(setDoc(doc(alice, 'teacher_invites', INVITE_ID), payload));
    await assertFails(setDoc(doc(bob, 'teacher_invites', INVITE_ID), {
      ...payload,
      trainee_id: 'bob',
      trainee_display_name: 'Grace Hopper',
    }));
  });

  test('expired invite cannot create a request', async () => {
    const expired = new Date(Date.now() - 60 * 1000);
    await seedRoster({
      inviteOverrides: {
        created_at: Timestamp.fromDate(new Date(expired.getTime() - 7 * 24 * 60 * 60 * 1000)),
        expires_at: Timestamp.fromDate(expired),
      },
    });
    const bob = verifiedUser('bob');
    await assertFails(setDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      ...linkData(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
  });

  test('verified teacher can create pending relationship with a valid invite', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    await assertSucceeds(setDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      ...linkData(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
  });

  test('unverified email cannot create a pending relationship', async () => {
    await seedRoster();
    const bob = unverifiedUser('bob');
    await assertFails(setDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      ...linkData(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
  });

  test('arbitrary trainee_id cannot be targeted', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    await assertFails(setDoc(doc(bob, 'teacher_student_links', 'bob_carol'), {
      ...linkData(),
      trainee_id: 'carol',
      trainee_display_name: 'Carol Shaw',
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
  });

  test('duplicate Teacher/Trainee relationship cannot bypass deterministic ID', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    await assertFails(setDoc(doc(bob, 'teacher_student_links', 'bob-alice'), {
      ...linkData(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
  });

  test('teacher cannot approve their own request', async () => {
    await seedRoster({ link: true });
    const bob = verifiedUser('bob');
    await assertFails(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      status: 'approved',
      updated_at: serverTimestamp(),
    }));
  });

  test('correct trainee can approve and later revoke', async () => {
    await seedRoster({ link: true });
    const alice = aliceDb();
    await assertSucceeds(updateDoc(doc(alice, 'teacher_student_links', LINK_ID), {
      status: 'approved',
      updated_at: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(alice, 'teacher_student_links', LINK_ID), {
      status: 'revoked',
      updated_at: serverTimestamp(),
    }));
  });

  test('correct trainee can reject', async () => {
    await seedRoster({ link: true });
    const alice = aliceDb();
    await assertSucceeds(updateDoc(doc(alice, 'teacher_student_links', LINK_ID), {
      status: 'rejected',
      updated_at: serverTimestamp(),
    }));
  });

  test('teacher can cancel their own pending request', async () => {
    await seedRoster({ link: true });
    const bob = verifiedUser('bob');
    await assertSucceeds(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      status: 'cancelled',
      updated_at: serverTimestamp(),
    }));
  });

  test('third party cannot read the relationship', async () => {
    await seedRoster({ link: true });
    const carol = verifiedUser('carol');
    await assertFails(getDoc(doc(carol, 'teacher_student_links', LINK_ID)));
  });

  test('teacher can list own relationships', async () => {
    await seedRoster({ link: true });
    const bob = verifiedUser('bob');
    await assertSucceeds(getDocs(query(
      collection(bob, 'teacher_student_links'),
      where('teacher_id', '==', 'bob'),
    )));
  });

  test('trainee can list own relationships', async () => {
    await seedRoster({ link: true });
    const alice = aliceDb();
    await assertSucceeds(getDocs(query(
      collection(alice, 'teacher_student_links'),
      where('trainee_id', '==', 'alice'),
    )));
  });

  test('teacher cannot read another teacher roster', async () => {
    await seedRoster({ link: true });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'dana'), teacherProfile({
        first_name: 'Dana',
        last_name: 'Scully',
        full_name: 'Dana Scully',
        email: 'dana@example.com',
      }));
    });
    const dana = verifiedUser('dana');
    await assertFails(getDoc(doc(dana, 'teacher_student_links', LINK_ID)));
    await assertFails(getDocs(query(
      collection(dana, 'teacher_student_links'),
      where('teacher_id', '==', 'bob'),
    )));
  });

  test('trainee cannot read another trainee requests', async () => {
    await seedRoster({ link: true });
    const carol = verifiedUser('carol');
    await assertFails(getDocs(query(
      collection(carol, 'teacher_student_links'),
      where('trainee_id', '==', 'alice'),
    )));
  });

  test('participant IDs cannot be mutated', async () => {
    await seedRoster({ link: true });
    const alice = aliceDb();
    await assertFails(updateDoc(doc(alice, 'teacher_student_links', LINK_ID), {
      trainee_id: 'carol',
      status: 'approved',
      updated_at: serverTimestamp(),
    }));
    const bob = verifiedUser('bob');
    await assertFails(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      teacher_id: 'dana',
      status: 'cancelled',
      updated_at: serverTimestamp(),
    }));
  });

  test('approved relationship does not grant session reads', async () => {
    await seedRoster({
      link: true,
      session: true,
      linkOverrides: { status: 'approved' },
    });
    const bob = verifiedUser('bob');
    await assertFails(getDoc(doc(bob, 'sessions', 'alice-session')));
    const alice = aliceDb();
    await assertSucceeds(getDoc(doc(alice, 'sessions', 'alice-session')));
  });

  test('users.role Teacher is not enough to browse links', async () => {
    await seedRoster({ link: true });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'eve'), teacherProfile({
        first_name: 'Eve',
        last_name: 'Agent',
        full_name: 'Eve Agent',
        email: 'eve@school.edu',
      }));
    });
    const eve = verifiedUser('eve');
    await assertFails(getDocs(collection(eve, 'teacher_student_links')));
  });

  // requestLink() must discover existing rows with this teacher_id-constrained
  // query. Exact get of a missing deterministic ID is denied because
  // isLinkParticipant() requires resource.data.
  function existingLinkLookup(db, teacherId, traineeId) {
    return getDocs(query(
      collection(db, 'teacher_student_links'),
      where('teacher_id', '==', teacherId),
      where('trainee_id', '==', traineeId),
      limit(1),
    ));
  }

  function rerequestUpdate() {
    return {
      teacher_display_name: 'Grace Hopper',
      trainee_display_name: 'Ada Lovelace',
      status: 'pending',
      invite_id: INVITE_ID,
      updated_at: serverTimestamp(),
    };
  }

  test('teacher with no links can query then create a pending relationship', async () => {
    await seedRoster();
    const bob = verifiedUser('bob');
    const linkRef = doc(bob, 'teacher_student_links', LINK_ID);

    await assertFails(getDoc(linkRef));
    await assertFails(getDocs(collection(bob, 'teacher_student_links')));

    const lookup = await assertSucceeds(existingLinkLookup(bob, 'bob', 'alice'));
    assert.equal(lookup.size, 0);

    const ownRoster = await assertSucceeds(getDocs(query(
      collection(bob, 'teacher_student_links'),
      where('teacher_id', '==', 'bob'),
    )));
    assert.equal(ownRoster.size, 0);

    await assertSucceeds(setDoc(linkRef, {
      ...linkData(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));

    await assertSucceeds(getDoc(linkRef));
    const afterCreate = await assertSucceeds(existingLinkLookup(bob, 'bob', 'alice'));
    assert.equal(afterCreate.size, 1);
    assert.equal(afterCreate.docs[0].id, LINK_ID);
    assert.equal(afterCreate.docs[0].data().status, 'pending');
  });

  test('unrelated teacher cannot discover another teacher relationship', async () => {
    await seedRoster({ link: true });
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'users', 'dana'), teacherProfile({
        first_name: 'Dana',
        last_name: 'Scully',
        full_name: 'Dana Scully',
        email: 'dana@example.com',
      }));
    });
    const dana = verifiedUser('dana');
    await assertFails(getDoc(doc(dana, 'teacher_student_links', LINK_ID)));
    await assertFails(existingLinkLookup(dana, 'bob', 'alice'));
    const ownLookup = await assertSucceeds(existingLinkLookup(dana, 'dana', 'alice'));
    assert.equal(ownLookup.size, 0);
  });

  test('existing pending relationship cannot be duplicated', async () => {
    await seedRoster({ link: true });
    const bob = verifiedUser('bob');
    await assertFails(setDoc(doc(bob, 'teacher_student_links', LINK_ID), {
      ...linkData(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), rerequestUpdate()));
  });

  test('approved relationship cannot be reset to pending', async () => {
    await seedRoster({ link: true, linkOverrides: { status: 'approved' } });
    const bob = verifiedUser('bob');
    await assertFails(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), rerequestUpdate()));
  });

  test('rejected relationship may be securely re-requested with a current invite', async () => {
    await seedRoster({ link: true, linkOverrides: { status: 'rejected' } });
    const bob = verifiedUser('bob');
    await assertSucceeds(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), rerequestUpdate()));
    const snap = await getDoc(doc(bob, 'teacher_student_links', LINK_ID));
    assert.equal(snap.data().status, 'pending');
    assert.equal(snap.data().teacher_id, 'bob');
    assert.equal(snap.data().trainee_id, 'alice');
  });

  test('cancelled relationship may be securely re-requested', async () => {
    await seedRoster({ link: true, linkOverrides: { status: 'cancelled' } });
    const bob = verifiedUser('bob');
    await assertSucceeds(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), rerequestUpdate()));
  });

  test('revoked relationship may be securely re-requested', async () => {
    await seedRoster({ link: true, linkOverrides: { status: 'revoked' } });
    const bob = verifiedUser('bob');
    await assertSucceeds(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), rerequestUpdate()));
  });

  test('expired invite cannot be used to re-request a rejected relationship', async () => {
    const expired = new Date(Date.now() - 60 * 1000);
    await seedRoster({
      link: true,
      linkOverrides: { status: 'rejected' },
      inviteOverrides: {
        created_at: Timestamp.fromDate(new Date(expired.getTime() - 7 * 24 * 60 * 60 * 1000)),
        expires_at: Timestamp.fromDate(expired),
      },
    });
    const bob = verifiedUser('bob');
    await assertFails(updateDoc(doc(bob, 'teacher_student_links', LINK_ID), rerequestUpdate()));
  });
});

describe('training plans', () => {
  function shiftDays(days) {
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  }

  function trainingPlan(userId, dayKey, overrides = {}) {
    return {
      user_id: userId,
      day_key: dayKey,
      plan_type: 'training',
      movement_name: 'Hand Stall',
      difficulty: 'Medium',
      prop_type: 'bottle',
      target_duration_minutes: 10,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
      ...overrides,
    };
  }

  function restPlan(userId, dayKey) {
    return {
      user_id: userId,
      day_key: dayKey,
      plan_type: 'rest',
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    };
  }

  test('owner can create, read, query, update, and delete an own plan', async () => {
    const alice = aliceDb();
    const dayKey = manilaDayKeyFor(new Date());
    const ref = doc(alice, 'training_plans', `alice_${dayKey}`);
    await assertSucceeds(setDoc(ref, trainingPlan('alice', dayKey)));
    await assertSucceeds(getDoc(ref));
    const listed = await assertSucceeds(getDocs(query(
      collection(alice, 'training_plans'),
      where('user_id', '==', 'alice'),
    )));
    assert.equal(listed.size, 1);
    await assertSucceeds(updateDoc(ref, {
      target_duration_minutes: 20,
      updated_at: serverTimestamp(),
    }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('owner can schedule a rest day for today', async () => {
    const alice = aliceDb();
    const dayKey = manilaDayKeyFor(new Date());
    await assertSucceeds(setDoc(
      doc(alice, 'training_plans', `alice_${dayKey}`),
      restPlan('alice', dayKey),
    ));
  });

  test('rejects another user\'s plan, mismatched ids, past days, and invalid fields', async () => {
    const alice = aliceDb();
    const today = manilaDayKeyFor(new Date());
    const past = manilaDayKeyFor(shiftDays(-3));
    const future = manilaDayKeyFor(shiftDays(2));

    await assertFails(setDoc(
      doc(alice, 'training_plans', `bob_${today}`),
      trainingPlan('bob', today),
    ));
    await assertFails(setDoc(
      doc(alice, 'training_plans', `alice_${future}`),
      trainingPlan('alice', today),
    ));
    await assertFails(setDoc(
      doc(alice, 'training_plans', `alice_${past}`),
      trainingPlan('alice', past),
    ));
    await assertFails(setDoc(
      doc(alice, 'training_plans', `alice_${today}`),
      trainingPlan('alice', today, { target_duration_minutes: 7 }),
    ));
    await assertFails(setDoc(
      doc(alice, 'training_plans', `alice_${today}`),
      trainingPlan('alice', today, { extra: true }),
    ));
    await assertFails(setDoc(
      doc(alice, 'training_plans', `alice_${today}`),
      trainingPlan('alice', today, { user_id: 'bob' }),
    ));
  });

  test('bob cannot read or list alice plans', async () => {
    const today = manilaDayKeyFor(new Date());
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'training_plans', `alice_${today}`), {
        ...trainingPlan('alice', today),
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'training_plans', `alice_${today}`)));
    await assertFails(getDocs(query(
      collection(bob, 'training_plans'),
      where('user_id', '==', 'alice'),
    )));
  });

  test('update cannot change owner or day key', async () => {
    const alice = aliceDb();
    const today = manilaDayKeyFor(new Date());
    const ref = doc(alice, 'training_plans', `alice_${today}`);
    await assertSucceeds(setDoc(ref, trainingPlan('alice', today)));
    await assertFails(updateDoc(ref, {
      user_id: 'bob',
      updated_at: serverTimestamp(),
    }));
    await assertFails(updateDoc(ref, {
      day_key: manilaDayKeyFor(shiftDays(1)),
      updated_at: serverTimestamp(),
    }));
  });

  test('owner can delete today and future plans', async () => {
    const alice = aliceDb();
    const today = manilaDayKeyFor(new Date());
    const future = manilaDayKeyFor(shiftDays(2));
    const todayRef = doc(alice, 'training_plans', `alice_${today}`);
    const futureRef = doc(alice, 'training_plans', `alice_${future}`);
    await assertSucceeds(setDoc(todayRef, trainingPlan('alice', today)));
    await assertSucceeds(setDoc(futureRef, trainingPlan('alice', future)));
    await assertSucceeds(deleteDoc(todayRef));
    await assertSucceeds(deleteDoc(futureRef));
  });

  test('owner cannot delete a past plan', async () => {
    const past = manilaDayKeyFor(shiftDays(-3));
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'training_plans', `alice_${past}`), {
        ...trainingPlan('alice', past),
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    await assertFails(deleteDoc(doc(aliceDb(), 'training_plans', `alice_${past}`)));
  });

  test('another user cannot delete the plan', async () => {
    const today = manilaDayKeyFor(new Date());
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'training_plans', `alice_${today}`), {
        ...trainingPlan('alice', today),
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    await assertFails(deleteDoc(doc(bobDb(), 'training_plans', `alice_${today}`)));
  });
});
