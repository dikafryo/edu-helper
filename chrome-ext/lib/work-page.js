export async function navigateWorkMenu(page,execute=false) {
 const names=page==='trip'?['개인출장관리']:page==='duty'?['개인근무상황관리']:['일일근무상황조회'];
 const shown=el=>el.getClientRects().length && el.getAttribute('aria-disabled')!=='true';
 const label=el=>(el.innerText||el.textContent||'').replace(/\s*\d+단계(?: 메뉴항목)?\s*$/,'').replace(/\s+/g,'').trim();
 const menus=()=>[...document.querySelectorAll('a.cl-sidenavigation-item')].filter(shown);
 const find=()=>{for(const name of names){const matches=menus().filter(el=>label(el)===name);if(matches.length===1)return matches[0];if(matches.length>1)return null;}return null;};
 const parents=menus().filter(el=>label(el)==='복무');
 if(!execute)return {ok:!!find()||parents.length===1};
 let target=find();
 if(!target && parents.length===1 && parents[0].classList.contains('cl-collapsed')){
  parents[0].click();
  for(let i=0;i<20&&!target;i++){await new Promise(r=>setTimeout(r,150));target=find();}
 }
 if(!target)return {ok:false,error:'복무 → '+(page==='trip'?'개인출장관리':page==='duty'?'개인근무상황관리':'일일근무상황조회')+' 메뉴를 찾지 못했습니다. 복무 메뉴가 표시되는지 확인해주세요.'};
 const name=label(target);target.click();
 if(page==='trip') {
  const find=id=>window.cpr?.core?.Platform?.INSTANCE?.getAllRunningAppInstances?.().find(app=>app.app?.id===id);
  const base='edu/ga/srv/mym/mm/srv_mymmm03';
  if(find(base+'_p00'))return {ok:true,message:'작성 중인 출장 신청 창을 확인하세요.'};
  let list;
  for(let i=0;i<30&&!list;i++){list=find(base+'_m00');if(!list)await new Promise(r=>setTimeout(r,150));}
  const button=list?.lookup('btnAply');
  if(!button || button.enabled===false)return {ok:false,error:'개인출장관리 화면을 열었습니다. 신청 버튼을 직접 눌러주세요.'};
  button.click();
  return {ok:true,message:'출장 신청 창 열기를 요청했습니다. 내용을 작성한 뒤 최종 상신하세요.'};
 }
 return {ok:true,message:name+' 메뉴를 열었습니다.'};
}
export async function openWorkPage(page) {
 const tabs=(await chrome.tabs.query({url:'https://*.neis.go.kr/*'})).filter(t=>{try{return new URL(t.url).pathname==='/jsp/main.jsp';}catch(_){return false;}});
 const active=tabs.filter(t=>t.active);const tab=active.length===1?active[0]:tabs.length===1?tabs[0]:null;
 if(!tab)return {ok:false,error:'나이스 메인 창을 하나 선택한 뒤 다시 실행하세요.'};
 const frames=await chrome.scripting.executeScript({target:{tabId:tab.id,allFrames:true},world:'MAIN',func:navigateWorkMenu,args:[page,false]});
 const matches=frames.filter(f=>f.result?.ok);
 if(matches.length!==1)return {ok:false,error:'나이스의 복무 메뉴를 한 곳으로 확인하지 못했습니다.'};
 const result=await chrome.scripting.executeScript({target:{tabId:tab.id,frameIds:[matches[0].frameId]},func:navigateWorkMenu,args:[page,true]});
 return result[0]?.result||{ok:false,error:'메뉴 응답이 없습니다.'};
}
