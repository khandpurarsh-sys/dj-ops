// CI-only fixture builder for the iOS preview job. Loads the committed DUMMY
// identity vault (wrapped with the dummy passphrase 'dummy-pass-1234'; its
// pubkey is the 10th recipient the peer publisher added to these synthetic
// envelopes) and embeds the peer-publisher's slim + full payloads for the
// in-app WKWebView decrypt test. All data is synthetic; no real keys or
// business data.
import {readFileSync, writeFileSync} from 'node:fs';
const vault = JSON.parse(readFileSync('native-ios/test-fixtures/vault.json', 'utf8'));
const payloadSlim = JSON.parse(readFileSync('native-ios/test-fixtures/payload_slim.json', 'utf8'));
const payloadFull = JSON.parse(readFileSync('native-ios/test-fixtures/payload_full.json', 'utf8'));
const seed = {vault, payloadSlim, payloadFull};
writeFileSync('/tmp/dj-seed.json', JSON.stringify(seed));
console.log('fixture ok, seed bytes:', JSON.stringify(seed).length);
