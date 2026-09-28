// Release: timer, fire both bodies, record the mode and look with the
// set, stitch if asked, then review. Capture with confidence.
import { h, toast, ask } from "./ui.js";
import { icon } from "./icons.js";
import * as M from "./model.js";
import * as api from "./api.js";
import { live, stopPull, compose, bitmap } from "./live.js";
import { ensureFilter, lookName, tweaks } from "./look.js";
import { toggleLive, refreshCaptures } from "./app.js";
import { go } from "./nav.js";

let shooting = false;
export const busy = () => shooting;
let cancelCount = null;
let closeReview = null;

export function cancelOverlay() {
  if (cancelCount) { cancelCount(); return true; }
  if (closeReview) { closeReview(); return true; }
  return false;
}

function countdown(n) {
  return new Promise((resolve) => {
    const num = h("b", { text: String(n) });
    const veil = h("div", { class: "veil count" },
      h("div", { class: "count-box" }, num, h("span", { text: "Tap to cancel" })));
    let left = n;
    const timer = setInterval(() => {
      left -= 1;
      if (left <= 0) stop(true);
      else { num.textContent = String(left); num.classList.remove("tick"); void num.offsetWidth; num.classList.add("tick"); }
    }, 1000);
    function stop(ok) {
      clearInterval(timer);
      veil.remove();
      cancelCount = null;
      resolve(ok);
    }
    veil.addEventListener("pointerdown", () => stop(false));
    cancelCount = () => stop(false);
    document.body.append(veil);
  });
}

export function stitchBody(stamp, look, engine) {
  const ph = M.photo();
  return {
    stamp,
    mode: engine || ph.drive.engine,
    overlap: Number(M.store.prefs.overlap) || 0.2,
    flip_r: !!M.store.prefs.flip_r,
    crop_inner: ph.frame.clip,
    squeeze: ph.frame.squeeze,
    look: look || ph.look,
  };
}

export async function fire() {
  if (shooting || cancelCount) return;
  if (!M.onlineRoles().length) { toast("No bodies on USB", "err"); return; }
  const ph = M.photo();
  if (ph.drive.timer && !(await countdown(ph.drive.timer))) return;
  shooting = true;
  M.emit("shoot");
  const wasLive = live.pulling;
  if (wasLive) await toggleLive(false);
  try {
    await M.flushNow();
    const j = await api.post("/api/shoot", M.exposureBody());
    toast(j.message, "info", 2200);
    const mode = M.activeMode();
    if (j.stamp) {
      const note = { stamp: j.stamp, mode: mode?.id || "", mode_name: mode?.name || "",
        look: ph.look, squeeze: ph.frame.squeeze, guide: ph.frame.guide };
      M.store.fx.shots[j.stamp] = note;
      api.post("/fxos/api/shot", note).catch(() => {});
    }
    const files = j.files || [];
    if (ph.drive.auto_stitch && files.length >= 2) {
      api.post("/api/pano", stitchBody(j.stamp, ph.look)).catch((e) => toast(e.message, "err"));
    }
    await refreshCaptures();
    shooting = false;
    M.emit("shoot");
    const secs = Number(j.preview_s ?? ph.drive.review);
    if (files.length && secs > 0) await review(j.stamp, { secs });
  } catch (e) {
    toast(e.message, "err");
  } finally {
    shooting = false;
    M.emit("shoot");
    if (wasLive) toggleLive(true);
  }
}

