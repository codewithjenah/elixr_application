import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  where,
} from 'firebase/firestore';

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

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

function challengeSession(overrides = {}) {
  return {
    user_id: 'alice',
    movement_name: 'Hand Stall',
    difficulty: 'Medium',
    duration_seconds: 45,
    prop_type: 'bottle',
    assessment_version: 2,
    rubric: {
      technique: 3,
      stability: 2,
      completion: 3,
      prop_positioning: 2,
    },
    rubric_total: 10,
    performance_level: 'proficient',
    challenge_context: {
      challenge_id: 'challenge-1',
      group_id: 'group-1',
      teacher_id: 'teacher-1',
      attempt_id: 'attempt-1',
    },
    created_at: serverTimestamp(),
    ...overrides,
  };
}

async function seedChallenge({
  challengeId = 'challenge-1',
  attemptId = 'attempt-1',
  traineeId = 'alice',
  groupId = 'group-1',
  teacherId = 'teacher-1',
  membershipStatus = 'approved',
  archived = false,
  expired = false,
} = {}) {
  const now = Date.now();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'group_memberships', `${groupId}_${traineeId}`), {
      group_id: groupId,
      teacher_id: teacherId,
      trainee_id: traineeId,
      status: membershipStatus,
    });
    await setDoc(doc(db, 'class_challenges', challengeId), {
      group_id: groupId,
      teacher_id: teacherId,
      movement_name: 'Hand Stall',
      prop_type: 'bottle',
      scoring_mode: 'rubric_total_v2',
      start_at: Timestamp.fromMillis(now - 60_000),
      deadline: Timestamp.fromMillis(now + (expired ? -1 : 60_000)),
      ...(archived ? {archived_at: Timestamp.fromMillis(now)} : {}),
    });
    await setDoc(doc(db, 'class_challenge_attempts', attemptId), {
      challenge_id: challengeId,
      group_id: groupId,
      teacher_id: teacherId,
      trainee_id: traineeId,
      movement_name: 'Hand Stall',
      prop_type: 'bottle',
      status: 'in_progress',
    });
    await setDoc(doc(db, 'class_challenge_results', `${challengeId}__${traineeId}`), {
      challenge_id: challengeId,
      group_id: groupId,
      teacher_id: teacherId,
      trainee_id: traineeId,
    });
  });
}

