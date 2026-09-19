const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {isDeepStrictEqual} = require('node:util');

const indexes = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', '..', 'firestore.indexes.json'),
  'utf8',
));

test('daily quest session lookup has its required ascending time index', () => {
  const requiredFields = [
    {fieldPath: 'user_id', order: 'ASCENDING'},
    {fieldPath: 'created_at', order: 'ASCENDING'},
  ];
  assert.ok(indexes.indexes.some((index) =>
    index.collectionGroup === 'sessions' &&
    index.queryScope === 'COLLECTION' &&
    isDeepStrictEqual(index.fields, requiredFields),
  ));
});
