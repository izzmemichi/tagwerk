import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';

// Zugangsdaten kommen aus config.js (beim Deployment aus Umgebungsvariablen erzeugt, siehe build.sh).
// Der Schlüssel ist öffentlich; die Daten schützt der Zeilenschutz in Supabase.
const { url: SUPABASE_URL, key: SUPABASE_KEY } = window.TAGWERK_CONFIG || {};
if (!SUPABASE_URL || !SUPABASE_KEY) {
  document.getElementById('root').innerHTML = '<div class="boot">config.js missing, see README</div>';
  throw new Error('Tagwerk: config.js missing');
}
const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

const TABLES = ['groups', 'lists', 'tasks', 'steps'];
const COLS = {
  groups: ['id', 'name', 'sort', 'is_expanded', 'deleted'],
  lists: ['id', 'name', 'theme', 'sort', 'is_default', 'group_id', 'created_at', 'deleted'],
  tasks: ['id', 'list_id', 'title', 'note', 'is_completed', 'completed_at', 'is_important', 'my_day_date',
    'my_day_added_at', 'due', 'reminder', 'repeat_raw', 'spawned_next', 'created_at', 'sort', 'deleted'],
  steps: ['id', 'task_id', 'title', 'is_completed', 'sort', 'deleted'],
};

// ---------- Kleine Helfer ----------

const store = {
  get(key, fallback) { try { const v = localStorage.getItem('tagwerk.' + key); return v == null ? fallback : JSON.parse(v); } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem('tagwerk.' + key, JSON.stringify(value)); } catch { /* privat */ } },
};
// ---------- Sprache (Deutsch ist die Quellsprache, Englisch wird übersetzt) ----------

const EN = {
  'Blau': 'Blue',
  'Indigo': 'Indigo',
  'Lila': 'Purple',
  'Rosé': 'Rose',
  'Rot': 'Red',
  'Orange': 'Orange',
  'Grün': 'Green',
  'Petrol': 'Teal',
  'Graphit': 'Graphite',
  'Morgenrot': 'Dawn',
  'Lagune': 'Lagoon',
  'Dämmerung': 'Dusk',
  'Mein Tag': 'My Day',
  'Wichtig': 'Important',
  'Geplant': 'Planned',
  'Alle': 'All',
  'Abgeschlossen': 'Completed',
  'Aufgaben': 'Tasks',
  'Heute': 'Today',
  'Morgen': 'Tomorrow',
  'Gestern': 'Yesterday',
  'Täglich': 'Daily',
  'Monatlich': 'Monthly',
  'Jährlich': 'Yearly',
  'Wochentage': 'Weekdays',
  'Wöchentlich': 'Weekly',
  'Wöchentlich: ': 'Weekly: ',
  'Alle %1 %2': 'Every %1 %2',
  'Tag': 'day',
  'Tage': 'days',
  'Woche': 'week',
  'Wochen': 'weeks',
  'Monat': 'month',
  'Monate': 'months',
  'Jahr': 'year',
  'Jahre': 'years',
  'So': 'Sun',
  'Mo': 'Mon',
  'Di': 'Tue',
  'Mi': 'Wed',
  'Do': 'Thu',
  'Fr': 'Fri',
  'Sa': 'Sat',
  'Speichern fehlgeschlagen: ': 'Save failed: ',
  'Löschen fehlgeschlagen: ': 'Delete failed: ',
  'Laden fehlgeschlagen: ': 'Loading failed: ',
  'Unbenannte Liste': 'Untitled list',
  'Einmalig': 'One-time',
  'Erledigt': 'Completed',
  'Liste': 'List',
  'Rhythmus': 'Rhythm',
  'Eigene Reihenfolge': 'My order',
  '%1 von %2': '%1 of %2',
  'Überfällig, ': 'Overdue, ',
  'Notiz': 'Note',
  'Als nicht erledigt markieren': 'Mark as not completed',
  'Erledigen': 'Complete',
  'Konzentriere dich auf deinen Tag': 'Focus on your day',
  'Erledige Aufgaben mit „Mein Tag“, einer Liste, die jeden Tag neu beginnt.': 'Get things done with My Day, a list that starts fresh every day.',
  'Nichts als wichtig markiert': 'Nothing starred yet',
  'Markiere Aufgaben mit dem Stern, damit sie hier erscheinen.': 'Star tasks to see them here.',
  'Nichts geplant': 'Nothing planned',
  'Aufgaben mit Fälligkeitsdatum oder Erinnerung erscheinen hier.': 'Tasks with a due date or reminder show up here.',
  'Keine offenen Aufgaben': 'No open tasks',
  'Alle offenen Aufgaben aus allen Listen erscheinen hier.': 'Open tasks from all lists show up here.',
  'Noch nichts erledigt': 'Nothing completed yet',
  'Erledigte Aufgaben aus allen Listen erscheinen hier.': 'Completed tasks from all lists show up here.',
  'Keine Treffer': 'No results',
  'Suche nach Titel oder Notiz.': 'Search by title or note.',
  'Suche': 'Search',
  'Suchen': 'Search',
  'Neue Liste': 'New list',
  'Abmelden': 'Sign out',
  'Sortieren': 'Sort',
  'Liste umbenennen': 'Rename list',
  'Design': 'Theme',
  'Erledigte anzeigen': 'Show completed',
  'Erledigte ausblenden': 'Hide completed',
  'Liste löschen': 'Delete list',
  'Optionen': 'Options',
  'Nach %1': 'By %1',
  'Listen': 'Lists',
  'Aufgabe hinzufügen': 'Add a task',
  'Nicht wiederholen': 'Don’t repeat',
  'Schließen': 'Close',
  'Schritt löschen': 'Delete step',
  'Nächster Schritt': 'Next step',
  'Schritt hinzufügen': 'Add step',
  'Zu „Mein Tag“ hinzugefügt': 'Added to My Day',
  'Zu „Mein Tag“ hinzufügen': 'Add to My Day',
  'Erinnerung': 'Reminder',
  'Fällig': 'Due',
  'Wiederholen': 'Repeat',
  'Notiz hinzufügen': 'Add note',
  'Erstellt %1': 'Created %1',
  'Aufgabe löschen': 'Delete task',
  'Wichtig markieren': 'Mark as important',
  'Melde dich mit demselben Konto an wie in der iPhone-App.': 'Sign in with the same account as in the iPhone app.',
  'E-Mail': 'Email',
  'Passwort (mindestens 6 Zeichen)': 'Password (at least 6 characters)',
  'Anmelden': 'Sign in',
  'Konto erstellen': 'Create account',
  '„%1“ wird endgültig gelöscht.': '“%1” will be permanently deleted.',
  'E-Mail oder Passwort falsch. Noch kein Konto? Dann auf „Konto erstellen“.': 'Wrong email or password. No account yet? Use “Create account”.',
  'Bitte bestätige zuerst deine E-Mail über den Link in der Mail.': 'Please confirm your email via the link in the email first.',
  'Diese E-Mail ist schon registriert. Bitte anmelden.': 'This email is already registered. Please sign in.',
  'Das Passwort ist zu kurz (mindestens 6 Zeichen).': 'Password too short (at least 6 characters).',
  'Fehler: ': 'Error: ',
  'Bitte E-Mail und Passwort eingeben.': 'Please enter email and password.',
  'Melde an …': 'Signing in …',
  'Erstelle Konto …': 'Creating account …',
  'Konto angelegt. Bitte bestätige die Mail an %1 und melde dich dann an.': 'Account created. Confirm the email sent to %1, then sign in.',
  'Sprache': 'Language',
};
let lang = store.get('lang', '') || ((navigator.language || 'en').toLowerCase().startsWith('de') ? 'de' : 'en');
const locale = () => (lang === 'de' ? 'de-DE' : 'en-US');
/** Übersetzt einen deutschen Text; %1, %2 werden durch die Argumente ersetzt. */
function tr(key, ...args) {
  let text = lang === 'de' ? key : (EN[key] ?? key);
  args.forEach((a, i) => { text = text.replace('%' + (i + 1), a); });
  return text;
}
document.documentElement.lang = lang;

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const uuid = () => (crypto.randomUUID ? crypto.randomUUID()
  : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));
