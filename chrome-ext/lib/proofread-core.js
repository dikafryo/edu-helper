(() => {
const LETTERS = '가나다라마바사아자차카타파하';
const RULES = [[/되요/g,'돼요'], [/돼어/g,'되어'], [/몇일/g,'며칠'], [/뵈요/g,'봬요'], [/않\s*됩니다/g,'안 됩니다'], [/할수(?=\s*(?:있|없))/g,'할 수']];
const token = (rank, index) => (rank % 2 ? LETTERS[index - 1] || '?' : index) + (rank < 2 ? '.' : ')');
function proofreadNotice(text) {
  const source = String(text || '').replace(/\r\n?/g, '\n');
  if (!source.trim()) return { ok:false, error:'검사할 본문이 없습니다. 검사 입력칸에 본문을 붙여넣으세요.' };
  if (source.length > 100000) return { ok:false, error:'본문을 10만 자 이내로 나눠 검사하세요.' };
  const issues = [], state = new Map(), lines = source.split('\n');
  let headings = 0;
  lines.forEach((line, row) => {
    const m = line.match(/^\s*(?:(\d{1,2})\.(?!\d)|([가나다라마바사아자차카타파하])\.|(\d{1,2})\)|([가나다라마바사아자차카타파하])\))\s*(?=\S|$)/u);
    if (m) {
      const rank = m[1] ? 0 : m[2] ? 1 : m[3] ? 2 : 3;
      const raw = m[1] || m[2] || m[3] || m[4];
      const index = rank % 2 ? LETTERS.indexOf(raw) + 1 : Number(raw);
      if (index > 0) {
        headings++;
        const previous = state.get(rank), expected = previous === undefined ? 1 : previous + 1;
        if (index !== expected) issues.push({ line:row+1, type:previous === index ? '번호 중복' : index < expected ? '번호 역순·재시작' : '번호 누락 의심', message:`${token(rank,index)} → 예상 ${token(rank,expected)}${previous === undefined ? ' (중간 발췌라면 정상일 수 있음)' : ''}`, excerpt:line.trim().slice(0,100) });
        state.set(rank,index);
        for (const depth of [...state.keys()]) if (depth > rank) state.delete(depth);
      }
    }
    for (const [regex,replacement] of RULES) {
      regex.lastIndex = 0;
      for (const match of line.matchAll(regex)) issues.push({ line:row+1, type:'오타·띄어쓰기 의심', message:`“${match[0]}” → “${replacement}” 검토`, excerpt:line.trim().slice(0,100) });
    }
  });
  const edits = planEdits(source);
  for (const edit of edits) {
    if(edit.type === '들여쓰기 불일치') issues.push({line:edit.line,type:edit.type,message:edit.message,excerpt:lines[edit.line-1].trim().slice(0,100)});
  }
  const details = issues.length ? issues.map((item,i)=>`${i+1}. [${item.line}줄 / ${item.type}] ${item.message}\n   ${item.excerpt}`).join('\n\n') : '등록된 오타 규칙과 번호 순서에서 의심 사항을 찾지 못했습니다.';
  return { ok:true, issues, edits, source, corrected:applyEdits(source,edits), text:`공문 오타·항목 순서 확인\n${lines.length}줄 · 번호 항목 ${headings}개 · 확인할 곳 ${issues.length}개\n\n${details}\n\n※ 로컬 규칙 검사이며 전체 맞춤법을 보장하지 않습니다. 중간 발췌·독립 목록·표는 문맥 확인이 필요합니다. 원문은 수정하지 않았습니다.` };
}

function planEdits(source) {
 const edits=[], counters=new Map(), indents=new Map();let offset=0;
 for(const [row,line] of source.split('\n').entries()) {
  const m=line.match(/^([ \t]*)(?:(\d{1,2})\.(?!\d)|([가나다라마바사아자차카타파하])\.|(\d{1,2})\)|([가나다라마바사아자차카타파하])\))(?=\s|$)/u);
  if(m) {
   const rank=m[2]?0:m[3]?1:m[4]?2:3;
   const expected=(counters.get(rank)||0)+1;counters.set(rank,expected);
   for(const depth of [...counters.keys()])if(depth>rank)counters.delete(depth);
   const original=m[0].slice(m[1].length),replacement=token(rank,expected);
   if(original!==replacement)edits.push({start:offset+m[1].length,end:offset+m[0].length,before:original,after:replacement,line:row+1,type:'번호 순서',message:original+' → '+replacement});
   if(!indents.has(rank))indents.set(rank,m[1]);
   const indent=indents.get(rank);
   if(m[1]!==indent)edits.push({start:offset,end:offset+m[1].length,before:m[1],after:indent,line:row+1,type:'들여쓰기 불일치',message:'같은 단계의 첫 항목과 들여쓰기 통일 ('+m[1].length+' → '+indent.length+'자; 공백·탭 구분)'});
  }
  for(const [regex,replacement] of RULES) {
   regex.lastIndex=0;
   for(const match of line.matchAll(regex))edits.push({start:offset+match.index,end:offset+match.index+match[0].length,before:match[0],after:replacement,line:row+1,type:'오타·띄어쓰기',message:match[0]+' → '+replacement});
  }
  offset+=line.length+1;
 }
 return edits.sort((a,b)=>a.start-b.start||a.end-b.end);
}
function applyEdits(source,edits) {
 let value=source;
 for(const edit of [...edits].sort((a,b)=>b.start-a.start||b.end-a.end))value=value.slice(0,edit.start)+edit.after+value.slice(edit.end);
 return value;
}
function escapeHtml(text) {return String(text).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function correctionHtml(source,edits) {
 let out='',offset=0;
 for(const edit of edits) {out+=escapeHtml(source.slice(offset,edit.start))+'<span style="color:#c62828;background:#fff0f0;text-decoration:underline" title="'+escapeHtml(edit.message)+'">'+escapeHtml(edit.after || '⟦삭제⟧')+'</span>';offset=edit.end;}
 return out+escapeHtml(source.slice(offset));
}
globalThis.PenProofread={proofreadNotice,applyEdits,correctionHtml};

})();
