// The layout every dimension shares: back, symbol and name across the
// top; the list on the left; on the right, whatever makes the choice
// visible (the frame, the histogram, the look).
import { h } from "./ui.js";
import { icon } from "./icons.js";
import { back, home } from "./nav.js";

export function dim({ id, title, ic, crumb = "", note = "" }) {
  const noteEl = h("span", { class: "bar-note", text: note });
  const el = h("section", { class: "screen dim", dataset: { screen: id } },
    h("header", { class: "bar" },
      h("button", { class: "back", type: "button", "aria-label": "Back", html: icon("back"), on: { click: () => back() } }),
      h("span", { class: "bar-ic", html: icon(ic) }),
      h("h1", {}, crumb ? h("span", { class: "crumb", text: crumb }) : null, h("span", { text: title })),
      h("span", { class: "grow" }),
      noteEl,
      h("button", { class: "done", type: "button", text: "Done", on: { click: () => home() } })));
  const list = h("div", { class: "dim-list" });
  const panel = h("div", { class: "dim-panel" });
  el.append(h("div", { class: "dim-body" }, list, panel));
  return { el, list, panel, noteEl };
}

// Same bar, one scrolling body (Playback, the gallery).
export function page({ id, title, ic, crumb = "" }) {
  const s = dim({ id, title, ic, crumb });
  const body = s.el.querySelector(".dim-body");
  body.className = "page-body";
  body.innerHTML = "";
  return { el: s.el, body, noteEl: s.noteEl, bar: s.el.querySelector(".bar") };
}

// A fact line in a panel: label left, value right.
export function fact(label, value = "", cls = "") {
  const v = h("b", { text: value });
  const el = h("div", { class: "fact " + cls }, h("span", { text: label }), v);
  el.set = (text, klass) => {
    v.textContent = text;
    if (klass !== undefined) el.className = "fact " + klass;
  };
  return el;
}
