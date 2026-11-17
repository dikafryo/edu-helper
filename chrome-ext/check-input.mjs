import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('./content.js', import.meta.url), 'utf8');
const start = source.indexOf('function setValue(');
const end = source.indexOf('function looksLikePortalLoginPage', start);
let fields = [];
const ctx = vm.createContext({
  visible: () => true,
  labelOf: el => el.label,
  document: { querySelectorAll: () => fields },
  Event: class { constructor(type) { this.type = type; } }
});
vm.runInContext(source.slice(start, end), ctx);
const field = (label, extra = {}) => ({ label, type: 'text', tagName: 'INPUT', value: '', name: '', id: '', dispatchEvent() {}, ...extra });

const disabled = field('사유', { disabled: true });
assert.equal(ctx.setValue(disabled, '변경'), false);
assert.equal(disabled.value, '');
assert.equal(ctx.setValue(field('사유', { readOnly: true }), '변경'), false);
const rejected = field('날짜', { dispatchEvent() { this.value = ''; } });
assert.equal(ctx.setValue(rejected, '2026-11-02'), false);
const ambiguous = field('종류', { tagName: 'SELECT', options: [{ text: '병가 오전', value: 'a' }, { text: '병가 오후', value: 'b' }] });
assert.equal(ctx.setValue(ambiguous, '병가'), false);
assert.equal(ctx.setValue(ambiguous, '병가 오전'), true);
assert.equal(ambiguous.value, 'a');
fields = [field('시작 종료')];
assert.equal(ctx.fillByHints({ start: '2026-11-02', end: '2026-11-03' }, { start: ['시작'], end: ['종료'] }), 1);
assert.equal(fields[0].value, '2026-11-02');
fields = [field('사유', { type: 'checkbox', checked: false }), field('사유')];
assert.equal(ctx.fillByHints({ reason: '회의' }, { reason: ['사유'] }), 1);
assert.equal(fields[0].checked, false);
assert.equal(fields[1].value, '회의');
fields = [field('시작'), field('종료'), field('사유')];
assert.equal(ctx.fillByHints({ start: '2026-11-02', end: '2026-11-03', reason: '회의' }, { start: ['시작'], end: ['종료'], reason: ['사유'] }), 3);
console.log('PASS: readonly/disabled fields, rejected values, ambiguous selects, duplicate targets, checkbox exclusion, normal fill');
