// Screen stack: Home → dimension → fine detail. Screens are built once and
// keep their state; enter/leave start and stop whatever they draw.
const factories = new Map();
const built = new Map();
const stack = [];
const listeners = new Set();
let root = null;

export const mount = (el) => { root = el; };
export const screen = (id, factory) => factories.set(id, factory);
export const onChange = (fn) => listeners.add(fn);
export const currentId = () => stack[stack.length - 1];
export const current = () => built.get(currentId());
export const get = (id) => built.get(id);

function show(id, params, dir) {
  let s = built.get(id);
  if (!s) {
    s = factories.get(id)();
    built.set(id, s);
    root.append(s.el);
  }
  for (const [key, other] of built) {
    if (key !== id && other.el.classList.contains("on")) {
      other.el.classList.remove("on");
      if (other.leave) other.leave();
    }
  }
  s.el.dataset.dir = dir;
  s.el.classList.add("on");
  if (s.enter) s.enter(params);
  listeners.forEach((fn) => fn(id));
}

export function go(id, params) {
  if (currentId() === id) { show(id, params, "fwd"); return; }
  stack.push(id);
  show(id, params, "fwd");
}

export function back() {
  if (stack.length <= 1) return false;
  stack.pop();
  show(currentId(), undefined, "back");
  return true;
}

export function home() {
  stack.length = 0;
  stack.push("home");
  show("home", undefined, "back");
}

export function refreshAll(what) {
  for (const s of built.values()) {
    if (s.el.classList.contains("on") && s.refresh) s.refresh(what);
  }
}
