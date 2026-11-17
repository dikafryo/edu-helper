import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import { buildDutyData } from './lib/duty.js';
import { validateSettings, validateDutyPresets } from './lib/settings.js';

const json = path => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8').replace(/^\uFEFF/, ''));
const presets = json('./data/duty_presets.json');
const settings = { taskCards: json('./data/task_cards.json'), travelForm: {}, dutyForm: {}, dutyPresets: presets };
assert.equal(validateSettings(settings), settings);
assert.deepEqual(validateDutyPresets([]), []);
for (const invalid of [null, {}, [null], [{ Label: ' ' }], [{ Label: '연가', Time: 9 }], [{ Label: '연가', Url: 'javascript:alert(1)' }], [{ Label: '연가', Url: 'https://user:pw@example.com' }]]) {
  assert.throws(() => validateDutyPresets(invalid));
}
for (const invalid of [{ ...settings, taskCards: {} }, { ...settings, travelForm: [] }, { ...settings, dutyForm: null }]) {
  assert.throws(() => validateSettings(invalid));
}
assert.equal(validateDutyPresets([{ Label: '연가', custom: '보존', Time: '종일' }])[0].custom, '보존');
let checked = 0;
function check(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = new URL(entry.name + (entry.isDirectory() ? '/' : ''), dir);
    if (entry.isDirectory()) check(path);
    else if (entry.name.endsWith('.js')) {
      const result = spawnSync(process.execPath, ['--input-type=module', '--check'], { input: readFileSync(path), encoding: 'utf8' });
      assert.equal(result.status, 0, `${path}: ${result.stderr}`);
      checked++;
    }
  }
}
check(new URL('./', import.meta.url));
const background = readFileSync(new URL('./background.js', import.meta.url), 'utf8');
const start = background.indexOf('async function applyDutyPresetIndex(');
const end = background.indexOf('chrome.runtime.onMessage.addListener', start);
assert.ok(start >= 0 && end > start);
async function runPreset(response, disconnected = false) {
  const context = vm.createContext({ buildDutyData, requireUnlocked: async () => null, chrome: {
    storage: { local: { get: async () => ({ dutyPresets: presets }), set: async () => {} } },
    tabs: { query: async () => [{ id: 1 }], sendMessage: async () => {
      if (disconnected) throw new Error('Disconnected');
      return response;
    } }
  } });
  vm.runInContext(background.slice(start, end), context);
  return context.applyDutyPresetIndex(0);
}
assert.equal((await runPreset({ ok: true, filled: 3 })).ok, true);
assert.equal((await runPreset({ ok: false, error: '입력 실패' })).error, '입력 실패');
assert.equal((await runPreset({ ok: true, filled: 0 })).ok, false);
assert.equal((await runPreset(undefined)).ok, false);
assert.equal((await runPreset(undefined, true)).ok, false);
console.log(`PASS: settings validation, preset success/zero/error/disconnection; ${checked} JavaScript syntax checks`);
const original = JSON.stringify(presets[0]);
const data = buildDutyData(presets[0], { start: '2026-11-02', end: '2026-11-04', reason: '변경 사유', time: '종일' });
assert.equal(data.end, '2026-11-04');
assert.equal(data.reason, '변경 사유');
assert.equal(JSON.stringify(presets[0]), original);
for (const changes of [{ start: '' }, { start: '2026-02-30' }, { start: '2026-11-04', end: '2026-11-02' }, { reason: 123 }, null]) {
  assert.throws(() => buildDutyData(presets[0], changes));
}
assert.equal(buildDutyData(presets[0], { start: '2028-02-29' }).end, '2028-02-29');
console.log('PASS: date overrides, leap dates, invalid/reversed dates, original preset preservation');
