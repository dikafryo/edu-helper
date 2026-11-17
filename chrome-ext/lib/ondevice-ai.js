/**
 * On-device built-in AI (Gemini Nano) helpers.
 * Feature-detect LanguageModel / Summarizer; never call cloud endpoints.
 * Graceful fallback to null / heuristic when unavailable.
 */

const KO_OPTS = {
  expectedInputs: [{ type: 'text', languages: ['ko', 'en'] }],
  expectedOutputs: [{ type: 'text', languages: ['ko'] }]
};

function withTimeout(promise, ms, label) {
  let timer;
  const to = new Promise((_, rej) => {
    timer = setTimeout(() => rej(new Error('timeout:' + (label || 'ai') + ':' + ms)), ms);
  });
  return Promise.race([promise, to]).finally(() => { try { clearTimeout(timer); } catch (_) {} });
}

export async function getPromptAvailability() {
  if (typeof LanguageModel === 'undefined') {
    return { ok: false, reason: 'no-api', availability: 'unavailable' };
  }
  try {
    const availability = await LanguageModel.availability(KO_OPTS);
    return { ok: availability !== 'unavailable', reason: availability, availability };
  } catch (e) {
    return { ok: false, reason: String(e?.message || e), availability: 'unavailable' };
  }
}

export async function getSummarizerAvailability() {
  if (typeof Summarizer === 'undefined') {
    return { ok: false, reason: 'no-api', availability: 'unavailable' };
  }
  try {
    const availability = await Summarizer.availability();
    return { ok: true && availability !== 'unavailable', reason: availability, availability };
  } catch (e) {
    return { ok: false, reason: String(e?.message || e), availability: 'unavailable' };
  }
}

function monitorDownload(onProgress) {
  return {
    monitor(m) {
      m.addEventListener('downloadprogress', (e) => {
        const pct = e.total ? Math.floor((e.loaded / e.total) * 100) : Math.floor((e.loaded || 0) * 100);
        if (typeof onProgress === 'function') onProgress(pct);
      });
    }
  };
}

/** Local 공문 요약. Returns { ok, text, source:'ondevice'|'fallback', error? } */
export async function summarizeGongmun(text, { onProgress } = {}) {
  const clipped = String(text || '').slice(0, 6000).trim();
  if (!clipped) return { ok: false, source: 'fallback', error: '본문 없음' };

  let avail = { ok: false, availability: 'unavailable' };
  try { avail = await withTimeout(getSummarizerAvailability(), 4000, 'sum-avail'); } catch (_) {}
  if (avail.ok && avail.availability !== 'unavailable') {
    try {
      const summarizer = await withTimeout(Summarizer.create({
        type: 'key-points',
        format: 'plain-text',
        length: 'short',
        ...monitorDownload(onProgress)
      }), 8000, 'summarizer-create');
      const out = await withTimeout(summarizer.summarize(clipped), 12000, 'summarizer-run');
      summarizer.destroy?.();
      return { ok: true, text: String(out || '').trim(), source: 'ondevice' };
    } catch (e) {
      /* fall through to Prompt or heuristic */
    }
  }

  let pAvail = { ok: false };
  try { pAvail = await withTimeout(getPromptAvailability(), 4000, 'prompt-avail'); } catch (_) {}
  if (pAvail.ok) {
    try {
      const session = await withTimeout(LanguageModel.create({
        ...KO_OPTS,
        initialPrompts: [{
          role: 'system',
          content: '당신은 교육청 공문을 요약합니다. 3~5개 불릿으로 핵심만. 상신/결재 지시 금지. 개인정보·담당자 이름은 ○○○로 가립니다.'
        }],
        ...monitorDownload(onProgress)
      }), 8000, 'prompt-create');
      const out = await withTimeout(session.prompt(`다음 공문을 한국어로 요약하세요:\n\n${clipped}`), 12000, 'prompt-run');
      session.destroy?.();
      return { ok: true, text: String(out || '').trim(), source: 'ondevice' };
    } catch (e) {
      return { ok: false, source: 'fallback', error: String(e?.message || e), text: heuristicSummary(clipped) };
    }
  }

  return { ok: true, text: heuristicSummary(clipped), source: 'fallback' };
}

