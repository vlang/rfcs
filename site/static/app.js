document.addEventListener('DOMContentLoaded', () => {
  const input = document.getElementById('rfc-search');
  const list = document.getElementById('rfc-list');
  const count = document.getElementById('rfc-count');
  const empty = document.getElementById('rfc-empty');
  const reset = document.getElementById('rfc-reset');
  const sortButtons = Array.from(document.querySelectorAll('.sort-btn'));

  const cards = list ? Array.from(list.querySelectorAll('.rfc-card')) : [];
  const total = cards.length;
  // Remember the server order so "RFC #" can always return to it.
  const original = cards.map((card, index) => ({ card, index }));

  function applyFilter() {
    if (!input || !list) return;
    const q = input.value.trim().toLowerCase();
    let visible = 0;
    for (const card of cards) {
      const show = q === '' || (card.dataset.search || '').toLowerCase().includes(q);
      card.hidden = !show;
      if (show) visible++;
    }
    if (count) {
      count.textContent = q === ''
        ? total + ' proposals'
        : visible + ' of ' + total + ' proposals';
    }
    if (empty) empty.hidden = visible !== 0;
  }

  function applySort(mode) {
    const sorted = original.slice();
    if (mode === 'newest') {
      sorted.sort((a, b) => {
        const da = a.card.dataset.date || '';
        const db = b.card.dataset.date || '';
        if (da && db) return db.localeCompare(da);
        if (da) return -1;
        if (db) return 1;
        return a.index - b.index;
      });
    } else if (mode === 'title') {
      sorted.sort((a, b) =>
        (a.card.dataset.title || '').localeCompare(b.card.dataset.title || ''));
    } else {
      sorted.sort((a, b) => a.index - b.index);
    }
    const fragment = document.createDocumentFragment();
    for (const entry of sorted) fragment.appendChild(entry.card);
    list.appendChild(fragment);

    for (const btn of sortButtons) {
      const active = btn.dataset.sort === mode;
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
      btn.classList.toggle('is-active', active);
    }
    try { localStorage.setItem('rfcs-sort', mode); } catch (e) { /* storage disabled */ }
    applyFilter();
  }

  for (const btn of sortButtons) {
    btn.addEventListener('click', () => applySort(btn.dataset.sort));
  }
  let savedSort = 'number';
  try { savedSort = localStorage.getItem('rfcs-sort') || 'number'; } catch (e) { /* storage disabled */ }
  if (sortButtons.some((btn) => btn.dataset.sort === savedSort)) applySort(savedSort);

  if (input) {
    input.addEventListener('input', applyFilter);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && input.value !== '') {
        input.value = '';
        applyFilter();
      }
    });
  }
  if (reset) {
    reset.addEventListener('click', () => {
      if (input) input.value = '';
      applyFilter();
      if (input) input.focus();
    });
  }

  document.addEventListener('keydown', (e) => {
    const target = e.target;
    const tag = (target && target.tagName) || '';
    const typing = /INPUT|TEXTAREA|SELECT/.test(tag) || (target && target.isContentEditable);
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      if (input) { input.focus(); input.select(); }
      return;
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === '/' && input) {
      e.preventDefault();
      input.focus();
      input.select();
    }
  });

  // Creator lookup through GitHub's public REST API. One paginated list call
  // resolves every PR author, and the result is cached for six hours so repeat
  // visits stay well inside the unauthenticated rate limit.
  const creatorEls = Array.from(document.querySelectorAll('.creator[data-pr]'));
  if (creatorEls.length === 0) return;
  const numbers = Array.from(new Set(creatorEls.map((el) => el.dataset.pr))).filter(Boolean);
  if (numbers.length === 0) return;

  const CACHE_KEY = 'rfcs-creators';
  const TTL = 6 * 60 * 60 * 1000;

  function renderCreators(map) {
    for (const el of creatorEls) {
      const info = map[el.dataset.pr];
      const name = el.querySelector('.creator-name');
      if (!info || !name) { el.hidden = true; continue; }
      const avatar = el.querySelector('.creator-avatar');
      if (avatar) {
        const img = document.createElement('img');
        img.src = info.avatar;
        img.alt = '';
        img.width = 18;
        img.height = 18;
        img.loading = 'lazy';
        img.decoding = 'async';
        avatar.appendChild(img);
      }
      const link = document.createElement('a');
      link.href = info.url;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.textContent = info.login;
      name.textContent = '';
      name.appendChild(link);
      el.dataset.loaded = 'true';
      el.hidden = false;
    }
  }

  function hideCreators() {
    for (const el of creatorEls) el.hidden = true;
  }

  let cached = null;
  try { cached = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null'); } catch (e) { /* storage disabled */ }
  if (cached && cached.ts && cached.map && Date.now() - cached.ts < TTL) {
    renderCreators(cached.map);
    return;
  }

  (async () => {
    try {
      const map = {};
      for (let page = 1; page <= 3; page++) {
        const res = await fetch(
          'https://api.github.com/repos/vlang/rfcs/pulls?state=all&per_page=100&page=' + page,
          { headers: { Accept: 'application/vnd.github+json' } }
        );
        if (!res.ok) throw new Error('GitHub returned ' + res.status);
        const rows = await res.json();
        for (const row of rows) {
          if (!row.user || !row.number) continue;
          map[String(row.number)] = {
            login: row.user.login,
            avatar: row.user.avatar_url,
            url: row.user.html_url
          };
        }
        if (rows.length < 100) break;
      }
      try { localStorage.setItem(CACHE_KEY, JSON.stringify({ ts: Date.now(), map })); } catch (e) { /* storage disabled */ }
      renderCreators(map);
    } catch (e) {
      if (cached && cached.map) renderCreators(cached.map);
      else hideCreators();
    }
  })();
});
