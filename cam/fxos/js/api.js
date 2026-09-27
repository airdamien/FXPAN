async function call(path, opt = {}) {
  const r = await fetch(path, opt);
  const text = await r.text();
  let j = {};
  try { j = text ? JSON.parse(text) : {}; } catch { j = { error: text || r.statusText }; }
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
}

export const get = (path) => call(path);

export const post = (path, body = {}) => call(path, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export const file = (name, w) =>
  "/api/file/" + encodeURIComponent(name) + (w ? "?w=" + w : "");
