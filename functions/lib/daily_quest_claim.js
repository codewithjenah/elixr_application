// Trusted daily-quest award logic. The Flutter catalog is intentionally
// mirrored here because this module is the authority for XP awards.
const QUESTS = Object.freeze({
  session_count_1: [10, 'count', 1], duration_10min: [10, 'duration', 600], score_70: [10, 'best', 7], two_movements: [10, 'movements', 2], practice_easy_movement: [10, 'difficulty', 'easy'], use_shaker: [10, 'prop', 'shaker'],
  session_count_3: [15, 'count', 3], duration_20min: [15, 'duration', 1200], score_85: [15, 'best', 10], sessions_above_70_x2: [15, 'above', 2], three_movements: [15, 'movements', 3], practice_medium_movement: [15, 'difficulty', 'medium'], distinct_props_2: [15, 'props', 2],
  session_count_5: [20, 'count', 5], duration_30min: [20, 'duration', 1800], score_95: [20, 'best', 12], practice_hard_movement: [20, 'difficulty', 'hard'], use_bottle_and_shaker_combo: [20, 'prop', 'bottle_and_shaker'],
});

function manilaDay(now) {
  const parts = new Intl.DateTimeFormat('en-US', {timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit'}).formatToParts(now);
  const value = (type) => Number(parts.find((part) => part.type === type).value);
  const year = value('year'); const month = value('month'); const day = value('day');
  const dayKey = `${year}${String(month).padStart(2, '0')}${String(day).padStart(2, '0')}`;
  return {dayKey, startMillis: Date.UTC(year, month - 1, day) - 8 * 60 * 60 * 1000};
}

function isIntegerIn(value, min, max) { return Number.isInteger(value) && value >= min && value <= max; }
function timestampMillis(value) { return value && typeof value.toMillis === 'function' ? value.toMillis() : NaN; }

function validSession(data, uid, startMillis) {
  const assessmentVersion = data?.assessment_version == null ? 1 : data.assessment_version;
  if (!data || data.user_id !== uid || typeof data.movement_name !== 'string' || !data.movement_name.trim() ||
      typeof data.difficulty !== 'string' || typeof data.prop_type !== 'string' ||
      !['bottle', 'shaker', 'bottle_and_shaker'].includes(data.prop_type) ||
      !isIntegerIn(data.duration_seconds, 0, 24 * 60 * 60) || !isIntegerIn(assessmentVersion, 1, 2)) return false;
  const created = timestampMillis(data.created_at);
  if (!Number.isFinite(created) || created < startMillis || created >= startMillis + 86400000) return false;
  if (assessmentVersion === 2) {
    const rubric = data.rubric;
    return rubric && ['technique', 'stability', 'completion', 'prop_positioning'].every((key) => isIntegerIn(rubric[key], 0, 3)) &&
      isIntegerIn(data.rubric_total, 0, 12) && data.rubric_total === rubric.technique + rubric.stability + rubric.completion + rubric.prop_positioning;
  }
  return isIntegerIn(data.score, 0, 100);
}

function questComplete(questId, sessions) {
  const quest = QUESTS[questId]; if (!quest) return false;
  const [, kind, target] = quest;
  const rubric = sessions.filter((s) => s.assessment_version === 2);
  if (kind === 'count') return sessions.length >= target;
  if (kind === 'duration') return sessions.reduce((sum, s) => sum + s.duration_seconds, 0) >= target;
  if (kind === 'best') return rubric.some((s) => s.rubric_total >= target);
  if (kind === 'above') return rubric.filter((s) => s.rubric_total >= 7).length >= target;
  if (kind === 'movements') return new Set(sessions.map((s) => s.movement_name.trim().toLowerCase()).filter(Boolean)).size >= target;
  if (kind === 'difficulty') return sessions.some((s) => s.difficulty.trim().toLowerCase() === target);
  if (kind === 'prop') return sessions.some((s) => s.prop_type === target);
  if (kind === 'props') return new Set(sessions.map((s) => s.prop_type)).size >= target;
  return false;
}

function validBoard(board, uid, dayKey, startMillis, questId) {
  if (!board || board.user_id !== uid || board.day_key !== dayKey || timestampMillis(board.day_start) !== startMillis || !Array.isArray(board.quest_ids) || board.quest_ids.length !== 5 || new Set(board.quest_ids).size !== 5 || !board.quest_ids.includes(questId)) return false;
  const quests = board.quest_ids.map((id) => QUESTS[id]);
  return quests.every(Boolean) && quests.filter((quest) => quest[0] === 10).length === 2 && quests.filter((quest) => quest[0] === 15).length === 2 && quests.filter((quest) => quest[0] === 20).length === 1;
}

function periodFields(existing, dayKey, xp) {
  const monthKey = dayKey.slice(0, 6);
  const dailySame = existing.daily_key === dayKey;
  const monthlySame = existing.monthly_key === monthKey;
  return {
    daily_key: dailySame ? existing.daily_key : dayKey,
    daily_xp: (dailySame ? Number(existing.daily_xp || 0) : 0) + xp,
    daily_sessions_completed: dailySame ? Number(existing.daily_sessions_completed || 0) : 0,
    daily_score_sum: dailySame ? Number(existing.daily_score_sum || 0) : 0,
    daily_average_score: dailySame ? Number(existing.daily_average_score || 0) : 0,
    daily_best_score: dailySame ? Number(existing.daily_best_score || 0) : 0,
    monthly_key: monthlySame ? existing.monthly_key : monthKey,
    monthly_xp: (monthlySame ? Number(existing.monthly_xp || 0) : 0) + xp,
    monthly_sessions_completed: monthlySame ? Number(existing.monthly_sessions_completed || 0) : 0,
    monthly_score_sum: monthlySame ? Number(existing.monthly_score_sum || 0) : 0,
    monthly_average_score: monthlySame ? Number(existing.monthly_average_score || 0) : 0,
    monthly_best_score: monthlySame ? Number(existing.monthly_best_score || 0) : 0,
  };
}

async function claimDailyQuest({firestore, uid, questId, now = new Date(), FieldValue, Timestamp}) {
  const quest = QUESTS[questId]; if (!quest) return {status: 'invalid_quest'};
  const {dayKey, startMillis} = manilaDay(now);
  const boardId = `${uid}_${dayKey}`; const claimId = `${uid}_${dayKey}_${questId}`;
  const boardRef = firestore.collection('daily_quest_boards').doc(boardId);
  const claimRef = firestore.collection('daily_quest_claims').doc(claimId);
  const leaderboardRef = firestore.collection('leaderboard').doc(uid);
  const sessionsQuery = firestore.collection('sessions').where('user_id', '==', uid)
    .where('created_at', '>=', Timestamp.fromMillis(startMillis))
    .where('created_at', '<', Timestamp.fromMillis(startMillis + 86400000));
  return firestore.runTransaction(async (tx) => {
    const [claimSnap, boardSnap, leaderboardSnap, sessionsSnap] = await Promise.all([tx.get(claimRef), tx.get(boardRef), tx.get(leaderboardRef), tx.get(sessionsQuery)]);
    if (claimSnap.exists) return {status: 'already_claimed'};
    const board = boardSnap.data();
    if (!validBoard(board, uid, dayKey, startMillis, questId)) return {status: 'board_missing'};
    if (!leaderboardSnap.exists) return {status: 'leaderboard_missing'};
    const snapshots = sessionsSnap.docs || [];
    const sessions = snapshots.map((doc) => doc.data());
    if (!sessions.every((session) => validSession(session, uid, startMillis))) return {status: 'invalid_evidence'};
    if (!questComplete(questId, sessions)) return {status: 'quest_not_completed'};
    const xp = quest[0]; const leaderboard = leaderboardSnap.data();
    tx.create(claimRef, {user_id: uid, board_id: boardId, day_key: dayKey, day_start: Timestamp.fromMillis(startMillis), quest_id: questId, xp_awarded: xp, claimed_at: FieldValue.serverTimestamp()});
    tx.set(leaderboardRef, {quest_xp: Number(leaderboard.quest_xp || 0) + xp, total_xp: Number(leaderboard.total_xp || 0) + xp, last_claim_id: claimId, ...periodFields(leaderboard, dayKey, xp)}, {merge: true});
    return {status: 'claimed', xp_awarded: xp};
  });
}

module.exports = {QUESTS, manilaDay, validSession, questComplete, validBoard, claimDailyQuest};
