import { useEffect, useState } from "react";

const api = (path, options) =>
  fetch(`/api${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  }).then(async (res) => {
    if (res.status === 204) return null;
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `Помилка ${res.status}`);
    return data;
  });

export default function App() {
  const [games, setGames] = useState([]);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ title: "", minPlayers: 2, maxPlayers: 4 });

  const load = () =>
    api("/games").then(setGames).catch((e) => setError(e.message));

  useEffect(() => {
    load();
  }, []);

  const run = async (fn) => {
    setError("");
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e.message);
    }
  };

  const addGame = (e) => {
    e.preventDefault();
    run(async () => {
      await api("/games", {
        method: "POST",
        body: JSON.stringify({
          title: form.title,
          minPlayers: Number(form.minPlayers),
          maxPlayers: Number(form.maxPlayers),
        }),
      });
      setForm({ title: "", minPlayers: 2, maxPlayers: 4 });
    });
  };

  const borrow = (id) => {
    const name = prompt("Хто бере гру?");
    if (name) run(() => api(`/games/${id}/borrow`, { method: "POST", body: JSON.stringify({ name }) }));
  };

  return (
    <main className="container">
      <h1>🎲 BoardGame Shelf</h1>
      <p className="sub">Облік настільних ігор клубу</p>

      {error && <div className="error">{error}</div>}

      <form className="card form" onSubmit={addGame}>
        <input
          placeholder="Назва гри"
          value={form.title}
          onChange={(e) => setForm({ ...form, title: e.target.value })}
        />
        <input
          type="number"
          min="1"
          value={form.minPlayers}
          onChange={(e) => setForm({ ...form, minPlayers: e.target.value })}
          title="Мін. гравців"
        />
        <input
          type="number"
          min="1"
          value={form.maxPlayers}
          onChange={(e) => setForm({ ...form, maxPlayers: e.target.value })}
          title="Макс. гравців"
        />
        <button type="submit">Додати</button>
      </form>

      <ul className="list">
        {games.map((g) => (
          <li key={g.id} className="card item">
            <div>
              <strong>{g.title}</strong>
              <span className="meta">
                {g.minPlayers}–{g.maxPlayers} гравців
              </span>
              {g.isBorrowed && <span className="badge">у {g.borrowedBy}</span>}
            </div>
            <div className="actions">
              {g.isBorrowed ? (
                <button onClick={() => run(() => api(`/games/${g.id}/return`, { method: "POST" }))}>
                  Повернути
                </button>
              ) : (
                <button onClick={() => borrow(g.id)}>Видати</button>
              )}
              <button className="danger" onClick={() => run(() => api(`/games/${g.id}`, { method: "DELETE" }))}>
                ✕
              </button>
            </div>
          </li>
        ))}
        {games.length === 0 && <p className="sub">Полиця порожня — додайте першу гру.</p>}
      </ul>
    </main>
  );
}
