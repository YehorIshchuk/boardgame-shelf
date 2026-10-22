export function formatPlayers(min, max) {
  return min === max ? `${min} гравців` : `${min}–${max} гравців`;
}

export function isValidGame({ title, minPlayers, maxPlayers }) {
  const min = Number(minPlayers);
  const max = Number(maxPlayers);
  return title.trim().length > 0 && min >= 1 && max >= min;
}
