document.addEventListener('DOMContentLoaded', () => {
  const input = document.getElementById('rfc-search');
  const list = document.getElementById('rfc-list');
  const count = document.getElementById('rfc-count');
  const empty = document.getElementById('rfc-empty');
  const reset = document.getElementById('rfc-reset');
  if (!input || !list) return;

  const cards = Array.from(list.querySelectorAll('.rfc-card'));
  const total = cards.length;

  function apply() {
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

  input.addEventListener('input', apply);

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && input.value !== '') {
      input.value = '';
      apply();
    }
  });

  if (reset) {
    reset.addEventListener('click', () => {
      input.value = '';
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', (e) => {
    const target = e.target;
    const tag = (target && target.tagName) || '';
    const typing = /INPUT|TEXTAREA|SELECT/.test(tag) || (target && target.isContentEditable);

    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      input.focus();
      input.select();
      return;
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;

    if (e.key === '/') {
      e.preventDefault();
      input.focus();
      input.select();
    }
  });
});
