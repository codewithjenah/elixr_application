import {applicationDefault, getApps, initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';

// One-time compatibility migration for announcements created before the
// server-maintained trainee_visible marker existed. It is intentionally manual
// and dry-run by default: the recurring publisher must stay a due-only query.
if (getApps().length === 0) initializeApp({credential: applicationDefault()});

const firestore = getFirestore();
const write = process.argv.includes('--write');
const pageSize = 400;
const counts = {scanned: 0, repaired: 0, skipped: 0, failures: 0};
let cursor = null;

while (true) {
  let query = firestore.collectionGroup('announcements')
    .orderBy('created_at', 'asc')
    .limit(pageSize);
  if (cursor) query = query.startAfter(cursor);
  const snapshot = await query.get();
  if (snapshot.empty) break;

  const repairs = [];
  for (const announcement of snapshot.docs) {
    counts.scanned += 1;
    const data = announcement.data();
    // Never change a scheduled announcement; those are owned by the due-only
    // publisher. This repairs only legacy immediate documents with a missing
    // or stale visibility marker.
    if (data.publish_at == null && data.trainee_visible !== true) {
      repairs.push(announcement.ref);
      counts.repaired += 1;
    } else {
      counts.skipped += 1;
    }
  }
  if (write && repairs.length > 0) {
    const batch = firestore.batch();
    repairs.forEach((ref) => batch.update(ref, {trainee_visible: true}));
    try {
      await batch.commit();
    } catch (error) {
      counts.failures += repairs.length;
      counts.repaired -= repairs.length;
      console.error('Announcement visibility migration batch failed', error);
    }
  }
  cursor = snapshot.docs[snapshot.docs.length - 1];
  if (snapshot.size < pageSize) break;
}

console.log(JSON.stringify({mode: write ? 'write' : 'dry-run', ...counts}, null, 2));
if (!write) {
  console.log('No writes performed. Re-run with --write after reviewing the output.');
}
