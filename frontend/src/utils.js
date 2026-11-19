export function formatPlayers(min, max) {
  return min === max ? `${min} гравців` : `${min}–${max} гравців`;
}

export function isValidGame({ title, minPlayers, maxPlayers }) {
  const min = Number(minPlayers);
  const max = Number(maxPlayers);
  return title.trim().length > 0 && min >= 1 && max >= min;
}

export function footerText(webVersion, info) {
  const web = `web v${webVersion || "dev"}`;
  if (!info) return `${web} · API недоступне`;
  return `${web} · API v${info.version} · под ${info.instance} · видача до ${info.maxBorrowDays} дн.`;
}
