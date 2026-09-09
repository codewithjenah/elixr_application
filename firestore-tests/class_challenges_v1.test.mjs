import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
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
  archived = false,
  expired = false,
} = {}) {
  const now = Date.now();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'group_memberships', 'group-1_alice'), {
      group_id: 'group-1',
      teacher_id: 'teacher-1',
      trainee_id: 'alice',
      status: 'approved',
    });
    await setDoc(doc(db, 'class_challenges', challengeId), {
      group_id: 'group-1',
      teacher_id: 'teacher-1',
      movement_name: 'Hand Stall',
      prop_type: 'bottle',
      scoring_mode: 'rubric_total_v2',
      start_at: Timestamp.fromMillis(now - 60_000),
      deadline: Timestamp.fromMillis(now + (expired ? -1 : 60_000)),
      ...(archived ? {archived_at: Timestamp.fromMillis(now)} : {}),
    });
    await setDoc(doc(db, 'class_challenge_attempts', attemptId), {
      challenge_id: challengeId,
      group_id: 'group-1',
      teacher_id: 'teacher-1',
      trainee_id: traineeId,
      movement_name: 'Hand Stall',
      prop_type: 'bottle',
      status: 'in_progress',
    });
    await setDoc(doc(db, 'class_challenge_results', 'challenge-1__alice'), {
      challenge_id: 'challenge-1',
      group_id: 'group-1',
      teacher_id: 'teacher-1',
      trainee_id: 'alice',
    });
  });
}

describe('Class Challenge authorization', () => {
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
      setDoc(doc(teacher, 'class_challenges', 'client-challenge'), {}),
    );
    await assertFails(
      setDoc(doc(teacher, 'class_challenge_results', 'client-result'), {}),
    );
  });
});
