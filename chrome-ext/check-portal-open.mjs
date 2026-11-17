import assert from 'node:assert/strict';
import { chooseCertIndex, isEduptl, prepareCertDialog, readPortalScreen, menuTarget, submitCertPassword } from './lib/portal-open.js';

assert.equal(chooseCertIndex(['김교사'], '', true, -1), 0);
assert.equal(chooseCertIndex(['김교사', '박교사'], '박교사', true, 0), 1);
assert.equal(chooseCertIndex(['김교사', '박교사'], '', false, 0), 0);
assert.equal(chooseCertIndex(['김교사', '박교사'], '', true, 0), -1);
assert.equal(isEduptl('https://pen.eduptl.kr/bpm_lgn_lg00_001.do'), true);
assert.equal(isEduptl('https://not-eduptl.kr/'), false);
assert.equal(isEduptl('https://pen.neis.go.kr/jsp/main.jsp'), false);

function row(user, selected = false) {
  const classes = new Set(selected ? ['kc-tableview-selected-row'] : []);
  return {
    offsetWidth: 8,
    classList: { contains: (name) => classes.has(name), add: (name) => classes.add(name) },
    cells: [{ clicked: false, click() { this.clicked = true; } }, { innerText: user }]
  };
}
const one = row('김교사');
const dialog = { offsetWidth: 20 };
const button = { offsetWidth: 10, clicked: false, click() { this.clicked = true; } };
globalThis.document = {
  querySelector(sel) {
    if (sel === '#kc_dialog_default') return dialog;
    if (sel === '#btnLgn') return button;
    if (sel === '#kc_dialog_default input[name=certPassword]') return null;
    return null;
  },
  querySelectorAll(sel) {
    return sel === '#kc_cert_list table tbody tr' ? [one] : [];
  }
};
const prepared = await prepareCertDialog('');
assert.equal(prepared.ok, true);
assert.equal(prepared.user, '김교사');
assert.equal(button.clicked, false);

globalThis.document.querySelector = (sel) => (sel === '#btnLgn' ? button : null);
assert.equal(readPortalScreen(), 'login');
const labeled = { offsetWidth: 12, tagName: 'A', innerText: '>> 교육행정 전자서명 인증서 로그인', clicked: false, focus() {}, click() { this.clicked = true; } };
globalThis.document = {
  querySelector: () => null,
  querySelectorAll: (sel) => sel === 'a,button,[role="button"]' ? [labeled] : []
};
assert.equal(readPortalScreen(), 'login');
labeled.click = function () { this.clicked = true; globalThis.document.querySelector = (sel) => sel === '#kc_dialog_default' ? { offsetWidth: 20 } : null; };
globalThis.document.querySelectorAll = (sel) => {
  if (sel === 'a,button,[role="button"]') return [labeled];
  if (sel === '#kc_cert_list table tbody tr' && labeled.clicked) return [one];
  return [];
};
const byLabel = await prepareCertDialog('');
assert.equal(byLabel.ok, true);
assert.equal(byLabel.user, '김교사');
assert.equal(labeled.clicked, true);
globalThis.document.querySelector = () => null;
globalThis.document.querySelectorAll = () => [{ offsetWidth: 4, innerText: '나이스', id: 'https://pen.neis.go.kr/cmc_fcm_lg01_000.do', href: '' }];
assert.equal(readPortalScreen(), 'main');
assert.equal(menuTarget('나이스').url, 'https://pen.neis.go.kr/cmc_fcm_lg01_000.do');

let clicked = false;
globalThis.document.querySelector = (sel) => {
  if (sel.includes('certPassword')) return { value: '', focus() {}, dispatchEvent() {} };
  if (sel.includes('kc-btn-blue')) return { click() { clicked = true; } };
  return null;
};
assert.equal(submitCertPassword('secret-only'), true);
assert.equal(clicked, true);
console.log('PASS: certificate choice, portal screen, menu address, single password submit');

clicked=false;
const plain={value:'',focus(){},dispatchEvent(){}};
globalThis.document.querySelector=sel=>sel.includes('certPassword')?plain:sel.includes('kc-btn-blue')?{click(){clicked=true;}}:null;
assert.equal(submitCertPassword('test-only'),true);assert.equal(plain.value,'test-only');assert.equal(clicked,true);
clicked=false;
assert.equal(submitCertPassword('').ok,false);assert.equal(clicked,false);
console.log('PASS: saved password is written and confirmed once; an empty password is not submitted');
