import { readSourceHtml, copyNotice } from './notice-rich.js';
import { preserveNotice, preserveNoticeHtml, noticeTitle, cleanNoticeDocument } from './notice-preserve.js';
const $=id=>document.getElementById(id);
const title=$('noticeSourceTitle'),body=$('noticeRichPreview');
let converted=false;
function status(text){$('status').textContent=text;$('status').hidden=!text;}
export function currentNotice(){return {title:title.value.trim(),body:body.innerText||body.textContent||''};}
function setSource(text,html=''){
 if(html)body.innerHTML=cleanNoticeDocument(html).body.innerHTML;else body.textContent=text;
 converted=false;
 const found=text.match(/(?:^|\n)\s*제\s*목[ \t]*[:：]?[ \t]*([^\n]+)/)?.[1];
 if(found)title.value=noticeTitle(found);
}
export async function prepareNotice(){
 if(converted){status('제목은 제목칸에, 본문은 1. 관련과 원문 2번 이하로 준비되어 있습니다.');return;}
 let html=body.innerHTML;
 let text=currentNotice().body;
 if(!text.trim()){
  html='';text='';
  if(navigator.clipboard.read){for(const item of await navigator.clipboard.read()){
   if(item.types.includes('text/html'))html=await (await item.getType('text/html')).text();
   if(item.types.includes('text/plain'))text=await (await item.getType('text/plain')).text();
  }}else text=await navigator.clipboard.readText();
  if(!html&&!text.trim())throw new Error('문서관리카드에서 시행 정보까지 본문복사 후 공문안내를 누르세요.');
 }
 // Keep the clipboard original out of the output until conversion succeeds.
 const source=html?readSourceHtml(html).body:text;
 let result;
 try { result=preserveNotice(source); }
 catch(error) { if(text && text!==source)result=preserveNotice(text);else throw error; }
 const resultHtml=html?preserveNoticeHtml(html,result.reference):null;
 const found=source.match(/(?:^|\n)\s*제\s*목[ \t]*[:：]?[ \t]*([^\n]+)/)?.[1];
 title.value=noticeTitle(found||title.value);
 if(resultHtml!==null)body.innerHTML=resultHtml;else body.textContent=result.body;
 converted=true;
 status('본문: 1. 관련(시행 부서·번호·날짜) + 원문 2번 이하. 제목은 제목칸에만 표시했습니다.');
}
body.addEventListener('paste',event=>{
 event.preventDefault();
 try{const html=event.clipboardData?.getData('text/html')||'';const text=html?readSourceHtml(html).body:event.clipboardData?.getData('text/plain')||'';setSource(text,html);status('본문을 가져왔습니다. 공문안내를 누르면 시행 문서번호와 안내초안을 함께 정리합니다.');}catch(e){status(e.message);}
});
$('noticeTitleCopy').addEventListener('click',async()=>{
 try{if(!title.value.trim())throw new Error('제목을 입력하세요.');await navigator.clipboard.writeText(title.value.trim());status('제목을 복사했습니다.');}catch(e){status(e.message);}
});
$('noticeRichCopy').addEventListener('click',async()=>{
 try{const text=currentNotice().body;if(!text.trim())throw new Error('본문을 입력하세요.');await copyNotice(body.innerHTML,text);status('수정한 본문과 표를 복사했습니다.');}catch(e){status(e.message);}
});
chrome.storage.onChanged.addListener((changes,area)=>{
 if(area==='session'&&changes.lastNoticeTitle){title.value=noticeTitle(changes.lastNoticeTitle.newValue||'');body.replaceChildren();converted=false;status('선택한 공문의 본문복사 후 공문안내를 누르세요.');}
});
void chrome.storage.session.get('lastNoticeTitle').then(st=>{if(!title.value&&st.lastNoticeTitle)title.value=noticeTitle(st.lastNoticeTitle);});