describe('Class Challenge authorization', () => {
  test('collection queries require canonical classroom scope', async () => {
    await seedChallenge();
    await seedChallenge({
      challengeId: 'other-teacher-challenge',
      attemptId: 'other-teacher-attempt',
      teacherId: 'teacher-2',
      traineeId: 'bob',
    });
    const teacher = testEnv.authenticatedContext('teacher-1', {
      role: 'Teacher',
    }).firestore();
    const alice = testEnv.authenticatedContext('alice').firestore();
    const outsider = testEnv.authenticatedContext('mallory').firestore();

    const classroomChallenges = query(
      collection(teacher, 'class_challenges'),
      where('group_id', '==', 'group-1'),
      where('teacher_id', '==', 'teacher-1'),
    );
    await assertSucceeds(getDocs(classroomChallenges));
    await assertFails(
      getDocs(
        query(
          collection(teacher, 'class_challenges'),
          where('group_id', '==', 'group-1'),
        ),
      ),
    );

    const traineeChallenges = query(
      collection(alice, 'class_challenges'),
      where('group_id', '==', 'group-1'),
      where('teacher_id', '==', 'teacher-1'),
    );
    await assertSucceeds(getDocs(traineeChallenges));
    await assertFails(
      getDocs(
        query(
          collection(outsider, 'class_challenges'),
          where('group_id', '==', 'group-1'),
          where('teacher_id', '==', 'teacher-1'),
        ),
      ),
    );
  });

  test('unapproved and removed trainees cannot query classroom challenges', async () => {
    await seedChallenge({traineeId: 'pending', membershipStatus: 'pending'});
    await seedChallenge({traineeId: 'removed', membershipStatus: 'removed'});
    const classroomQuery = (db) => query(
      collection(db, 'class_challenges'),
      where('group_id', '==', 'group-1'),
      where('teacher_id', '==', 'teacher-1'),
    );

    await assertFails(
      getDocs(classroomQuery(testEnv.authenticatedContext('pending').firestore())),
    );
    await assertFails(
      getDocs(classroomQuery(testEnv.authenticatedContext('removed').firestore())),
    );
  });

  test('authorized classroom users can query results and a challenge leaderboard', async () => {
    await seedChallenge();
    const teacher = testEnv.authenticatedContext('teacher-1', {
      role: 'Teacher',
    }).firestore();
    const alice = testEnv.authenticatedContext('alice').firestore();
    const outsider = testEnv.authenticatedContext('mallory').firestore();
    const resultsForClassroom = (db) => query(
      collection(db, 'class_challenge_results'),
      where('group_id', '==', 'group-1'),
      where('teacher_id', '==', 'teacher-1'),
    );
    const leaderboardForChallenge = (db) => query(
      collection(db, 'class_challenge_results'),
      where('challenge_id', '==', 'challenge-1'),
      where('group_id', '==', 'group-1'),
      where('teacher_id', '==', 'teacher-1'),
    );

    await assertSucceeds(getDocs(resultsForClassroom(teacher)));
    await assertSucceeds(getDocs(resultsForClassroom(alice)));
    await assertSucceeds(getDocs(leaderboardForChallenge(alice)));
    await assertFails(getDocs(resultsForClassroom(outsider)));
    await assertFails(getDocs(leaderboardForChallenge(outsider)));
  });

  test('approved trainee can read the challenge and save its reserved session', async () => {
    await seedChallenge();
    const alice = testEnv.authenticatedContext('alice').firestore();

    await assertSucceeds(getDoc(doc(alice, 'class_challenges', 'challenge-1')));
    await assertSucceeds(
      getDoc(doc(alice, 'class_challenge_results', 'challenge-1__alice')),
    );
    await assertSucceeds(
      setDoc(doc(alice, 'sessions', 'session-1'), challengeSession()),
    );
  });

  test('session rejects unauthorized identity, wrong attempt, and context collision', async () => {
    await seedChallenge();
    await seedChallenge({attemptId: 'attempt-for-bob', traineeId: 'bob'});
    const alice = testEnv.authenticatedContext('alice').firestore();
    const bob = testEnv.authenticatedContext('bob').firestore();

    await assertFails(
      setDoc(
        doc(bob, 'sessions', 'session-bob'),
        challengeSession({user_id: 'bob'}),
      ),
    );
    await assertFails(
      setDoc(
        doc(alice, 'sessions', 'session-wrong-attempt'),
        challengeSession({
          challenge_context: {
            challenge_id: 'challenge-1',
            group_id: 'group-1',
            teacher_id: 'teacher-1',
            attempt_id: 'attempt-for-bob',
          },
        }),
      ),
    );
    await assertFails(
      setDoc(
        doc(alice, 'sessions', 'session-collision'),
        challengeSession({
          assignment_context: {
            assignment_id: 'assignment-1',
            group_id: 'group-1',
            teacher_id: 'teacher-1',
            movement_id: 'official_hand_stall',
            revision_id: 'official_hand_stall_v1',
          },
        }),
      ),
    );
  });

  test('archived and expired challenges cannot receive a session', async () => {
    await seedChallenge({challengeId: 'archived', attemptId: 'archived-attempt', archived: true});
    await seedChallenge({challengeId: 'expired', attemptId: 'expired-attempt', expired: true});
    const alice = testEnv.authenticatedContext('alice').firestore();

    await assertFails(
      setDoc(
        doc(alice, 'sessions', 'session-archived'),
        challengeSession({
          challenge_context: {
            challenge_id: 'archived',
            group_id: 'group-1',
            teacher_id: 'teacher-1',
            attempt_id: 'archived-attempt',
          },
        }),
      ),
    );
    await assertFails(
      setDoc(
        doc(alice, 'sessions', 'session-expired'),
        challengeSession({
          challenge_context: {
            challenge_id: 'expired',
            group_id: 'group-1',
            teacher_id: 'teacher-1',
            attempt_id: 'expired-attempt',
          },
        }),
      ),
    );
  });

  test('clients cannot write server-owned challenge collections', async () => {
    await seedChallenge();
    const alice = testEnv.authenticatedContext('alice').firestore();
    const teacher = testEnv.authenticatedContext('teacher-1', {
      role: 'Teacher',
    }).firestore();

    await assertFails(
      setDoc(doc(alice, 'class_challenge_attempts', 'client-attempt'), {}),
    );
    await assertFails(
      setDoc(doc(alice, 'class_challenge_participants', 'client-participant'), {}),
    );
    await assertFails(
      setDoc(doc(teacher, 'class_challenges', 'client-challenge'), {}),
    );
    await assertFails(
      setDoc(doc(teacher, 'class_challenge_results', 'client-result'), {}),
    );
  });
});
