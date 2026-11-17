import { parseIssuedReference } from './document-context.js';
export function noticeTitle(title) {
 const value=String(title||'').trim();
 return value && !/안내$/.test(value) ? value+' 안내' : value;
}
export function preserveNotice(body) {
 const text=String(body||'').replace(/\r/g,'');
 const issued=parseIssuedReference(text);
 if(!issued.ok)throw new Error(issued.error);
 const start=/(?:^|\n)[ \t\u00a0]*2\.[ \t\u00a0]*/m.exec(text);
 if(!start)throw new Error('원문의 2. 항목을 찾지 못했습니다. 본문 전체를 다시 복사해주세요.');
 const tail=text.slice(start.index).trimStart();
 const end=/(?:^|\n)[ \t]*시\s*행\s*[:：]?/m.exec(tail);
 const continuation=(end?tail.slice(0,end.index):tail).trimEnd();
 return {reference:issued.value,body:issued.value+'\n'+continuation};
}
// Preserve copied table layout and inline formatting from item 2 onward.
export function cleanNoticeDocument(html) {
 const doc=new DOMParser().parseFromString(html,'text/html');
 doc.querySelectorAll('script,style,iframe,object,embed,img,link,meta,svg,math,form,input,button').forEach(el=>el.remove());
 for(const el of doc.querySelectorAll('*')) {
   for(const attr of [...el.attributes]) {
     if(!['rowspan','colspan','style'].includes(attr.name))el.removeAttribute(attr.name);
   }
   if(el.hasAttribute('style')) {
     const safe=[];
     for(const name of ['font-weight','font-style','text-align','border','border-collapse','padding','width','height','vertical-align']) {
       const value=el.style.getPropertyValue(name);
       if(value && !/url|expression|var\(/i.test(value))safe.push(name+':'+value);
     }
     el.setAttribute('style',safe.join(';'));
   }
 }
 return doc;
}
export function preserveNoticeHtml(html, reference) {
 const doc=cleanNoticeDocument(html);
 const entries=[];let text='';
 const newline=()=>{if(text&&!text.endsWith('\n'))text+='\n';};
 function walk(node){
  if(node.nodeType===3){entries.push({node,start:text.length,end:text.length+node.textContent.length});text+=node.textContent;return;}
  if(node.nodeType!==1)return;
  if(node.tagName==='BR'){text+='\n';return;}
  const block=/^(P|DIV|TR|LI|H[1-6])$/.test(node.tagName);
  if(block)newline();
  for(const child of node.childNodes)walk(child);
  if(block)newline();
 }
 walk(doc.body);
 const start=/(?:^|\n)[ \t\u00a0]*2\.[ \t\u00a0]*/m.exec(text);
 if(!start)throw new Error('서식 원문에서 2. 항목을 찾지 못했습니다. 원문을 다시 붙여넣으세요.');
 const from=start.index+start[0].indexOf('2');
 const tail=text.slice(from); const footer=/(?:^|\n)[ \t]*시\s*행\s*[:：]?/m.exec(tail);
 const to=footer?from+footer.index:text.length;
 const first=entries.find(e=>e.end>from);const last=[...entries].reverse().find(e=>e.start<to);
 if(!first||!last)throw new Error('본문 범위를 확인하지 못했습니다.');
 const range=doc.createRange();range.setStart(first.node,from-first.start);range.setEnd(last.node,Math.min(last.node.textContent.length,to-last.start));
 const out=doc.createElement('div');const p=doc.createElement('p');p.textContent=reference;out.append(p,range.cloneContents());
 return out.innerHTML;
}
