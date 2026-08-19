import { readFileSync } from 'node:fs';
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const NOTES = 'teacher_coaching_notes';
const LINKS = 'teacher_student_links';
const SOURCE_FIELD = 'authorization_source';
const SOURCE_LEGACY = 'legacy_link';
const WRITE_BATCH_SIZE = 400;

function option(args, name) {
  for (const arg of args) {
    if (arg.startsWith(`${name}=`)) return arg.slice(name.length + 1);
  }
  const index = args.indexOf(name);
  if (index >= 0 && index + 1 < args.length) return args[index + 1];
  return null;
}

function isValidParticipantId(value) {
  return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= 128;
}

function linkDocumentId(teacherId, traineeId) {
  return `${teacherId}_${traineeId}`;
}

/**
 * Keep in sync with lib/legacy_coaching_provenance_planner.dart
 */
function evaluate(noteId, note, link) {
  if (Object.prototype.hasOwnProperty.call(note, 'group_id')) {
    return { noteId, eligible: false, reason: 'groupBacked' };
  }
  if (Object.prototype.hasOwnProperty.call(note, SOURCE_FIELD)) {
    return { noteId, eligible: false, reason: 'alreadyProvenanced' };
  }
  const teacherId = note.teacher_id;
  const traineeId = note.trainee_id;
  if (
    !isValidParticipantId(teacherId) ||
    !isValidParticipantId(traineeId) ||
    teacherId.trim() === traineeId.trim()
  ) {
    return { noteId, eligible: false, reason: 'invalidIdentity' };
  }
  const trimmedTeacherId = teacherId.trim();
  const trimmedTraineeId = traineeId.trim();
  if (!link) {
    return { noteId, eligible: false, reason: 'missingRelationship' };
  }
  if (link.teacher_id !== trimmedTeacherId || link.trainee_id !== trimmedTraineeId) {
    return { noteId, eligible: false, reason: 'identityMismatch' };
  }
  if (link.status !== 'approved') {
    return { noteId, eligible: false, reason: 'relationshipNotApproved' };
  }
  return { noteId, eligible: true, teacherId: trimmedTeacherId, traineeId: trimmedTraineeId };
}

function emptyReport() {
  return {
    notesScanned: 0,
    historicalCandidates: 0,
    eligible: 0,
    skippedGroupBacked: 0,
    skippedAlreadyProvenanced: 0,
    skippedInvalidIdentity: 0,
    skippedMissingRelationship: 0,
    skippedRelationshipNotApproved: 0,
    skippedIdentityMismatch: 0,
    wouldUpdateIds: [],
    writeFailures: [],
  };
}

function addDecision(report, decision) {
  report.notesScanned += 1;
  if (decision.eligible) {
    report.historicalCandidates += 1;
    report.eligible += 1;
    report.wouldUpdateIds.push(decision.noteId);
    return;
  }
  switch (decision.reason) {
    case 'groupBacked':
      report.skippedGroupBacked += 1;
      break;
    case 'alreadyProvenanced':
      report.skippedAlreadyProvenanced += 1;
      break;
    case 'invalidIdentity':
      report.historicalCandidates += 1;
      report.skippedInvalidIdentity += 1;
      break;
    case 'missingRelationship':
      report.historicalCandidates += 1;
      report.skippedMissingRelationship += 1;
      break;
    case 'relationshipNotApproved':
      report.historicalCandidates += 1;
      report.skippedRelationshipNotApproved += 1;
      break;
    case 'identityMismatch':
      report.historicalCandidates += 1;
      report.skippedIdentityMismatch += 1;
      break;
    default:
      break;
  }
}