// The set just made: a stitched preview at once, the real pano as soon as
// the stitcher has it. Touch the picture to hold it on screen.
export function review(stamp, { secs = 0 } = {}) {
  return new Promise((resolve) => {
    const note = M.store.fx.shots[stamp] || {};
    const pair = () => (M.store.pairs || []).find((p) => p.stamp === stamp) || { stamp };
    const cv = h("canvas", { class: "rv-cv" });
    const img = h("img", { class: "rv-pano", alt: "", hidden: true });
    const badge = h("span", { class: "rv-badge", text: "Preview" });
    const stat = h("div", { class: "rv-stat" });
    const count = h("span", { class: "rv-count" });
    const lockBtn = h("button", { class: "btn", type: "button" });
    const t = stamp.match(/_(\d\d)(\d\d)(\d\d)$/);
    const box = h("div", { class: "rv-box" },
      h("div", { class: "rv-head" },
        h("b", { text: t ? `${t[1]}:${t[2]}:${t[3]}` : stamp }),
        h("span", { text: [note.mode_name, note.look ? lookName(note.look, M.store.fx.looks) : ""].filter(Boolean).join(" · ") }),
        h("span", { class: "grow" }), count),
      h("div", { class: "rv-img" }, cv, img, badge),
      stat,
      h("div", { class: "rv-acts" },
        lockBtn,
        h("button", { class: "btn danger", type: "button", html: icon("trash") + "<span>Delete</span>", on: { click: del } }),
        h("button", { class: "btn", type: "button", html: icon("play") + "<span>Playback</span>",
          on: { click: () => { done("open"); go("shot", { stamp }); } } }),
        h("span", { class: "grow" }),
        h("button", { class: "btn primary", type: "button", html: icon("check") + "<span>Keep</span>", on: { click: () => done("keep") } })));
    const veil = h("div", { class: "veil review" }, box);
    document.body.append(veil);
    let left = secs;
    let timer = 0;
    let poll = 0;
    let held = !secs;
    const paintCount = () => { count.textContent = held ? "" : `${left} s`; };
    const hold = () => { held = true; clearInterval(timer); paintCount(); };
    box.querySelector(".rv-img").addEventListener("pointerdown", hold);
    if (!held) {
      timer = setInterval(() => { left -= 1; if (left <= 0) done("keep"); else paintCount(); }, 1000);
    }
    paintCount();
    function done(why) {
      clearInterval(timer);
      clearInterval(poll);
      veil.remove();
      closeReview = null;
      resolve(why);
    }
    closeReview = () => done("keep");

    const paintLock = () => {
      const on = !!pair().protected;
      lockBtn.innerHTML = icon(on ? "lock" : "unlock") + `<span>${on ? "Locked" : "Lock"}</span>`;
      lockBtn.classList.toggle("on", on);
    };
    lockBtn.addEventListener("click", async () => {
      hold();
      try {
        const j = await api.post("/api/captures/protect", { stamp, protected: !pair().protected });
        M.store.pairs = j.pairs || M.store.pairs;
        paintLock();
      } catch (e) { toast(e.message, "err"); }
    });
    async function del() {
      hold();
      if (pair().protected) { toast("Locked — unlock first", "err"); return; }
      if (!(await ask({ title: "Delete this set?", text: "T, R and the panorama.", ok: "Delete", danger: true }))) return;
      try {
        const j = await api.post("/api/captures/delete", { stamp });
        M.store.pairs = j.pairs || [];
        M.emit("captures");
        done("delete");
      } catch (e) { toast(e.message, "err"); }
    }
    paintLock();

    (async () => {
      const p = pair();
      if (!p.t || !p.r) return;
      try {
        const [tb, rb] = await Promise.all([bitmap(p.t, 1280), bitmap(p.r, 1280)]);
        compose(cv, tb, rb);
        tb.close();
        rb.close();
        const sq = Number(note.squeeze) || 1;
        if (sq > 1.01) {
          const tmp = h("canvas", { width: Math.round(cv.width * sq), height: cv.height });
          tmp.getContext("2d").drawImage(cv, 0, 0, tmp.width, tmp.height);
          cv.width = tmp.width;
          cv.getContext("2d").drawImage(tmp, 0, 0);
        }
        cv.style.filter = ensureFilter("fx-rv", note.look || M.photo().look);
      } catch { /* the files may still be arriving */ }
    })();

    const check = async () => {
      try {
        const j = await api.get("/api/pano/job?stamp=" + encodeURIComponent(stamp));
        M.store.pairs = j.pairs || M.store.pairs;
        const job = j.job || {};
        const p = pair();
        if (p.pano && (!job.running || job.phase === "done")) {
          img.onload = () => { img.hidden = false; cv.hidden = true; };
          img.src = api.file(p.pano, 1800) + "&t=" + (p.pano_mtime || Date.now());
          const s = p.stitch || {};
          badge.textContent = "Stitched" + (s.mode ? ` · ${s.mode}` : "") + (s.sec ? ` · ${s.sec} s` : "");
          badge.classList.add("ok");
          stat.textContent = tweaks(note.look).join(" · ");
          clearInterval(poll);
          return;
        }
        if (job.phase === "error") {
          stat.textContent = "Stitch failed: " + (job.error || "");
          stat.className = "rv-stat err";
          clearInterval(poll);
          return;
        }
        if (job.running) stat.textContent = (job.phase === "queued" ? "Queued · " : "Stitching · ") + (job.message || "");
        else stat.textContent = "Not stitched — Playback stitches it";
      } catch { /* keep the preview */ }
    };
    poll = setInterval(check, 700);
    check();
  });
}
