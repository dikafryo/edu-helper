import { buildDutyData } from './duty.js';
const TYPES = { 연가:'W0101', 조퇴:'W0104', 외출:'W0105', 지각:'W0103', 병조퇴:'W0205', 병외출:'W0206', 병지각:'W0204' };
export function prepareRoute(preset, overrides) {
  const data = buildDutyData(preset, overrides);
  const kind = /^(시간외|시간외근무)$/.test(data.type) ? 'overtime' : data.type === '출장' ? 'trip' : TYPES[data.type] ? 'leave' : '';
  if (!kind) throw new Error('자동 신청 지원 종류: 시간외·연가·조퇴·외출·지각·병조퇴·병외출·병지각·출장');
  const time = data.time.match(/^(\d{2}):([0-5]\d)\s*[~～-]\s*(\d{2}):([0-5]\d)$/);
  if (!time || +time[1] > 23 || +time[3] > 23 || time[1]+time[2] >= time[3]+time[4]) throw new Error('시작~종료 시간을 09:00~17:00 형식으로 입력하세요. 종일도 근무 시작·종료 시각이 필요합니다.');
  if (kind === 'overtime' && data.start !== data.end) throw new Error('시간외근무는 하루씩 신청하세요.');
  if (!data.reason) throw new Error('사유를 입력하세요.');
  if (!String(preset.LineName || '').trim()) throw new Error('설정에서 개인결재선 이름을 입력하세요.');
  if (kind === 'trip' && (!preset.Place?.trim() || !preset.Contact?.trim())) throw new Error('출장지와 연락처를 설정하세요.');
  if (kind === 'trip' && !['10','20','30','40'].includes(preset.TripType || '10')) throw new Error('출장 구분 코드를 확인하세요.');
  if (data.type === '연가' && !/^0\d$/.test(preset.LeaveReason || '')) throw new Error('연가 사유 코드(00~09)를 설정하세요.');
  return { ...data, kind, code:TYPES[data.type], date:data.start.replaceAll('-',''), dateTo:data.end.replaceAll('-',''), startH:time[1], startM:time[2], endH:time[3], endM:time[4], line:preset.LineName.trim(), place:preset.Place || '', contact:preset.Contact || '', leaveReason:preset.LeaveReason || '', tripType:preset.TripType || '10' };
}

