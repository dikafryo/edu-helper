// Only visible document content; never use body.textContent (scripts/layout noise).
export function readDocumentContext() {
  const selected = String(window.getSelection?.() || '').trim();
  const candidates = [...document.querySelectorAll('[contenteditable="true"],article,[role="document"]')].filter(el=>el.getClientRects().length);
  const text = selected || candidates.map(el=>el.innerText||'').sort((a,b)=>b.length-a.length)[0] || document.body?.innerText || '';
  const titleMatch = text.match(/(?:^|\n)\s*제\s*목\s*[:：]?\s*([^\n]+)/);
  const field = document.querySelector('input[aria-label="제목"],input[name="docTitle"],input[id="docTitle"]');
  const title = (field?.value || titleMatch?.[1] || '').trim();
  const documentLike = !!title && /(?:^|\n)\s*(?:1\.\s*관련|시행\s|수신\s)/m.test(text);
  return {ok:!!selected || documentLike,title,body:selected || (documentLike?text:''),error:'문서 본문을 읽지 못했습니다. 별도 한글/문서관리카드 창은 본문복사 후 아래 원문 칸에 붙여넣으세요.'};
}

export function parseIssuedReference(text) {
  const raw=String(text||'');
  const m=raw.match(/(?:^|\n)\s*시\s*행\s*[:：]?\s*([가-힣A-Za-z0-9·ㆍ() ]{2,60}?)\s*[-–—]\s*(\d{1,8})\s*\(\s*(\d{4})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})\s*[.일]?\s*\)/m);
  if(!m)return {ok:false,error:'시행 부서·번호·날짜를 찾지 못했습니다. 본문 하단의 시행 줄까지 복사해주세요. 본문 1. 관련 번호는 대신 사용하지 않습니다.'};
  const date=new Date(Date.UTC(+m[3],+m[4]-1,+m[5]));
  if(date.getUTCFullYear()!==+m[3]||date.getUTCMonth()+1!==+m[4]||date.getUTCDate()!==+m[5])return {ok:false,error:'시행 날짜를 확인하세요.'};
  const docId=m[1].replace(/\s+/g,'')+'-'+m[2];
  return {ok:true,docId,date:`${m[3]}. ${+m[4]}. ${+m[5]}.`,value:`1. 관련: ${docId}(${m[3]}. ${+m[4]}. ${+m[5]}.)`,source:'시행'};
}

export function markTargetFrame(enabled) {
  const id='pen-target-frame';document.getElementById(id)?.remove();
  if(!enabled)return;
  const border=document.createElement('div');border.id=id;
  border.style.cssText='position:fixed;inset:0;border:3px solid #e53935;box-sizing:border-box;pointer-events:none;z-index:2147483647;';
  const label=document.createElement('span');label.textContent='교직원 업무도우미 읽기 대상';
  label.style.cssText='position:absolute;right:8px;top:0;background:#c62828;color:white;padding:3px 8px;font:12px sans-serif;';border.appendChild(label);document.documentElement.appendChild(border);
}