function heuristicSummary(text) {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const pick = [];
  for (const l of lines) {
    if (/(제목|문서번호|시행|근거|목적|주요|일정|장소)/.test(l) || l.length >= 20) {
      pick.push('· ' + l.slice(0, 120));
    }
    if (pick.length >= 5) break;
  }
  if (!pick.length) pick.push('· ' + text.slice(0, 160));
  return pick.join('\n') + '\n(온디바이스 AI 없음 · 키워드 요약)';
}

/** Rank task cards with optional on-device AI; always merges keyword scores. */
export async function rankTaskCards(pageText, taskCards, { onProgress } = {}) {
  const text = String(pageText || '').slice(0, 4000);
  const cards = Array.isArray(taskCards) ? taskCards : [];
  const keywordRanked = cards
    .map((c) => ({ ...c, score: keywordScore(c, text) }))
    .filter((c) => c.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 8);

  const avail = await getPromptAvailability();
  if (!avail.ok || !keywordRanked.length) {
    return { ok: true, candidates: keywordRanked.slice(0, 5), source: 'keyword' };
  }

  try {
    const names = keywordRanked.map((c, i) => `${i + 1}. ${c.name}`).join('\n');
    const session = await LanguageModel.create({
      ...KO_OPTS,
      initialPrompts: [{
        role: 'system',
        content: '공문 내용과 과제카드 목록을 보고 가장 관련 높은 카드 번호 최대 3개를 JSON 배열로만 답하세요. 예: [1,3,2]. 설명 금지.'
      }],
      ...monitorDownload(onProgress)
    });
    const out = await session.prompt(`공문:\n${text}\n\n과제카드:\n${names}`);
    session.destroy?.();
    const nums = String(out).match(/\d+/g)?.map((n) => Number(n)) || [];
    const picked = [];
    for (const n of nums) {
      const c = keywordRanked[n - 1];
      if (c && !picked.find((x) => x.name === c.name)) {
        picked.push({ ...c, score: Math.max(c.score, 90 - picked.length * 5), aiBoost: true });
      }
      if (picked.length >= 3) break;
    }
    const rest = keywordRanked.filter((c) => !picked.find((p) => p.name === c.name));
    return { ok: true, candidates: [...picked, ...rest].slice(0, 5), source: 'ondevice+keyword' };
  } catch {
    return { ok: true, candidates: keywordRanked.slice(0, 5), source: 'keyword' };
  }
}

function keywordScore(card, text) {
  const raw = (text || '').toLowerCase();
  let score = 0;
  const name = String(card.name || '');
  if (name && raw.includes(name.toLowerCase())) score += 40;
  for (const kw of card.keywords || []) {
    const k = String(kw || '').trim();
    if (k && raw.includes(k.toLowerCase())) score += 12;
  }
  return score;
}

/** Local 공문 다듬기 (버튼 누를 때만). Falls back to masked packet text. */
export async function polishGongmun(maskedText, { onProgress } = {}) {
  const clipped = String(maskedText || '').slice(0, 6000).trim();
  if (!clipped) return { ok: false, source: 'fallback', error: '본문 없음' };

  let pAvail = { ok: false };
  try { pAvail = await withTimeout(getPromptAvailability(), 4000, 'prompt-avail'); } catch (_) {}
  if (pAvail.ok) {
    try {
      const session = await LanguageModel.create({
        ...KO_OPTS,
        initialPrompts: [{
          role: 'system',
          content: '당신은 교육청 안내공문 초안을 다듬습니다. 번호(1. 2. 가. 나.)·붙임 형식을 유지하고, 상신/결재 지시 금지. 개인정보 자리표시자([이름1] 등)는 그대로 둡니다. 결과만 출력.'
        }],
        ...monitorDownload(onProgress)
      });
      const out = await session.prompt('다음 마스킹된 공문을 안내공문 초안으로 다듬으세요:\n\n' + clipped);
      session.destroy && session.destroy();
      return { ok: true, text: String(out || '').trim(), source: 'ondevice' };
    } catch (e) {
      return { ok: false, source: 'fallback', error: String((e && e.message) || e), text: clipped };
    }
  }
  return { ok: true, text: clipped, source: 'fallback', note: '온디바이스 AI 없음 · 마스킹 원문 유지(클립보드용)' };
}