// Self-contained function executed in the page MAIN world. No final submit action.
export async function runNeisRoute(job) {
  let step = '나이스 확인';
  const pause = ms => new Promise(resolve => setTimeout(resolve,ms));
  const platform = window.cpr?.core?.Platform?.INSTANCE;
  const find = id => platform?.getAllRunningAppInstances().find(a => a.app.id === id);
  const wait = async predicate => { const until=Date.now()+12000; let last; do { try { const value=predicate(); if(value) return value; } catch (error) { last=error; } await pause(180); } while(Date.now()<until); throw last || new Error('화면 준비 시간이 초과되었습니다. 현재 창을 확인하세요.'); };
  const base='edu/ga/srv/mym/mm/';
  const id = job.kind === 'overtime' ? 'srv_mymmm02' : job.kind === 'trip' ? 'srv_mymmm03' : 'srv_mymmm00';
  const draftId='edu/cm/wam/woa/pm/wam_woapm07_p00', lineId='edu/cm/wam/woa/pm/wam_woapm07_p02';
  try {
    if (!platform) throw new Error('로그인된 나이스 메인 화면이 아닙니다.');
    if ([draftId,lineId,...['00','02','03'].map(n=>base+'srv_mymmm'+n+'_p00')].some(find)) throw new Error('작성 중인 신청·결재 창이 있습니다. 먼저 마무리하거나 닫으세요.');
    step='복무 메뉴 이동';
    let list=find(base+id+'_m00');
    if (!list) {
      const menu = name => [...document.querySelectorAll('a.cl-sidenavigation-item')].find(el=>el.getClientRects().length && el.textContent.replace(/\s*\d+단계(?: 메뉴항목)?\s*$/,'').replace(/\s+/g,' ').trim()===name);
      const parent=await wait(()=>menu('복무'));
      if(parent.classList.contains('cl-collapsed')) parent.click();
      (await wait(()=>menu(job.kind==='overtime'?'개인초과근무관리':job.kind==='trip'?'개인출장관리':'개인근무상황관리'))).click();
      list=await wait(()=>find(base+id+'_m00'));
    }
    step='신청 창 열기';
    list.lookup('btnAply').click();
    const form=await wait(()=>find(base+id+'_p00'));
    const get = id => { const c=form.lookup(id); if(!c) throw new Error('입력 항목을 찾지 못했습니다: '+id); return c; };
    await wait(()=>get('grdMain').dataSet.getRowCount()>0);
    if(get('grdMain').dataSet.getRowCount()!==1) throw new Error('신청 행이 한 개가 아닙니다.');
    const put=async(id,value)=>{const c=get(id); if(c.enabled===false || c.readOnly===true)throw new Error('수정할 수 없는 입력 항목: '+id); if(typeof c.selectItemByValue==='function'){if(!c.getItemByValue(value))throw new Error('선택값 없음: '+id);c.selectItemByValue(value,true);}else if(typeof c.putValue==='function')c.putValue(value);else c.value=value; await pause(250);};
    const expected=[];
    const fill=async(id,value)=>{await put(id,value);expected.push([id,value]);};
    step='날짜·종류·시간 입력';
    if(job.kind==='overtime') {
      await fill('dtiMtWorkYmd',job.date); await pause(650);
      await fill('cmbMtWorkTypCd','1');
      for(const [key,value] of [['ipbAplyBgngH',job.startH],['ipbAplyBgngM',job.startM],['ipbAplyEndH',job.endH],['ipbAplyEndM',job.endM],['txaMtWorkRsnCn',job.reason]]) await fill(key,value);
    } else {
      if(job.kind==='leave') {
        await fill('cmbWorkSittnLclfCd',job.code.slice(0,3)); await fill('cmbWorkSittnSclfCd',job.code);
        if(job.code.startsWith('W01')) await fill('cmbAvAplyScCd','1');
        if(job.code==='W0101') await fill('cmbAvRsnCd',job.leaveReason);
      } else await fill('cmbBsrpScCd',job.tripType);
      const keys=job.kind==='trip'?['dti1','dti2','cmb10','cmb2','cmb3','cmb4']:['dtiWorkYmdFrom','dtiWorkYmdTo','cmbBgngH','cmbBgngM','cmbEndH','cmbEndM'];
      const values=[job.date,job.dateTo,job.startH,job.startM,job.endH,job.endM];
      for(let i=0;i<keys.length;i++) await fill(keys[i],values[i]);
      if(job.kind==='trip'){await fill('ipbDobtNm',job.place);await fill('ipbBsrpCn',job.reason);await fill('mse1',job.contact);}
      else {if(job.code!=='W0101')await fill('ipbWorkSittnRsnCn',job.reason);if(job.contact)await fill('mse1',job.contact);}
    }
    step='입력값 검증'; await pause(800);
    for(const [key,value] of expected) if(String(get(key).value ?? '')!==value) throw new Error('입력값 불일치: '+key);
    const planned=(+job.endH*60 + +job.endM)-(+job.startH*60 + +job.startM);
    if(job.kind==='leave') {
      const days=+get('nbeWorkSittnDdTtl').value, minutes=+get('nbeWorkSittnHrTtl').value*60 + +get('nbeWorkSittnMTtl').value;
      const span=(Date.parse(job.end)-Date.parse(job.start))/86400000+1;
      if(job.code==='W0101' ? !(days>=1&&days<=span&&minutes===0) : !(days===0&&minutes>0&&minutes<=planned)) throw new Error('계산된 복무 일수·시간을 확인하세요.');
    } else if(job.kind==='overtime') {
      const minutes=+get('dtiMtWorkH').value*60 + +get('dtiMtWorkM').value;
      if(!(minutes>0&&minutes<=planned))throw new Error('계산된 초과근무 시간을 확인하세요.');
    } else {
      const ds=get('grdMain').dataSet;
      for(const [key,value] of [['bgngYmd',job.date],['endYmd',job.dateTo],['bgngHh',job.startH],['bgngMm',job.startM],['endHh',job.endH],['endMm',job.endM]]) if(String(ds.getValue(0,key))!==value)throw new Error('출장 표 날짜·시간 불일치');
      const travelers=get('grdTgpr').dataSet;
      for(let i=0;i<travelers.getRowCount();i++) for(const [key,value] of [['bgngYmd',job.date],['endYmd',job.dateTo]]) if(String(travelers.getValue(i,key))!==value)throw new Error('출장자 기간을 확인하세요.');
    }
    step='승인요청';get(job.kind==='trip'?'btnAply':'btnAprvDmnd').click();
    const draft=await wait(()=>find(draftId));
    step='개인결재선 지정';draft.lookup('btnSelectMySancr').click();
    const line=await wait(()=>find(lineId));const grid=line.lookup('grd3');
    await wait(()=>grid.dataSet.getRowCount()>0);
    const matches=[];for(let i=0;i<grid.dataSet.getRowCount();i++)if(String(grid.dataSet.getValue(i,'snclnNm')).trim()===job.line)matches.push(i);
    if(matches.length!==1)throw new Error('같은 이름의 개인결재선이 정확히 한 개 있어야 합니다.');
    grid.selectRows([matches[0]]);await wait(()=>line.lookup('grd2').dataSet.getRowCount()>0);
    line.lookup('btn4').click();await wait(()=>!find(lineId));
    await wait(()=>draft.lookup('grdSancr').dataSet.getRowCount()>=2);
    return {ok:true,step:'상신 전 확인',message:'입력 검증과 개인결재선 지정을 마쳤습니다. 내용을 확인한 뒤 상신하세요.'};
  }catch(error){return {ok:false,step,error:error.message};}
}

