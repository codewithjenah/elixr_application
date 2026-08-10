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
  query,
  where,
  writeBatch,
  Timestamp,
  serverTimestamp,
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

async function seedBypassingRules(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

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
      { quest_xp: CLAIM_QUEST_XP, total_xp: 25 + CLAIM_QUEST_XP, last_claim_id: claimId },
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
      { quest_xp: 15, total_xp: 40, last_claim_id: claimId },
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
      { quest_xp: 15, total_xp: 40, last_claim_id: claimId },
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
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's1'), { user_id: 'alice', score: 80 });
      await setDoc(doc(adminDb, 'sessions', 's2'), { user_id: 'alice', score: 100 });
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
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's3'), { user_id: 'alice', score: 70 });
      await setDoc(doc(adminDb, 'sessions', 's4'), { user_id: 'alice', score: 90 });
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
      },
      { merge: true },
    );
    await assertSucceeds(batch.commit());
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
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'sessions', 's1'), { user_id: 'alice', score: 80 });
      await setDoc(doc(adminDb, 'sessions', 's2'), { user_id: 'alice', score: 100 });
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

  test('other user cannot read private profile summary', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'details', 'summary'),
        publicProfileSummary(),
      );
    });

    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'details', 'summary')));
  });

  test('other user can read public profile summary', async () => {
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

  test('other user cannot read private session projection', async () => {
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'public_profiles', 'alice'), publicProfileRoot('alice'));
      await setDoc(doc(adminDb, 'sessions', 's1'), { user_id: 'alice', score: 85 });
      await setDoc(
        doc(adminDb, 'public_profiles', 'alice', 'sessions', 's1'),
        publicProfileSession('alice', 's1'),
      );
    });

    const bob = bobDb();
    await assertFails(getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 's1')));
  });

  test('other user can read public session projection', async () => {
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

    const bob = bobDb();
    await assertSucceeds(getDoc(doc(bob, 'public_profiles', 'alice', 'sessions', 's1')));
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

  test('owner can delete own daily_quest_board by id; list remains denied', async () => {
    const { id, data } = boardData('alice');
    await seedBypassingRules(async (adminDb) => {
      await setDoc(doc(adminDb, 'daily_quest_boards', id), data);
    });

    const alice = aliceDb();
    await assertFails(getDocs(query(collection(alice, 'daily_quest_boards'), where('user_id', '==', 'alice'))));
    await assertSucceeds(deleteDoc(doc(alice, 'daily_quest_boards', id)));
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
