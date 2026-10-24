// CI-only fixture builder for the iOS preview job. Loads the committed DUMMY
// identity vault (wrapped with the dummy passphrase 'dummy-pass-1234') and the
// synthetic encrypted fixtures, and writes the driver seeds. All data is
// synthetic; no real keys or business data. Writes:
//   /tmp/dj-seed.json           legacy decrypt-only roundtrip seed
//   /tmp/dj-seed-{match,mismatch,solo}.json   v6 render seeds (ops + expenses)
import {readFileSync, writeFileSync} from 'node:fs';
const dir = 'native-ios/test-fixtures/';
const vault = JSON.parse(readFileSync(dir + 'vault.json', 'utf8'));
const payloadSlim = JSON.parse(readFileSync(dir + 'payload_slim.json', 'utf8'));
const payloadFull = JSON.parse(readFileSync(dir + 'payload_full.json', 'utf8'));
const expA = JSON.parse(readFileSync(dir + 'expense_a.json', 'utf8'));
const expBMatch = JSON.parse(readFileSync(dir + 'expense_b_match.json', 'utf8'));
const expBMismatch = JSON.parse(readFileSync(dir + 'expense_b_mismatch.json', 'utf8'));
writeFileSync('/tmp/dj-seed.json', JSON.stringify({vault, payloadSlim, payloadFull}));
for (const [mode, expB] of [['match', expBMatch], ['mismatch', expBMismatch], ['solo', null]]) {
  writeFileSync('/tmp/dj-seed-' + mode + '.json', JSON.stringify({vault, payloadSlim, payloadFull, expA, expB, mode}));
}
console.log('fixture ok: legacy seed + 3 render seeds written');