let running=false;
export async function startNeisRoute(job) {
  if(running)return {ok:false,error:'복무 자동 신청이 진행 중입니다.'};
  const {neisLastRun}=await chrome.storage.session.get('neisLastRun');
  if(neisLastRun?.running && Date.now()-Number(neisLastRun.at||0)<180000)return {ok:false,error:'복무 자동 신청이 진행 중입니다.'};
  running=true;
  try {
    const candidates=(await chrome.tabs.query({})).filter(tab=>{try{const u=new URL(tab.url);return u.hostname==='pen.neis.go.kr'&&u.pathname==='/jsp/main.jsp';}catch{return false;}});
    const ready=[];
    for(const tab of candidates){const r=await chrome.scripting.executeScript({target:{tabId:tab.id},world:'MAIN',func:()=>!!window.cpr?.core?.Platform?.INSTANCE&&!!document.querySelector('a.cl-sidenavigation-item')}).catch(()=>[]);if(r[0]?.result)ready.push(tab);}
    if(ready.length!==1)throw new Error(ready.length?'나이스 메인 탭을 하나만 열어주세요.':'로그인된 부산 나이스 메인 탭을 먼저 열어주세요.');
    const tab=ready[0];
    await chrome.storage.session.set({neisLastRun:{running:true,step:'신청 시작',at:Date.now()}});
    await chrome.tabs.update(tab.id,{active:true});await chrome.windows.update(tab.windowId,{focused:true});
    const results=await chrome.scripting.executeScript({target:{tabId:tab.id},world:'MAIN',func:runNeisRoute,args:[job]});
    const result=results[0]?.result||{ok:false,error:'나이스 응답 없음'};
    await chrome.storage.session.set({neisLastRun:{...result,running:false,at:Date.now()}});return result;
  }catch(error){const result={ok:false,error:error.message};await chrome.storage.session.set({neisLastRun:{...result,running:false,at:Date.now()}});return result;}
  finally{running=false;}
}
