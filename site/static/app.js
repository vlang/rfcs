document.addEventListener('DOMContentLoaded', () => {
  const input = document.getElementById('rfc-search');
  const list = document.getElementById('rfc-list');
  const count = document.getElementById('rfc-count');
  if (!input || !list) return;
  const cards = Array.from(list.querySelectorAll('.rfc-card'));
  const total = cards.length;
  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();
    let visible = 0;
    for (const card of cards) {
      const hay = (card.getAttribute('data-search') || '').toLowerCase();
      const show = q === '' || hay.includes(q);
      card.style.display = show ? '' : 'none';
      if (show) visible++;
    }
    if (count) count.textContent = visible + ' of ' + total + ' RFCs';
  });
});
