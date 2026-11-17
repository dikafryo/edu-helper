/** Local 할 일 · 일정 (chrome.storage.local). Urgent-first sort. */

function uid() {
  return 't' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

export function todayYmd() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
}

export function workSortKey(due, done) {
  if (done) return '9|' + (due || '') + '|z';
  if (!due) return '2|9999-12-31|a';
  if (due < todayYmd()) return '0|' + due + '|a';
  return '1|' + due + '|a';
}

export async function loadTodos() {
  const { todos = [] } = await chrome.storage.local.get('todos');
  return Array.isArray(todos) ? todos : [];
}

export async function saveTodos(todos) {
  await chrome.storage.local.set({ todos: todos || [] });
}

export async function loadSchedules() {
  const { schedules = [] } = await chrome.storage.local.get('schedules');
  return Array.isArray(schedules) ? schedules : [];
}

export async function saveSchedules(schedules) {
  await chrome.storage.local.set({ schedules: schedules || [] });
}

export async function addTodo({ title, due, body, source }) {
  const todos = await loadTodos();
  const item = {
    Id: uid(),
    Title: String(title || '').trim() || '(제목 없음)',
    Due: due || null,
    Body: body || '',
    Source: source || 'manual',
    Done: false,
    Created: new Date().toISOString()
  };
  todos.push(item);
  await saveTodos(todos);
  return item;
}

export async function setTodoDone(id, done) {
  const todos = await loadTodos();
  for (const t of todos) {
    if (t.Id === id) t.Done = !!done;
  }
  await saveTodos(todos);
}

export async function removeTodo(id) {
  const todos = (await loadTodos()).filter((t) => t.Id !== id);
  await saveTodos(todos);
}

export async function registerScheduleFromTodo(todoId) {
  const todos = await loadTodos();
  const t = todos.find((x) => x.Id === todoId);
  if (!t) return { ok: false, error: '할 일 없음' };
  const schedules = await loadSchedules();
  const existing = schedules.find((s) => s.TodoId === todoId);
  if (existing) return { ok: true, schedule: existing, already: true };
  const sched = {
    Id: uid(),
    TodoId: todoId,
    Title: t.Title,
    Date: t.Due || todayYmd(),
    Body: t.Body || '',
    GoogleSaved: false,
    Created: new Date().toISOString()
  };
  schedules.push(sched);
  await saveSchedules(schedules);
  return { ok: true, schedule: sched };
}

export async function markScheduleGoogleSaved(schedId, note) {
  const schedules = await loadSchedules();
  for (const s of schedules) {
    if (s.Id === schedId) {
      s.GoogleSaved = true;
      s.GoogleSavedAt = new Date().toISOString();
      if (note) s.GoogleNote = note;
    }
  }
  await saveSchedules(schedules);
  const { gcalSaved = {} } = await chrome.storage.local.get('gcalSaved');
  gcalSaved[schedId] = { SavedAt: new Date().toISOString(), Note: note || '' };
  await chrome.storage.local.set({ gcalSaved: gcalSaved });
}

export async function listWorkItems() {
  const todos = await loadTodos();
  const schedules = await loadSchedules();
  const rows = [];
  for (const t of todos) {
    const sched = schedules.find((s) => s.TodoId === t.Id) || null;
    rows.push({
      Kind: 'todo',
      Id: t.Id,
      Title: t.Title,
      Due: t.Due || (sched && sched.Date) || '',
      Done: !!t.Done,
      Body: t.Body || '',
      Sched: sched,
      Todo: t
    });
  }
  for (const s of schedules) {
    if (s.TodoId && todos.find((t) => t.Id === s.TodoId)) continue;
    rows.push({
      Kind: 'sched',
      Id: s.Id,
      Title: s.Title,
      Due: s.Date || '',
      Done: false,
      Body: s.Body || '',
      Sched: s,
      Todo: null
    });
  }
  rows.sort((a, b) => {
    const ka = workSortKey(a.Due, a.Done);
    const kb = workSortKey(b.Due, b.Done);
    if (ka < kb) return -1;
    if (ka > kb) return 1;
    return String(a.Title).localeCompare(String(b.Title), 'ko');
  });
  return rows;
}
