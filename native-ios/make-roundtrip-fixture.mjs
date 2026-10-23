// CI-only fixture builder for the iOS preview job. Creates a dummy identity,
// wraps it in a vault with the dummy passphrase, and encrypts a SYNTHETIC
// payload (no business data) to that identity using the repo's real encrypt.mjs.
import {writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const m = await import('/tmp/crypto.mjs');
const r = await m.setup('dummy-pass-1234');
writeFileSync('/tmp/dj-pubs.json', JSON.stringify([r.vault.pub]));
writeFileSync('/tmp/dj-synth-data.json', JSON.stringify({synthetic: 'roundtrip-ok-dummy', history: [], note: 'synthetic fixture, not business data'}));
const payload = execFileSync('node', ['encrypt.mjs', '/tmp/dj-synth-data.json', '/tmp/dj-pubs.json'], {encoding: 'utf8'});
const seed = {vault: r.vault, payload: JSON.parse(payload)};
writeFileSync('/tmp/dj-seed.json', JSON.stringify(seed));
console.log('fixture ok, seed bytes:', JSON.stringify(seed).length);
