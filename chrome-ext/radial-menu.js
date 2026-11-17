(() => {
 if(globalThis.__penRadialLoaded)return;globalThis.__penRadialLoaded=true;
 let host=null, editor=null, checked=null, undo=null;
 function close(){host?.remove();host=null;}
 function frame(){
  close();host=document.createElement('div');host.id='pen-radial-menu';
  host.style.cssText='position:fixed;inset:0;z-index:2147483647;pointer-events:none';
  const shadow=host.attachShadow({mode:'closed'});
  shadow.innerHTML='<style>*{box-sizing:border-box}button{cursor:pointer;font:13px "Malgun Gothic",sans-serif}button:focus-visible{outline:3px solid #ff9b18}button:disabled{opacity:.5;cursor:default}.wheel{position:absolute;width:300px;height:300px;pointer-events:auto;border-radius:50%;background:#eef4fbed;box-shadow:0 8px 30px #1235}.wheel button{position:absolute;width:78px;height:66px;border:1px solid #c5d6ef;border-radius:50%;background:white;color:#123c70;box-shadow:0 2px 8px #2342}.wheel button:hover{background:#dceaff}.wheel .center{left:111px;top:117px;background:#245fc2;color:white}.panel{position:absolute;right:12px;top:12px;width:min(520px,calc(100vw - 24px));max-height:calc(100vh - 24px);overflow:auto;pointer-events:auto;background:white;color:#24364b;padding:18px;border:2px solid #245fc2;border-radius:14px;font:14px/1.6 "Malgun Gothic",sans-serif;box-shadow:0 8px 30px #1235}.panel button{padding:8px;margin:4px;border:1px solid #ccd8e9;border-radius:7px;background:#eef4ff}.preview{white-space:pre-wrap;border:1px solid #ddd;padding:12px;overflow-wrap:anywhere}.message{white-space:pre-wrap}.actions{position:sticky;top:0;background:white}</style>';
  document.documentElement.append(host);return shadow;
 }
 function snapshot(el) {
  if(el.tagName==='TEXTAREA')return {text:el.value.replace(/\r\n?/g,'\n'),nodes:[]};
  let text='';const nodes=[];
  const newline=()=>{if(text && !text.endsWith('\n'))text+='\n';};
  function walk(node){
   if(node.nodeType===3){nodes.push({node,start:text.length,end:text.length+node.data.length});text+=node.data;return;}
   if(node.nodeType!==1||/^(SCRIPT|STYLE|NOSCRIPT)$/.test(node.tagName))return;
   if(node.tagName==='BR'){text+='\n';return;}
   const block=/^(P|DIV|LI|TR|H[1-6])$/.test(node.tagName);
   if(block)newline();for(const child of node.childNodes)walk(child);if(block)newline();
  }
  walk(el);return {text,nodes};
 }
 function editable(el){return el?.isConnected && !el.disabled && !el.readOnly && (el.tagName==='TEXTAREA'||el.isContentEditable);}
 async function authorized(action){const r=await chrome.runtime.sendMessage({type:'RADIAL_ACTION',action});if(!r?.ok)throw new Error(r?.error||'기능을 열지 못했습니다.');return r;}
 function panel(message=''){
  const shadow=frame(),box=document.createElement('section');box.className='panel';box.setAttribute('role','dialog');box.setAttribute('aria-label','공문점검');
  box.innerHTML='<div class="actions"><strong>공문점검</strong><button data-close>닫기</button></div><p class="message"></p><div class="preview"></div><button data-apply>수정 적용</button><button data-undo disabled>수정 취소</button>';
  shadow.append(box);box.querySelector('[data-close]').onclick=close;
  const status=box.querySelector('.message'),preview=box.querySelector('.preview'),apply=box.querySelector('[data-apply]'),revert=box.querySelector('[data-undo]');
  status.textContent=message;apply.disabled=true;
  if(message)return;
  if(!editable(editor)){status.textContent=message||'수정할 본문 입력칸 안에서 Shift+오른쪽 클릭하세요. 별도 한글·문서관리카드 창은 이 Chrome 메뉴로 직접 수정할 수 없습니다.';return;}
  const snap=snapshot(editor);checked=PenProofread.proofreadNotice(snap.text);
  if(!checked.ok){status.textContent=checked.error;return;}
  preview.innerHTML=PenProofread.correctionHtml(checked.source,checked.edits);
  status.textContent='수정안 '+checked.edits.length+'곳 · 번호는 각 상위 항목 안에서 1/가부터, 들여쓰기는 같은 단계의 첫 항목 기준입니다. 중간 발췌라면 적용하지 마세요.\n'+(editor.tagName==='TEXTAREA'?'이 입력칸은 색상 서식을 지원하지 않아 수정 부분은 이 창에서 빨간색으로 표시합니다.':'적용하면 본문의 바뀐 글자에 빨간색과 배경 표시를 남깁니다.');
  apply.disabled=!checked.edits.length;
  apply.onclick=async()=>{
   apply.disabled=true;
   try {
    await authorized('proofread');
    if(!editable(editor)||snapshot(editor).text!==checked.source)throw new Error('검사 후 원문이 바뀌었습니다. 다시 점검하세요.');
    const old=editor.tagName==='TEXTAREA'?editor.value:editor.innerHTML;
    if(!editor.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertReplacementText',data:null})))throw new Error('편집기가 외부 수정을 허용하지 않습니다.');
    if(snapshot(editor).text!==checked.source)throw new Error('편집기가 내용을 변경했습니다. 다시 점검하세요.');
    if(editor.tagName==='TEXTAREA'){
     Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(editor,checked.corrected);
    }else{
     const current=snapshot(editor);
     const points=checked.edits.map(edit=>{
      const start=current.nodes.find(n=>n.start<=edit.start && n.end>edit.start);
      const end=edit.end===edit.start?start:current.nodes.find(n=>n.start<edit.end && n.end>=edit.end);
      if(!start||!end||current.nodes.some(n=>n.end>edit.start && n.start<edit.end && !n.node.parentElement.isContentEditable)||!start.node.parentElement.isContentEditable||!end.node.parentElement.isContentEditable)throw new Error('수정 위치가 잠겨 있거나 서식 경계를 넘습니다. 직접 확인해주세요.');
      return {edit,start,end};
     });
     try {
      for(const {edit,start,end} of points.reverse()){
       const range=document.createRange();range.setStart(start.node,edit.start-start.start);range.setEnd(end.node,edit.end-end.start);range.deleteContents();
       const span=document.createElement('span');span.style.cssText='color:#c62828;background-color:#fff0f0;text-decoration:underline;white-space:pre-wrap';span.title=edit.message;span.textContent=edit.after;range.insertNode(span);
      }
     }catch(e){editor.innerHTML=old;throw e;}
    }
    editor.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertReplacementText',data:null}));
    editor.dispatchEvent(new Event('change',{bubbles:true}));
    if(snapshot(editor).text!==checked.corrected)throw new Error('편집기가 수정 결과를 유지하지 않았습니다. 본문을 다시 확인하세요.');
    undo={old,after:editor.tagName==='TEXTAREA'?editor.value:editor.innerHTML};revert.disabled=false;
    status.textContent='본문에 '+checked.edits.length+'곳을 수정했습니다. 저장·상신 전에 내용을 확인하세요.';
   }catch(e){status.textContent=e.message;}
  };
  revert.onclick=()=>{
   if(!editable(editor)||(editor.tagName==='TEXTAREA'?editor.value:editor.innerHTML)!==undo.after){status.textContent='적용 이후 편집한 내용이 있어 취소하지 않았습니다.';return;}
   if(editor.tagName==='TEXTAREA')Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(editor,undo.old);else editor.innerHTML=undo.old;
   editor.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'historyUndo'}));editor.dispatchEvent(new Event('change',{bubbles:true}));revert.disabled=true;status.textContent='이번 수정을 취소했습니다.';
  };
 }
 document.addEventListener('contextmenu',event=>{
  if(!event.isTrusted||!event.shiftKey)return;
  event.preventDefault();event.stopPropagation();
  editor=event.target.closest?.('textarea,[contenteditable="true"],[contenteditable=""]')||null;
  if(event.target.closest?.('[contenteditable="false"]'))editor=null;
  checked=null;undo=null;
  const shadow=frame(),wheel=document.createElement('div');wheel.className='wheel';wheel.setAttribute('role','dialog');wheel.setAttribute('aria-label','교직원 업무도우미 원형 메뉴');
  wheel.style.left=Math.max(0,Math.min(event.clientX-150,innerWidth-300))+'px';wheel.style.top=Math.max(0,Math.min(event.clientY-150,innerHeight-300))+'px';shadow.append(wheel);
  const actions=[['portal','업무포털'],['neis','나이스'],['edufine','K에듀파인'],['travel','출장'],['notice','공문안내'],['proofread','공문점검']];
  actions.forEach(([action,label],i)=>{
   const button=document.createElement('button');button.textContent=label;const angle=(-90+i*60)*Math.PI/180;
   button.style.left=(111+106*Math.cos(angle))+'px';button.style.top=(117+106*Math.sin(angle))+'px';wheel.append(button);
   button.onclick=async()=>{try {await authorized(action);if(action==='proofread')panel();else close();}catch(e){panel(e.message);}};
  });
  const dismiss=document.createElement('button');dismiss.className='center';dismiss.textContent='닫기';dismiss.onclick=close;wheel.append(dismiss);wheel.querySelector('button').focus();
 },true);
 document.addEventListener('keydown',event=>{if(event.key==='Escape'&&host){close();event.preventDefault();}},true);
 document.addEventListener('pointerdown',event=>{if(host&&!event.composedPath().includes(host))close();},true);
})();