function formatReport(report, dryRun) {
  const skippedMissingOrNonApproved =
    report.skippedMissingRelationship + report.skippedRelationshipNotApproved;
  const lines = [
    `Legacy coaching provenance backfill — ${dryRun ? 'DRY RUN (no writes)' : 'WRITE'}`,
    `notes scanned: ${report.notesScanned}`,
    `historical notes (no group_id, no authorization_source): ${report.historicalCandidates}`,
    `eligible: ${report.eligible}`,
    `skipped Group-backed notes: ${report.skippedGroupBacked}`,
    `skipped already-provenanced notes: ${report.skippedAlreadyProvenanced}`,
    `skipped missing/non-approved relationships: ${skippedMissingOrNonApproved}`,
    `skipped identity mismatch: ${report.skippedIdentityMismatch}`,
    `skipped invalid identity: ${report.skippedInvalidIdentity}`,
    dryRun
      ? `documents that WOULD be updated: ${report.wouldUpdateIds.length}`
      : `documents targeted: ${report.wouldUpdateIds.length}`,
  ];
  for (const id of report.wouldUpdateIds) {
    lines.push(`  - ${id}`);
  }
  if (report.writeFailures.length > 0) {
    lines.push(`write failures: ${report.writeFailures.length}`);
    for (const failure of report.writeFailures) {
      lines.push(`  - ${failure}`);
    }
  }
  return `${lines.join('\n')}\n`;
}

function chunkIds(ids) {
  const chunks = [];
  for (let i = 0; i < ids.length; i += WRITE_BATCH_SIZE) {
    chunks.push(ids.slice(i, i + WRITE_BATCH_SIZE));
  }
  return chunks;
}

const usage = `Controlled historical legacy coaching provenance backfill.

Adds ONLY authorization_source: "legacy_link" to eligible notes that have
no group_id, no authorization_source, valid teacher_id/trainee_id, and a
matching approved teacher_student_links/{teacherId}_{traineeId} document.

Does not alter body, names, timestamps, group_id, or identities.
Does not create links. Does not convert Group-backed notes.

Dry run (default, no writes):
  node backfill.mjs --dry-run --project=elixr-app-2026

Write:
  node backfill.mjs --write --project=elixr-app-2026

Optional:
  --credentials=path/to/service-account.json
`;

async function plan(db) {
  const links = new Map();
  const linkSnap = await db.collection(LINKS).get();
  for (const doc of linkSnap.docs) {
    links.set(doc.id, doc.data());
  }

  const report = emptyReport();
  const notesSnap = await db.collection(NOTES).get();
  for (const doc of notesSnap.docs) {
    const note = doc.data();
    let link;
    if (isValidParticipantId(note.teacher_id) && isValidParticipantId(note.trainee_id)) {
      link = links.get(linkDocumentId(note.teacher_id.trim(), note.trainee_id.trim()));
    }
    addDecision(report, evaluate(doc.id, note, link));
  }
  return report;
}

async function writeEligible(db, report) {
  const chunks = chunkIds(report.wouldUpdateIds);
  for (const chunk of chunks) {
    try {
      const batch = db.batch();
      for (const noteId of chunk) {
        batch.update(db.collection(NOTES).doc(noteId), {
          [SOURCE_FIELD]: SOURCE_LEGACY,
        });
      }
      await batch.commit();
    } catch (error) {
      console.error(`Batch write failed (${error}); retrying documents individually.`);
      for (const noteId of chunk) {
        try {
          await db.collection(NOTES).doc(noteId).update({
            [SOURCE_FIELD]: SOURCE_LEGACY,
          });
        } catch (individual) {
          report.writeFailures.push(`${noteId}: ${individual}`);
        }
      }
    }
  }
}

async function main(args) {
  if (args.includes('--help') || args.includes('-h')) {
    process.stdout.write(usage);
    return;
  }
  const write = args.includes('--write');
  const dryRunFlag = args.includes('--dry-run');
  if (write && dryRunFlag) {
    console.error('Pass either --dry-run or --write, not both.');
    process.exitCode = 64;
    return;
  }
  const dryRun = !write;
  const projectId = option(args, '--project') ?? 'elixr-app-2026';
  const credentialsPath = option(args, '--credentials');

  const credential = credentialsPath
    ? cert(JSON.parse(readFileSync(credentialsPath, 'utf8')))
    : applicationDefault();
  initializeApp({ credential, projectId });
  const db = getFirestore();

  const report = await plan(db);
  process.stdout.write(formatReport(report, dryRun));
  if (dryRun) return;
  if (report.wouldUpdateIds.length === 0) {
    console.log('No eligible documents. Nothing written.');
    return;
  }
  await writeEligible(db, report);
  process.stdout.write(formatReport(report, false));
  if (report.writeFailures.length > 0) process.exitCode = 1;
}

await main(process.argv.slice(2));