const DAY = 864e5;
const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const addMonths = (d, n) => {
  const x = new Date(d); const day = x.getDate(); x.setDate(1); x.setMonth(x.getMonth() + n);
  const last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate(); x.setDate(Math.min(day, last)); return x;
};
const today = () => startOfDay(new Date());
const toDate = (iso) => (iso ? new Date(iso) : null);
const offset = (iso) => Math.round((startOfDay(iso) - today()) / DAY);
const isToday = (iso) => !!iso && offset(iso) === 0;
const iso = (d) => (d ? new Date(d).toISOString() : null);
const fmt = (opts) => new Intl.DateTimeFormat(locale(), opts);
const fmtShort = { format: (d) => fmt({ weekday: 'short', day: 'numeric', month: 'short' }).format(d) };
const fmtShortYear = { format: (d) => fmt({ weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }).format(d) };
const fmtLong = { format: (d) => fmt({ weekday: 'long', day: 'numeric', month: 'long' }).format(d) };
const fmtTime = { format: (d) => fmt({ hour: '2-digit', minute: '2-digit', hour12: false }).format(d) };
function dayLabel(d) {
  const o = offset(d);
  if (o === 0) return tr('Heute');
  if (o === 1) return tr('Morgen');
  if (o === -1) return tr('Gestern');
  return (new Date(d).getFullYear() === new Date().getFullYear() ? fmtShort : fmtShortYear).format(new Date(d));
}
const dateInput = (d) => { if (!d) return ''; const x = new Date(d); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
const dateTimeInput = (d) => { if (!d) return ''; const x = new Date(d); return `${dateInput(x)}T${String(x.getHours()).padStart(2, '0')}:${String(x.getMinutes()).padStart(2, '0')}`; };
function splitEmoji(name) {
  const m = String(name || '').match(/^(\p{Extended_Pictographic}️?)\s*(.*)$/u);
  return m ? { emoji: m[1], rest: m[2] } : { emoji: null, rest: name || '' };
}

// ---------- Designs (wie in der App) ----------

const rgb = (r, g, b) => `rgb(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)})`;
const shade = ([r, g, b], k = 0.18) => rgb(r * (1 - k), g * (1 - k), b * (1 - k));
const THEMES = {
  blue: { name: 'Blau', c: [0.25, 0.42, 0.85] }, indigo: { name: 'Indigo', c: [0.36, 0.40, 0.78] },
  purple: { name: 'Lila', c: [0.55, 0.33, 0.75] }, rose: { name: 'Rosé', c: [0.78, 0.29, 0.44] },
  red: { name: 'Rot', c: [0.80, 0.27, 0.24] }, orange: { name: 'Orange', c: [0.85, 0.48, 0.16] },
  green: { name: 'Grün', c: [0.24, 0.55, 0.30] }, teal: { name: 'Petrol', c: [0.10, 0.53, 0.53] },
  graphite: { name: 'Graphit', c: [0.37, 0.41, 0.46] },
  dawn: { name: 'Morgenrot', c: [0.86, 0.47, 0.29], g: [[0.98, 0.62, 0.40], [0.62, 0.36, 0.62]] },
  lagoon: { name: 'Lagune', c: [0.08, 0.50, 0.62], g: [[0.12, 0.62, 0.68], [0.10, 0.30, 0.55]] },
  dusk: { name: 'Dämmerung', c: [0.42, 0.30, 0.68], g: [[0.55, 0.38, 0.85], [0.16, 0.16, 0.40]] },
};
const theme = (key) => {
  const t = THEMES[key] || THEMES.blue;
  const grad = t.g ? `linear-gradient(${rgb(...t.g[0])}, ${rgb(...t.g[1])})` : `linear-gradient(${rgb(...t.c)}, ${shade(t.c)})`;
  return { accent: rgb(...t.c), gradient: grad, name: tr(t.name) };
};

const SMART = {
  myDay: { title: 'Mein Tag', icon: 'sun', theme: 'dawn', color: '#66737f' },
  important: { title: 'Wichtig', icon: 'star', theme: 'rose', color: '#c74a70' },
  planned: { title: 'Geplant', icon: 'calendar', theme: 'teal', color: '#66737f' },
  all: { title: 'Alle', icon: 'infinity', theme: 'graphite', color: '#2e8057' },
  completed: { title: 'Abgeschlossen', icon: 'check', theme: 'green', color: '#2e8057' },
  tasks: { title: 'Aufgaben', icon: 'house', theme: 'indigo', color: '#406bd9' },
};

const ICONS = {
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  star: '<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  infinity: '<path d="M12 12c-2-2.7-3.6-4-5.5-4a4 4 0 0 0 0 8c1.9 0 3.5-1.3 5.5-4s3.6-4 5.5-4a4 4 0 0 1 0 8c-1.9 0-3.5-1.3-5.5-4z"/>',
  check: '<circle cx="12" cy="12" r="8.5"/><path d="M8.3 12.3l2.5 2.5 5-5.2"/>',
  house: '<path d="M4 11l8-6.5 8 6.5M6 9.5V19h12V9.5"/>',
  list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20a2 2 0 0 0 4 0"/>',
  note: '<path d="M5 4h10l4 4v12H5zM14 4v5h5M8 13h8M8 16h6"/>',
  repeat: '<path d="M17 2l3 3-3 3M4 11V9a4 4 0 0 1 4-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 0 1-4 4H4"/>',
  chevron: '<path d="M6 9l6 6 6-6"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  more: '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
  sort: '<path d="M7 4v16M3 16l4 4 4-4M17 20V4M13 8l4-4 4 4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
  folder: '<path d="M3.5 6.5h6l2 2h9v10h-17z"/>',
  sidebar: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M9.5 4.5v15"/>',
  logout: '<path d="M10 5H5v14h5M14 8l4 4-4 4M18 12H9"/>',
  tick: '<path d="M6 12.5l4 4 8-9"/>',
};
const icon = (name, cls = '') => `<svg class="ic ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ''}</svg>`;

// ---------- Wiederholung (gleiches Format wie die App) ----------

const parseRule = (raw) => { try { const r = raw ? JSON.parse(raw) : null; return r ? { unit: r.unit, interval: r.interval || 1, weekdays: r.weekdays || [] } : null; } catch { return null; } };
const ruleRaw = (r) => (r ? JSON.stringify({ unit: r.unit, interval: r.interval, weekdays: r.weekdays }) : null);
const WD_SHORT = { 1: 'So', 2: 'Mo', 3: 'Di', 4: 'Mi', 5: 'Do', 6: 'Fr', 7: 'Sa' };
function ruleLabel(r) {
  const days = [2, 3, 4, 5, 6, 7, 1].filter((d) => r.weekdays.includes(d)).map((d) => tr(WD_SHORT[d]));
  if (r.interval === 1) {
    if (r.unit === 'day') return tr('Täglich');
    if (r.unit === 'month') return tr('Monatlich');
    if (r.unit === 'year') return tr('Jährlich');
    if ([...new Set(r.weekdays)].sort().join() === '2,3,4,5,6') return tr('Wochentage');
    if (r.weekdays.length <= 1) return tr('Wöchentlich');
    return tr('Wöchentlich: ') + days.join(', ');
  }
  const unit = { day: ['Tag', 'Tage'], week: ['Woche', 'Wochen'], month: ['Monat', 'Monate'], year: ['Jahr', 'Jahre'] }[r.unit][1];
  return tr('Alle %1 %2', r.interval, tr(unit)) + (r.unit === 'week' && days.length ? ': ' + days.join(', ') : '');
}
function perYear(r) {
  if (!r) return 0;
  const n = Math.max(r.interval, 1);
  return { day: 365 / n, week: (52 * Math.max(r.weekdays.length, 1)) / n, month: 12 / n, year: 1 / n }[r.unit] || 0;
}
const startOfWeek = (d) => { const s = startOfDay(d); return addDays(s, -((s.getDay() + 6) % 7)); };
function nextDate(r, date) {
  const base = startOfDay(date);
  const n = Math.max(r.interval, 1);
  if (r.unit === 'day') return addDays(base, n);
  if (r.unit === 'month') return addMonths(base, n);
  if (r.unit === 'year') return addMonths(base, 12 * n);
  const days = r.weekdays.length ? r.weekdays : [base.getDay() + 1];
  const sw = startOfWeek(base);
  for (let i = 1; i <= 7 * n + 7; i++) {
    const d = addDays(base, i);
    const weeks = Math.round((startOfWeek(d) - sw) / (7 * DAY));
    if (days.includes(d.getDay() + 1) && (weeks === 0 || weeks % n === 0)) return d;
  }
  return addDays(base, 7 * n);
}

// ---------- Schnelleingabe (wie QuickAddParser in der App) ----------

const WD = { sonntag: 1, montag: 2, dienstag: 3, mittwoch: 4, donnerstag: 5, freitag: 6, samstag: 7, so: 1, mo: 2, di: 3, mi: 4, do: 5, fr: 6, sa: 7,
  sunday: 1, monday: 2, tuesday: 3, wednesday: 4, thursday: 5, friday: 6, saturday: 7, sun: 1, mon: 2, tue: 3, wed: 4, thu: 5, fri: 6, sat: 7 };
const LONG = 'montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|monday|tuesday|wednesday|thursday|friday|saturday|sunday';
const SHORT = 'mon|tue|wed|thu|fri|sat|sun|mo|di|mi|do|fr|sa|so';
function parseQuick(input, now = new Date()) {
  const t0 = startOfDay(now);
  let w = ' ' + input + ' ';
  const res = { title: input, due: null, reminder: null, rule: null, important: false };
  let time = null;
  const take = (pat, fn) => {
    const m = w.match(new RegExp(pat, 'i'));
    if (m && fn(m)) w = w.slice(0, m.index) + ' ' + w.slice(m.index + m[0].length);
  };
  const nextWd = (wd, incl = true) => { let d = (wd - (t0.getDay() + 1) + 7) % 7; if (d === 0 && !incl) d = 7; return addDays(t0, d); };

  take('\\s(jeden tag|täglich|every day|daily)(?=\\s)', () => { res.rule = { unit: 'day', interval: 1, weekdays: [] }; return true; });
  if (!res.rule) take('\\s(werktags|wochentags|an werktagen|every weekday|on weekdays|weekdays)(?=\\s)', () => { res.rule = { unit: 'week', interval: 1, weekdays: [2, 3, 4, 5, 6] }; return true; });
  if (!res.rule) take(`\\s(?:jede[nrs]?|every)\\s(zweiten\\s|2\\.\\s|other\\s|2nd\\s)?(${LONG}|${SHORT})(?=\\s)`, (m) => {
    const wd = WD[m[2].toLowerCase()]; if (!wd) return false;
    res.rule = { unit: 'week', interval: m[1] ? 2 : 1, weekdays: [wd] }; res.due = res.due || nextWd(wd); return true;
  });
  if (!res.rule) take('\\s(?:alle|every)\\s(\\d{1,2})\\s(tage|wochen|monate|jahre|days|weeks|months|years)(?=\\s)', (m) => {
    const n = +m[1]; if (!n) return false;
    res.rule = { unit: { tage: 'day', wochen: 'week', monate: 'month', jahre: 'year', days: 'day', weeks: 'week', months: 'month', years: 'year' }[m[2].toLowerCase()], interval: n, weekdays: [] }; return true;
  });
  if (!res.rule) take('\\s(wöchentlich|jede woche|weekly|every week)(?=\\s)', () => { res.rule = { unit: 'week', interval: 1, weekdays: [] }; return true; });
  if (!res.rule) take('\\s(monatlich|jeden monat|monthly|every month)(?=\\s)', () => { res.rule = { unit: 'month', interval: 1, weekdays: [] }; return true; });
  if (!res.rule) take('\\s(jährlich|jedes jahr|yearly|annually|every year)(?=\\s)', () => { res.rule = { unit: 'year', interval: 1, weekdays: [] }; return true; });

  if (!res.due) take('\\s(übermorgen|the day after tomorrow|day after tomorrow)(?=\\s)', () => { res.due = addDays(t0, 2); return true; });
  if (!res.due) take('\\s(morgen|tomorrow)(?=\\s)', () => { res.due = addDays(t0, 1); return true; });
  if (!res.due) take('\\s(heute|today)(?=\\s)', () => { res.due = t0; return true; });
  if (!res.due) take('\\s(nächste woche|next week)(?=\\s)', () => { res.due = nextWd(2, false); return true; });
  if (!res.due) take('\\sin\\s(\\d{1,3})\\s(tag|tagen|woche|wochen|day|days|week|weeks)(?=\\s)', (m) => { res.due = addDays(t0, m[2].toLowerCase().startsWith('w') ? +m[1] * 7 : +m[1]); return true; });
  if (!res.due) take('\\s(?:am\\s|bis\\s)?(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2,4})?(?=\\s)', (m) => {
    const d = +m[1], mo = +m[2]; if (d < 1 || d > 31 || mo < 1 || mo > 12) return false;
    let y = t0.getFullYear(); if (m[3]) y = +m[3] < 100 ? 2000 + +m[3] : +m[3];
    let date = new Date(y, mo - 1, d); if (!m[3] && date < t0) date = new Date(y + 1, mo - 1, d);
    res.due = date; return true;
  });
  if (!res.due) take(`\\s(?:am\\s|bis\\s|on\\s|by\\s)?(${LONG})(?=\\s)`, (m) => { res.due = nextWd(WD[m[1].toLowerCase()]); return true; });
  if (!res.due) take(`\\s(?:am|bis|on|by)\\s(${SHORT})\\.?(?=\\s)`, (m) => { res.due = nextWd(WD[m[1].toLowerCase()]); return true; });

  take('\\s(?:at\\s)?(\\d{1,2})(?::(\\d{2}))?\\s?(am|pm)(?=\\s)', (m) => {
    let h = +m[1]; if (h < 1 || h > 12) return false;
    const pm = m[3].toLowerCase() === 'pm'; h = h === 12 ? (pm ? 12 : 0) : (pm ? h + 12 : h);
    time = [h, +(m[2] || 0)]; return true;
  });
  if (!time) take('\\sat\\s(\\d{1,2})(?::(\\d{2}))?(?=\\s)', (m) => { if (+m[1] > 23) return false; time = [+m[1], +(m[2] || 0)]; return true; });
  if (!time) take('\\s(?:um\\s|ab\\s|gegen\\s)?(\\d{1,2})(?::(\\d{2}))?\\s?uhr(?=\\s)', (m) => { if (+m[1] > 23) return false; time = [+m[1], +(m[2] || 0)]; return true; });
  if (!time) take('\\s(?:um\\s)?(\\d{1,2}):(\\d{2})(?=\\s)', (m) => { if (+m[1] > 23 || +m[2] > 59) return false; time = [+m[1], +m[2]]; return true; });
  if (!time) take('\\s(morgens|früh|in the morning|morning)(?=\\s)', () => { time = [9, 0]; return true; });
  if (!time) take('\\s(mittags|at noon|noon)(?=\\s)', () => { time = [12, 0]; return true; });
  if (!time) take('\\s(abends|in the evening|evening|tonight)(?=\\s)', () => { time = [19, 0]; return true; });

  take('\\s(!+|wichtig|important)(?=\\s)', () => { res.important = true; return true; });

  if (time) {
    let day = res.due || t0;
    let at = new Date(day); at.setHours(time[0], time[1], 0, 0);
    if (!res.due && at <= now) { day = addDays(t0, 1); at = new Date(day); at.setHours(time[0], time[1], 0, 0); }
    res.reminder = at; res.due = res.due || startOfDay(day);
  }
  if (res.rule && !res.due) res.due = res.rule.unit === 'week' && res.rule.weekdays.length ? nextWd(res.rule.weekdays[0]) : t0;
  if (res.rule && res.rule.unit === 'week' && !res.rule.weekdays.length && res.due) res.rule.weekdays = [res.due.getDay() + 1];
  // Feste Wochentage: Fälligkeit auf den nächsten passenden Tag legen (z. B. werktags am Samstag -> Montag)
  if (res.rule && res.rule.unit === 'week' && res.due) {
    let shift = 0;
    while (shift < 7 && !res.rule.weekdays.includes(addDays(res.due, shift).getDay() + 1)) shift++;
    if (shift) { res.due = addDays(res.due, shift); if (res.reminder) res.reminder = addDays(res.reminder, shift); }
  }
  const cleaned = w.split(/\s+/).filter(Boolean).join(' ').replace(/^[\s,;\-–]+|[\s,;\-–]+$/g, '');
  res.title = cleaned || input.trim();
  return res;
}

// ---------- Zustand ----------

const S = {
  user: null,
  loading: true,
  groups: new Map(), lists: new Map(), tasks: new Map(), steps: new Map(),
  route: store.get('route', { type: 'smart', id: 'myDay' }),
  pane: 'home',
  selected: null,
  collapsed: new Set(store.get('collapsed', [])),
  sortMyDay: store.get('sortMyDay', 'rhythm'),
  hideDone: store.get('hideDone', {}),
  menu: null,
  renaming: null,
  search: '',
  authMsg: '',
  loginEmail: '',
  toast: '',
};
const root = document.getElementById('root');

const sortedLists = () => [...S.lists.values()].sort((a, b) => (a.is_default ? -1 : a.sort) - (b.is_default ? -1 : b.sort));
const defaultList = () => [...S.lists.values()].find((l) => l.is_default);
const isInMyDay = (t) => isToday(t.my_day_date) || isToday(t.due);
const stepsOf = (taskId) => [...S.steps.values()].filter((s) => s.task_id === taskId).sort((a, b) => a.sort - b.sort);
const visibleTasks = () => [...S.tasks.values()].filter((t) => S.lists.has(t.list_id));
const byImportance = (a, b) => (a.is_important === b.is_important ? a.sort - b.sort : a.is_important ? -1 : 1);
const listPos = (t) => { const l = S.lists.get(t.list_id); return l ? (l.is_default ? -1 : l.sort) : 1e12; };

function routeTheme() {
  if (S.route.type === 'list') return theme(S.lists.get(S.route.id)?.theme);
  if (S.route.type === 'search') return theme('graphite');
  return theme(SMART[S.route.id]?.theme);
}
function routeTitle() {
  if (S.route.type === 'list') return S.lists.get(S.route.id)?.name || 'Liste';
  if (S.route.type === 'search') return 'Suche';
  return tr(SMART[S.route.id]?.title || '');
}
function scoped() {
  const all = visibleTasks();
  if (S.route.type === 'list') return all.filter((t) => t.list_id === S.route.id);
  if (S.route.type === 'search') {
    const q = S.search.trim().toLowerCase();
    return q ? all.filter((t) => t.title.toLowerCase().includes(q) || (t.note || '').toLowerCase().includes(q)) : [];
  }
  switch (S.route.id) {
    case 'myDay': return all.filter(isInMyDay);
    case 'important': return all.filter((t) => t.is_important && !t.is_completed);
    case 'planned': return all.filter((t) => (t.due || t.reminder) && !t.is_completed);
    case 'all': return all.filter((t) => !t.is_completed);
    case 'completed': return all.filter((t) => t.is_completed);
    case 'tasks': return all.filter((t) => S.lists.get(t.list_id)?.is_default);
    default: return [];
  }
}
function smartCount(id) {
  const all = visibleTasks().filter((t) => !t.is_completed);
  switch (id) {
    case 'myDay': return all.filter(isInMyDay).length;
    case 'important': return all.filter((t) => t.is_important).length;
    case 'planned': return all.filter((t) => t.due || t.reminder).length;
    case 'all': return all.length;
    case 'tasks': return all.filter((t) => S.lists.get(t.list_id)?.is_default).length;
    default: return 0;
  }
}

// ---------- Speichern ----------

function payload(table, row) {
  const out = {};
  for (const c of COLS[table]) if (c in row) out[c] = row[c];
  return out;
}
async function put(table, row) {
  S[table].set(row.id, row);
  render();
  const { error } = await sb.from(table).upsert(payload(table, { deleted: false, ...row }));
  if (error) showToast(tr('Speichern fehlgeschlagen: ') + error.message);
}
async function patch(table, id, changes) {
  const row = S[table].get(id);
  if (row) await put(table, { ...row, ...changes });
}
async function removeRow(table, id) {
  S[table].delete(id);
  render();
  const { error } = await sb.from(table).upsert({ id, deleted: true });
  if (error) showToast(tr('Löschen fehlgeschlagen: ') + error.message);
}
function showToast(text) {
  S.toast = text; render();
  clearTimeout(showToast.t); showToast.t = setTimeout(() => { S.toast = ''; render(); }, 4000);
}

async function addTask(input) {
  const p = parseQuick(input);
  if (!p.title) return;
  let list = S.route.type === 'list' ? S.lists.get(S.route.id) : defaultList();
  if (!list) {
    list = { id: uuid(), name: tr('Aufgaben'), theme: 'indigo', sort: -1, is_default: true, group_id: null, created_at: iso(new Date()) };
    await put('lists', list);
  }
  const orders = visibleTasks().filter((t) => t.list_id === list.id).map((t) => t.sort);
  const now = new Date();
  const smart = S.route.type === 'smart' ? S.route.id : null;
  let due = p.due;
  if (!due && smart === 'planned') due = today();
  if (!due && p.rule) due = today();
  const task = {
    id: uuid(), list_id: list.id, title: p.title, note: '', is_completed: false, completed_at: null,
    is_important: p.important || smart === 'important',
    my_day_date: smart === 'myDay' ? iso(today()) : null, my_day_added_at: smart === 'myDay' ? iso(now) : null,
    due: iso(due), reminder: iso(p.reminder), repeat_raw: ruleRaw(p.rule), spawned_next: false,
    created_at: iso(now), sort: (orders.length ? Math.min(...orders) : 0) - 1,
  };
  await put('tasks', task);
}

async function toggleComplete(id) {
  const t = S.tasks.get(id);
  if (!t) return;
  if (t.is_completed) return patch('tasks', id, { is_completed: false, completed_at: null });
  const rule = parseRule(t.repeat_raw);
  const changes = { is_completed: true, completed_at: iso(new Date()) };
  if (rule && !t.spawned_next && t.list_id) {
    changes.spawned_next = true;
    const base = t.due ? new Date(t.due) : today();
    const next = nextDate(rule, base);
    const reminder = t.reminder ? new Date(new Date(t.reminder).getTime() + (next - startOfDay(base))) : null;
    const nt = {
      id: uuid(), list_id: t.list_id, title: t.title, note: t.note, is_completed: false, completed_at: null,
      is_important: t.is_important, my_day_date: null, my_day_added_at: null, due: iso(next), reminder: iso(reminder),
      repeat_raw: t.repeat_raw, spawned_next: false, created_at: iso(new Date()), sort: t.sort,
    };
    await patch('tasks', id, changes);
    await put('tasks', nt);
    for (const s of stepsOf(id)) await put('steps', { id: uuid(), task_id: nt.id, title: s.title, is_completed: false, sort: s.sort });
    return;
  }
  return patch('tasks', id, changes);
}

async function deleteTask(id) {
  for (const s of stepsOf(id)) removeRow('steps', s.id);
  if (S.selected === id) S.selected = null;
  await removeRow('tasks', id);
}

async function deleteList(id) {
  for (const t of visibleTasks().filter((x) => x.list_id === id)) await deleteTask(t.id);
  await removeRow('lists', id);
  go({ type: 'smart', id: 'myDay' });
}

function go(route) {
  S.route = route; S.selected = null; S.menu = null; S.renaming = null; S.pane = 'list';
  if (route.type !== 'search') store.set('route', route);
  render();
}

// ---------- Darstellung ----------

function taskMeta(t, ctx) {
  const parts = [];
  if (ctx.showMyDay && isToday(t.my_day_date)) parts.push(`<span>${icon('sun')} ${tr('Mein Tag')}</span>`);
  if (ctx.showList) parts.push(`<span>${esc(splitEmoji(S.lists.get(t.list_id)?.name).rest)}</span>`);
  const steps = stepsOf(t.id);
  if (steps.length) parts.push(`<span>${tr('%1 von %2', steps.filter((s) => s.is_completed).length, steps.length)}</span>`);
  if (t.due) {
    const o = offset(t.due);
    const cls = !t.is_completed && o < 0 ? 'overdue' : o === 0 ? 'today' : '';
    parts.push(`<span class="${cls}">${icon('calendar')} ${o < 0 && !t.is_completed ? tr('Überfällig, ') : ''}${dayLabel(t.due)}${t.repeat_raw ? ' ' + icon('repeat') : ''}</span>`);
  }
  if (t.reminder) parts.push(`<span>${icon('bell')} ${dayLabel(t.reminder)}, ${fmtTime.format(new Date(t.reminder))}</span>`);
  if ((t.note || '').trim()) parts.push(`<span>${icon('note')} ${tr('Notiz')}</span>`);
  return parts.join('<i>•</i>');
}

function taskRow(t, ctx) {
  const meta = taskMeta(t, ctx);
  return `<div class="task ${t.is_completed ? 'done' : ''} ${S.selected === t.id ? 'sel' : ''}" data-act="open-task" data-id="${t.id}">
    <button class="check" data-act="toggle-done" data-id="${t.id}" aria-label="${t.is_completed ? tr('Als nicht erledigt markieren') : tr('Erledigen')}">${icon('tick')}</button>
    <div class="body"><div class="title">${esc(t.title)}</div>${meta ? `<div class="meta">${meta}</div>` : ''}</div>
    <button class="star ${t.is_important ? 'on' : ''}" data-act="toggle-star" data-id="${t.id}" aria-label="${tr('Wichtig')}">${icon('star')}</button>
  </div>`;
}

function section(key, title, items, ctx, opts = {}) {
  const closed = S.collapsed.has(key);
  return `<button class="section ${opts.alert ? 'alert' : ''}" data-act="toggle-section" data-key="${esc(key)}">
      ${icon('chevron', closed ? 'rot' : '')}<span>${esc(title)}</span><b>${items.length}</b></button>
    ${closed ? '' : items.map((t) => taskRow(t, ctx)).join('')}`;
}

function groupsByRhythm(open) {
  const map = new Map();
  for (const t of open) {
    const r = parseRule(t.repeat_raw);
    const label = r ? ruleLabel(r) : tr('Einmalig');
    if (!map.has(label)) map.set(label, { label, rank: 0, items: [] });
    const g = map.get(label); g.items.push(t); g.rank = Math.max(g.rank, perYear(r));
  }
  return [...map.values()].sort((a, b) => (b.rank - a.rank) || a.label.localeCompare(b.label))
    .map((g) => ({ key: 'r' + g.label, title: g.label, items: g.items.sort(byImportance) }));
}
function groupsByList(items, sortFn = byImportance) {
  return sortedLists().map((l) => ({ key: 'l' + l.id, title: l.name, items: items.filter((t) => t.list_id === l.id).sort(sortFn) }))
    .filter((g) => g.items.length);
}

function listContent() {
  const items = scoped();
  const smart = S.route.type === 'smart' ? S.route.id : null;
  const ctx = { showList: S.route.type !== 'list' && smart !== 'tasks', showMyDay: smart !== 'myDay' };
  const key = S.route.type === 'list' ? S.route.id : S.route.id || 'search';
  const doneSorted = (a, b) => (b.completed_at || '').localeCompare(a.completed_at || '');

  if (smart === 'planned') {
    const buckets = new Map();
    for (const t of items) {
      const d = startOfDay(t.due || t.reminder).getTime();
      if (!buckets.has(d)) buckets.set(d, []);
      buckets.get(d).push(t);
    }
    const out = [...buckets.keys()].sort((a, b) => a - b)
      .map((d) => section('d' + d, dayLabel(new Date(d)), buckets.get(d).sort(byImportance), ctx, { alert: offset(new Date(d)) < 0 })).join('');
    return out || empty();
  }
  if (smart === 'all' || smart === 'completed') {
    const groups = groupsByList(items, smart === 'completed' ? doneSorted : byImportance);
    return groups.map((g) => section(g.key, g.title, g.items, ctx)).join('') || empty();
  }
  const open = items.filter((t) => !t.is_completed);
  const done = items.filter((t) => t.is_completed).sort(doneSorted);
  let html = '';
  if (smart === 'myDay' && S.sortMyDay !== 'manual') {
    const groups = S.sortMyDay === 'list' ? groupsByList(open) : groupsByRhythm(open);
    html += groups.map((g) => section(g.key, g.title, g.items, ctx)).join('');
  } else {
    const flat = [...open].sort((a, b) => a.sort - b.sort);
    const sorted = [...flat.filter((t) => t.is_important), ...flat.filter((t) => !t.is_important)];
    html += sorted.map((t) => taskRow(t, ctx)).join('');
  }
  if (done.length && !S.hideDone[key]) html += section('done', tr('Erledigt'), done, ctx);
  return html || empty();
}

function empty() {
  const texts = {
    myDay: ['Konzentriere dich auf deinen Tag', 'Erledige Aufgaben mit „Mein Tag“, einer Liste, die jeden Tag neu beginnt.'],
    important: ['Nichts als wichtig markiert', 'Markiere Aufgaben mit dem Stern, damit sie hier erscheinen.'],
    planned: ['Nichts geplant', 'Aufgaben mit Fälligkeitsdatum oder Erinnerung erscheinen hier.'],
    all: ['Keine offenen Aufgaben', 'Alle offenen Aufgaben aus allen Listen erscheinen hier.'],
    completed: ['Noch nichts erledigt', 'Erledigte Aufgaben aus allen Listen erscheinen hier.'],
  };
  const t = S.route.type === 'search' ? ['Keine Treffer', 'Suche nach Titel oder Notiz.'] : texts[S.route.id];
  return t ? `<div class="empty">${icon(S.route.type === 'smart' ? SMART[S.route.id].icon : 'search')}<h3>${tr(t[0])}</h3><p>${tr(t[1])}</p></div>` : '';
}

function sidebar() {
  const name = store.get('name', '') || (S.user?.email || '').split('@')[0];
  const initials = name.split(/[\s._-]+/).filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join('');
  const active = (type, id) => (S.route.type === type && S.route.id === id ? 'active' : '');
  const smartRow = (id) => {
    if (id === 'completed' && !smartCount('all') && !visibleTasks().some((t) => t.is_completed)) return '';
    const c = smartCount(id);
    return `<button class="nav ${active('smart', id)}" data-act="nav-smart" data-id="${id}">
      <span class="lead" style="color:${SMART[id].color}">${icon(SMART[id].icon)}</span><span class="name">${tr(SMART[id].title)}</span>${c ? `<span class="count">${c}</span>` : ''}</button>`;
  };
  const listRow = (l, indent = false) => {
    const { emoji, rest } = splitEmoji(l.name);
    const c = visibleTasks().filter((t) => t.list_id === l.id && !t.is_completed).length;
    return `<button class="nav ${indent ? 'indent' : ''} ${active('list', l.id)}" data-act="nav-list" data-id="${l.id}">
      <span class="lead" style="color:${theme(l.theme).accent}">${emoji ? `<span class="emoji">${emoji}</span>` : icon('list')}</span>
      <span class="name">${esc(rest || l.name)}</span>${c ? `<span class="count">${c}</span>` : ''}</button>`;
  };
  const loose = sortedLists().filter((l) => !l.is_default && !(l.group_id && S.groups.has(l.group_id)));
  const items = [...[...S.groups.values()].map((g) => ({ g, sort: g.sort })), ...loose.map((l) => ({ l, sort: l.sort }))].sort((a, b) => a.sort - b.sort);
  const groupBlock = (g) => {
    const members = sortedLists().filter((l) => l.group_id === g.id);
    const { emoji, rest } = splitEmoji(g.name);
    return `<div class="group">
      <button class="nav grouphead" data-act="toggle-group" data-id="${g.id}">
        <span class="lead">${emoji ? `<span class="emoji">${emoji}</span>` : icon('folder')}</span><span class="name"><b>${esc(rest || g.name)}</b></span>
        ${icon('chevron', g.is_expanded ? '' : 'rot')}</button>
      ${g.is_expanded ? `<div class="members">${members.map((l) => listRow(l, true)).join('')}</div>` : ''}</div>`;
  };
  return `<aside class="side">
    <div class="profile">
      <div class="avatar">${esc(initials || 'T')}</div>
      <div class="who"><b>${esc(name || 'Tagwerk')}</b><small>${esc(S.user?.email || '')}</small></div>
      <button class="lang-btn" data-act="lang" title="${tr('Sprache')}">${lang === 'de' ? 'EN' : 'DE'}</button>
      <button class="icon-btn" data-act="logout" title="${tr('Abmelden')}">${icon('logout')}</button>
    </div>
    <label class="searchbox">${icon('search')}<input id="search" type="search" placeholder="${tr('Suchen')}" value="${esc(S.search)}" autocomplete="off"></label>
    <nav>
      ${['myDay', 'important', 'planned', 'all', 'completed', 'tasks'].map(smartRow).join('')}
      <div class="divider"></div>
      ${items.map((i) => (i.g ? groupBlock(i.g) : listRow(i.l))).join('')}
    </nav>
    <button class="newlist" data-act="new-list">${icon('plus')}<span>${tr('Neue Liste')}</span></button>
  </aside>`;
}

function header() {
  const smart = S.route.type === 'smart' ? S.route.id : null;
  const list = S.route.type === 'list' ? S.lists.get(S.route.id) : null;
  const key = list ? list.id : S.route.id || 'search';
  const title = S.renaming && list
    ? `<input id="rename" class="title-input" value="${esc(list.name)}" data-id="${list.id}">`
    : `<h1>${esc(routeTitle())}</h1>`;
  const sortChip = smart === 'myDay' && S.sortMyDay !== 'manual'
    ? `<button class="chip" data-act="sort-clear">${tr('Nach %1', tr(S.sortMyDay === 'list' ? 'Liste' : 'Rhythmus'))} ${icon('close')}</button>` : '';
  const menuItems = `
      ${smart === 'myDay' ? `<div class="menu-label">${tr('Sortieren')}</div>
        ${[['rhythm', 'Rhythmus'], ['list', 'Liste'], ['manual', 'Eigene Reihenfolge']].map(([k, l]) => `<button data-act="sort" data-key="${k}">${S.sortMyDay === k ? icon('tick') : '<span class="ic"></span>'}${tr(l)}</button>`).join('')}
        <div class="menu-sep"></div>` : ''}
      ${list ? `<button data-act="rename-list">${tr('Liste umbenennen')}</button>
        <div class="menu-label">${tr('Design')}</div>
        <div class="swatches">${Object.keys(THEMES).map((k) => `<button class="swatch ${list.theme === k ? 'on' : ''}" style="background:${theme(k).gradient}" data-act="set-theme" data-key="${k}" title="${tr(THEMES[k].name)}"></button>`).join('')}</div>
        <div class="menu-sep"></div>` : ''}
      ${smart !== 'completed' && smart !== 'planned' && smart !== 'all' ? `<button data-act="toggle-hide-done">${S.hideDone[key] ? tr('Erledigte anzeigen') : tr('Erledigte ausblenden')}</button>` : ''}
      ${list && !list.is_default ? `<button class="danger" data-act="delete-list">${tr('Liste löschen')}</button>` : ''}
    `.trim();
  const menu = S.menu === 'list' && menuItems ? `<div class="menu" data-stop>${menuItems}</div>` : '';
  return `<header class="head">
    <div class="topbar">
      <button class="back" data-act="back">${icon('back')}<span>${tr('Listen')}</span></button>
      <span class="spacer"></span>
      ${menuItems ? `<div class="menu-wrap"><button class="icon-btn light" data-act="menu" aria-label="${tr('Optionen')}">${icon('more')}</button>${menu}</div>` : ''}
    </div>
    ${title}
    ${smart === 'myDay' ? `<p class="sub">${fmtLong.format(new Date())}</p>` : ''}
    ${sortChip ? `<div class="chips">${sortChip}</div>` : ''}
  </header>`;
}

function addBar() {
  if (S.route.type === 'smart' && S.route.id === 'completed') return '';
  if (S.route.type === 'search') return '';
  return `<div class="addbar">
    <label class="addfield">${icon('plus')}<input id="quick" placeholder="${tr('Aufgabe hinzufügen')}" autocomplete="off" enterkeyhint="done"></label>
    <div id="quick-preview" class="preview"></div>
  </div>`;
}

function quickPreview(text) {
  if (!text.trim()) return '';
  const p = parseQuick(text);
  const chips = [];
  if (p.due) chips.push(`${icon('calendar')} ${dayLabel(p.due)}`);
  if (p.reminder) chips.push(`${icon('bell')} ${fmtTime.format(p.reminder)}`);
  if (p.rule) chips.push(`${icon('repeat')} ${ruleLabel(p.rule)}`);
  if (p.important) chips.push(`${icon('star')} Wichtig`);
  if (!chips.length) return '';
  return `<span class="ptitle">„${esc(p.title)}“</span>${chips.map((c) => `<span class="pchip">${c}</span>`).join('')}`;
}

function detail() {
  const t = S.tasks.get(S.selected);
  if (!t) return '';
  const steps = stepsOf(t.id);
  const rule = parseRule(t.repeat_raw);
  const presets = [['', 'Nicht wiederholen'], ['day', 'Täglich'], ['workdays', 'Wochentage'], ['week', 'Wöchentlich'], ['month', 'Monatlich'], ['year', 'Jährlich']].map(([k, l]) => [k, tr(l)]);
  const ruleKey = !rule ? '' : rule.interval !== 1 ? 'custom' : rule.unit === 'week' ? ([...rule.weekdays].sort().join() === '2,3,4,5,6' ? 'workdays' : rule.weekdays.length <= 1 ? 'week' : 'custom') : rule.unit;
  if (ruleKey === 'custom') presets.push(['custom', ruleLabel(rule)]);
  const accent = routeTheme().accent;
  return `<aside class="detail" style="--accent:${accent}">
    <div class="detail-top"><button class="icon-btn" data-act="close-detail" aria-label="${tr('Schließen')}">${icon('close')}</button></div>
    <div class="dscroll">
      <div class="card">
        <div class="drow titlerow">
          <button class="check ${t.is_completed ? 'on' : ''}" data-act="toggle-done" data-id="${t.id}">${icon('tick')}</button>
          <textarea id="d-title" rows="1" class="dtitle ${t.is_completed ? 'done' : ''}">${esc(t.title)}</textarea>
          <button class="star ${t.is_important ? 'on' : ''}" data-act="toggle-star" data-id="${t.id}">${icon('star')}</button>
        </div>
        ${steps.map((s) => `<div class="drow step">
          <button class="check small ${s.is_completed ? 'on' : ''}" data-act="toggle-step" data-id="${s.id}">${icon('tick')}</button>
          <span class="${s.is_completed ? 'done' : ''}">${esc(s.title)}</span>
          <button class="icon-btn tiny" data-act="delete-step" data-id="${s.id}" aria-label="${tr('Schritt löschen')}">${icon('close')}</button></div>`).join('')}
        <label class="drow addstep">${icon('plus')}<input id="d-step" placeholder="${steps.length ? tr('Nächster Schritt') : tr('Schritt hinzufügen')}" autocomplete="off"></label>
      </div>
      <div class="card">
        <button class="drow action ${isToday(t.my_day_date) ? 'on' : ''}" data-act="toggle-myday">${icon('sun')}<span>${isToday(t.my_day_date) ? tr('Zu „Mein Tag“ hinzugefügt') : tr('Zu „Mein Tag“ hinzufügen')}</span></button>
      </div>
      <div class="card">
        <label class="drow field ${t.reminder ? 'on' : ''}">${icon('bell')}<span>${tr('Erinnerung')}</span><input id="d-reminder" type="datetime-local" value="${dateTimeInput(t.reminder)}"></label>
        <label class="drow field ${t.due ? 'on' : ''}">${icon('calendar')}<span>${tr('Fällig')}</span><input id="d-due" type="date" value="${dateInput(t.due)}"></label>
        <label class="drow field ${rule ? 'on' : ''}">${icon('repeat')}<span>${tr('Wiederholen')}</span>
          <select id="d-repeat">${presets.map(([k, l]) => `<option value="${k}" ${k === ruleKey ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
      </div>
      <div class="card">
        <label class="drow field">${icon('list')}<span>${tr('Liste')}</span>
          <select id="d-list">${sortedLists().map((l) => `<option value="${l.id}" ${l.id === t.list_id ? 'selected' : ''}>${esc(l.name)}</option>`).join('')}</select></label>
      </div>
      <div class="card"><textarea id="d-note" class="note" placeholder="${tr('Notiz hinzufügen')}">${esc(t.note)}</textarea></div>
    </div>
    <div class="detail-foot">
      <span>${t.created_at ? tr('Erstellt %1', dayLabel(t.created_at)) : ''}</span>
      <button class="icon-btn" data-act="delete-task" data-id="${t.id}" aria-label="${tr('Aufgabe löschen')}">${icon('trash')}</button>
    </div>
  </aside>`;
}

function loginView() {
  return `<div class="login" style="background:${theme('dawn').gradient}">
    <form class="login-card" id="login">
      <img src="icon.png" alt="" width="64" height="64">
      <h1>Tagwerk</h1>
      <p>${tr('Melde dich mit demselben Konto an wie in der iPhone-App.')}</p>
      <input id="l-email" type="email" placeholder="${tr('E-Mail')}" autocomplete="username" value="${esc(S.loginEmail || '')}">
      <input id="l-pass" type="password" placeholder="${tr('Passwort (mindestens 6 Zeichen)')}" autocomplete="current-password">
      <button type="submit" class="primary">${tr('Anmelden')}</button>
      <button type="button" class="secondary" data-act="signup">${tr('Konto erstellen')}</button>
      <button type="button" class="lang-link" data-act="lang">${lang === 'de' ? 'English' : 'Deutsch'}</button>
      ${S.authMsg ? `<p class="msg">${esc(S.authMsg)}</p>` : ''}
    </form>
  </div>`;
}

function view() {
  if (S.loading) return '<div class="boot">Tagwerk</div>';
  if (!S.user) return loginView();
  const th = routeTheme();
  return `<div class="app pane-${S.pane} ${S.selected ? 'has-detail' : ''}">
    ${sidebar()}
    <main class="main" style="background:${th.gradient};--accent:${th.accent}">
      ${header()}
      <div class="scroll">${listContent()}</div>
      ${addBar()}
    </main>
    ${detail()}
    ${S.toast ? `<div class="toast">${esc(S.toast)}</div>` : ''}
  </div>`;
}

let frame = 0;
function render() {
  cancelAnimationFrame(frame);
  frame = requestAnimationFrame(paint);
}
function paint() {
  const a = document.activeElement;
  const keep = a && a.id && /INPUT|TEXTAREA|SELECT/.test(a.tagName) ? { id: a.id, value: a.value, s: a.selectionStart, e: a.selectionEnd } : null;
  const scroll = root.querySelector('.scroll')?.scrollTop || 0;
  const dscroll = root.querySelector('.dscroll')?.scrollTop || 0;
  root.innerHTML = view();
  const sc = root.querySelector('.scroll'); if (sc) sc.scrollTop = scroll;
  const dsc = root.querySelector('.dscroll'); if (dsc) dsc.scrollTop = dscroll;
  if (keep) {
    const el = document.getElementById(keep.id);
    if (el) {
      el.value = keep.value; el.focus();
      try { el.setSelectionRange(keep.s, keep.e); } catch { /* nicht jedes Feld kann das */ }
      if (keep.id === 'quick') document.getElementById('quick-preview').innerHTML = quickPreview(keep.value);
    }
  }
  const dt = document.getElementById('d-title');
  if (dt) { dt.style.height = 'auto'; dt.style.height = dt.scrollHeight + 'px'; }
}

// ---------- Ereignisse ----------

root.addEventListener('click', async (e) => {
  const el = e.target.closest('[data-act]');
  if (!el) {
    if (S.menu && !e.target.closest('[data-stop]')) { S.menu = null; render(); }
    return;
  }
  e.stopPropagation();
  const id = el.dataset.id;
  const act = el.dataset.act;
  if (act !== 'menu' && !el.closest('[data-stop]')) S.menu = null;
  switch (act) {
    case 'nav-smart': return go({ type: 'smart', id });
    case 'nav-list': return go({ type: 'list', id });
    case 'back': S.pane = 'home'; S.selected = null; return render();
    case 'open-task': S.selected = id; return render();
    case 'close-detail': S.selected = null; return render();
    case 'toggle-done': return toggleComplete(id);
    case 'toggle-star': { const t = S.tasks.get(id); return patch('tasks', id, { is_important: !t.is_important }); }
    case 'toggle-section': {
      const k = el.dataset.key; S.collapsed.has(k) ? S.collapsed.delete(k) : S.collapsed.add(k);
      store.set('collapsed', [...S.collapsed]); return render();
    }
    case 'toggle-group': { const g = S.groups.get(id); return patch('groups', id, { is_expanded: !g.is_expanded }); }
    case 'menu': S.menu = S.menu ? null : 'list'; return render();
    case 'sort': S.sortMyDay = el.dataset.key; store.set('sortMyDay', S.sortMyDay); S.menu = null; return render();
    case 'sort-clear': S.sortMyDay = 'manual'; store.set('sortMyDay', 'manual'); return render();
    case 'toggle-hide-done': {
      const key = S.route.type === 'list' ? S.route.id : S.route.id;
      S.hideDone[key] = !S.hideDone[key]; store.set('hideDone', S.hideDone); S.menu = null; return render();
    }
    case 'rename-list': S.renaming = S.route.id; S.menu = null; render(); setTimeout(() => document.getElementById('rename')?.select(), 30); return;
    case 'set-theme': return patch('lists', S.route.id, { theme: el.dataset.key });
    case 'delete-list': {
      const l = S.lists.get(S.route.id);
      if (l && confirm(tr('„%1“ wird endgültig gelöscht.', l.name))) await deleteList(l.id);
      return;
    }
    case 'new-list': {
      const sorts = [...S.lists.values(), ...S.groups.values()].map((x) => x.sort);
      const l = { id: uuid(), name: tr('Unbenannte Liste'), theme: 'blue', sort: (sorts.length ? Math.max(...sorts) : 0) + 1, is_default: false, group_id: null, created_at: iso(new Date()) };
      await put('lists', l);
      go({ type: 'list', id: l.id });
      S.renaming = l.id; render(); setTimeout(() => document.getElementById('rename')?.select(), 30);
      return;
    }
    case 'toggle-myday': {
      const t = S.tasks.get(S.selected); const on = isToday(t.my_day_date);
      return patch('tasks', t.id, { my_day_date: on ? null : iso(today()), my_day_added_at: on ? null : iso(new Date()) });
    }
    case 'toggle-step': { const s = S.steps.get(id); return patch('steps', id, { is_completed: !s.is_completed }); }
    case 'delete-step': return removeRow('steps', id);
    case 'delete-task': {
      const t = S.tasks.get(id);
      if (t && confirm(tr('„%1“ wird endgültig gelöscht.', t.title))) await deleteTask(id);
      return;
    }
    case 'logout': await sb.auth.signOut(); return;
    case 'signup': return authenticate('up');
    case 'lang': lang = lang === 'de' ? 'en' : 'de'; store.set('lang', lang); document.documentElement.lang = lang; return render();
    default:
  }
});

root.addEventListener('input', (e) => {
  if (e.target.id === 'quick') document.getElementById('quick-preview').innerHTML = quickPreview(e.target.value);
  if (e.target.id === 'search') {
    S.search = e.target.value;
    if (S.search.trim()) { S.route = { type: 'search' }; S.pane = 'list'; S.selected = null; }
    else if (S.route.type === 'search') S.route = store.get('route', { type: 'smart', id: 'myDay' });
    render();
  }
  if (e.target.id === 'd-title') { e.target.style.height = 'auto'; e.target.style.height = e.target.scrollHeight + 'px'; }
});

root.addEventListener('keydown', async (e) => {
  if (e.key === 'Escape') {
    if (S.menu) { S.menu = null; return render(); }
    if (S.selected) { S.selected = null; return render(); }
  }
  if (e.key !== 'Enter' || e.isComposing) return;
  const el = e.target;
  if (el.id === 'quick' && el.value.trim()) {
    const value = el.value; el.value = ''; document.getElementById('quick-preview').innerHTML = '';
    await addTask(value);
  }
  if (el.id === 'd-step' && el.value.trim()) {
    const title = el.value.trim(); el.value = '';
    const steps = stepsOf(S.selected);
    await put('steps', { id: uuid(), task_id: S.selected, title, is_completed: false, sort: steps.length ? steps[steps.length - 1].sort + 1 : 0 });
  }
  if (el.id === 'd-title') { e.preventDefault(); el.blur(); }
  if (el.id === 'rename') el.blur();
});

root.addEventListener('change', async (e) => {
  const el = e.target;
  const t = S.tasks.get(S.selected);
  if (el.id === 'd-due' && t) {
    const [y, m, d] = el.value.split('-').map(Number);
    return patch('tasks', t.id, { due: el.value ? iso(new Date(y, m - 1, d)) : null });
  }
  if (el.id === 'd-reminder' && t) return patch('tasks', t.id, { reminder: el.value ? iso(new Date(el.value)) : null });
  if (el.id === 'd-list' && t) return patch('tasks', t.id, { list_id: el.value });
  if (el.id === 'd-repeat' && t) {
    if (el.value === 'custom') return;
    const base = t.due ? new Date(t.due) : today();
    const rules = {
      day: { unit: 'day', interval: 1, weekdays: [] },
      workdays: { unit: 'week', interval: 1, weekdays: [2, 3, 4, 5, 6] },
      week: { unit: 'week', interval: 1, weekdays: [base.getDay() + 1] },
      month: { unit: 'month', interval: 1, weekdays: [] },
      year: { unit: 'year', interval: 1, weekdays: [] },
    };
    const rule = rules[el.value] || null;
    return patch('tasks', t.id, { repeat_raw: ruleRaw(rule), due: rule && !t.due ? iso(today()) : t.due });
  }
});

root.addEventListener('focusout', async (e) => {
  const el = e.target;
  const t = S.tasks.get(S.selected);
  if (el.id === 'd-title' && t) {
    const v = el.value.replace(/\s+/g, ' ').trim();
    if (v && v !== t.title) await patch('tasks', t.id, { title: v });
  }
  if (el.id === 'd-note' && t && el.value !== (t.note || '')) await patch('tasks', t.id, { note: el.value });
  if (el.id === 'rename') {
    const l = S.lists.get(el.dataset.id);
    S.renaming = null;
    const v = el.value.trim();
    if (l && v && v !== l.name) await patch('lists', l.id, { name: v }); else render();
  }
});

root.addEventListener('submit', (e) => {
  if (e.target.id !== 'login') return;
  e.preventDefault();
  authenticate('in');
});

function authError(message) {
  if (/Invalid login/i.test(message)) return tr('E-Mail oder Passwort falsch. Noch kein Konto? Dann auf „Konto erstellen“.');
  if (/not confirmed/i.test(message)) return tr('Bitte bestätige zuerst deine E-Mail über den Link in der Mail.');
  if (/already registered/i.test(message)) return tr('Diese E-Mail ist schon registriert. Bitte anmelden.');
  if (/at least/i.test(message)) return tr('Das Passwort ist zu kurz (mindestens 6 Zeichen).');
  return tr('Fehler: ') + message;
}

async function authenticate(mode) {
  const email = document.getElementById('l-email').value.trim();
  const password = document.getElementById('l-pass').value;
  S.loginEmail = email;
  if (!email || !password) { S.authMsg = tr('Bitte E-Mail und Passwort eingeben.'); return render(); }
  S.authMsg = mode === 'in' ? tr('Melde an …') : tr('Erstelle Konto …'); render();
  const { data, error } = mode === 'in'
    ? await sb.auth.signInWithPassword({ email, password })
    : await sb.auth.signUp({ email, password, options: { emailRedirectTo: location.origin + location.pathname } });
  if (error) S.authMsg = authError(error.message);
  else if (mode === 'up' && !data.session) S.authMsg = tr('Konto angelegt. Bitte bestätige die Mail an %1 und melde dich dann an.', email);
  else S.authMsg = '';
  render();
}

// ---------- Laden und Live-Abgleich ----------

async function loadAll() {
  for (const table of TABLES) {
    const rows = [];
    for (let from = 0; ; from += 1000) {
      const { data, error } = await sb.from(table).select('*').eq('deleted', false).range(from, from + 999);
      if (error) { showToast(tr('Laden fehlgeschlagen: ') + error.message); return; }
      rows.push(...data);
      if (data.length < 1000) break;
    }
    S[table] = new Map(rows.map((r) => [r.id, r]));
  }
  if (S.route.type === 'list' && !S.lists.has(S.route.id)) S.route = { type: 'smart', id: 'myDay' };
}

let channel = null;
function subscribe() {
  channel?.unsubscribe();
  channel = sb.channel('tagwerk');
  for (const table of TABLES) {
    channel.on('postgres_changes', { event: '*', schema: 'public', table }, (msg) => {
      const row = msg.new;
      if (!row || !row.id) return;
      if (row.deleted) S[table].delete(row.id); else S[table].set(row.id, row);
      render();
    });
  }
  channel.subscribe();
}

let loadedFor = null;
async function onSession(session) {
  S.user = session?.user || null;
  if (S.user && loadedFor !== S.user.id) {
    loadedFor = S.user.id;
    S.loading = true; render();
    await loadAll();
    subscribe();
    if (window.matchMedia('(min-width: 761px)').matches) S.pane = 'list';
  }
  if (!S.user) { loadedFor = null; channel?.unsubscribe(); TABLES.forEach((t) => S[t].clear()); }
  S.loading = false;
  render();
}

sb.auth.onAuthStateChange((_event, session) => { onSession(session); });
// Beim Zurückkehren in den Tab alles frisch laden (falls Live-Updates verpasst wurden)
document.addEventListener('visibilitychange', async () => {
  if (document.visibilityState === 'visible' && S.user) { await loadAll(); render(); }
});
// Um Mitternacht beginnt Mein Tag neu
setInterval(render, 60 * 1000);
