import assert from 'node:assert/strict';

const baseUrl = process.env.ELIXR_FUNCTIONS_EMULATOR_URL ||
  'http://127.0.0.1:5001/demo-elixr/asia-southeast1/';

const unauthenticatedSearch = await fetch(
  new URL('searchChatUsers?q=alice', baseUrl),
);
assert.equal(unauthenticatedSearch.status, 401);

const wrongSearchMethod = await fetch(new URL('searchChatUsers', baseUrl), {
  method: 'POST',
});
assert.equal(wrongSearchMethod.status, 405);

const unauthenticatedErasure = await fetch(
  new URL('archiveChatForAccountErasure', baseUrl),
  {method: 'POST'},
);
assert.equal(unauthenticatedErasure.status, 401);

console.log('Functions emulator authentication/method smoke checks passed.');
