import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { BOARDS, boardById, pinAt } from "./boards.js";
import { defaultProject } from "./devices.js";
import { buildMeshes, headerPreview } from "./geometry.js";
import { downloadParts } from "./stl.js";

const KEY = "pinjig-v3";
const canvas = document.getElementById("view");
const mapEl = document.getElementById("map");
const devicesEl = document.getElementById("devices");
const boardSel = document.getElementById("board");
const statusEl = document.getElementById("status");

let project = load();
let selected = project.devices[0]?.id || "";
let jigGroup = new THREE.Group();

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x101214);
const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 400);
camera.position.set(28, 42, 48);
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
const controls = new OrbitControls(camera, canvas);
controls.target.set(0, 4, 0);
scene.add(new THREE.AmbientLight(0xffffff, 0.55));
const key = new THREE.DirectionalLight(0xffffff, 1.1);
key.position.set(20, 40, 16);
scene.add(key);
scene.add(jigGroup);

function load() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) || "null");
    if (raw && raw.board && Array.isArray(raw.devices)) return raw;
  } catch (e) {}
  return defaultProject();
}

function save() {
  localStorage.setItem(KEY, JSON.stringify(project));
}

function fit() {
  const box = canvas.getBoundingClientRect();
  const w = Math.max(1, box.width), h = Math.max(1, box.height);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h, false);
}

function rebuild() {
  save();
  jigGroup.clear();
  const { board, parts } = buildMeshes(project);
  for (const p of parts) jigGroup.add(p);
  jigGroup.add(headerPreview(board));
  fillBoard();
  fillMap();
  fillDevices();
  statusEl.textContent = legend();
}

function legend() {
  const board = boardById(project.board);
  const bits = project.devices.map((d) => {
    const names = d.pins.map((n) => {
      const p = pinAt(board, n);
      return `${n}${p && p.bcm != null ? "/BCM" + p.bcm : ""}`;
    });
    return `${d.name} → ${names.join(" + ")}`;
  });
  if (project.capUnused) bits.push("unused pins capped");
  return bits.join("  ·  ") || "no devices";
}

function fillBoard() {
  boardSel.innerHTML = "";
  for (const b of BOARDS) {
    const o = document.createElement("option");
    o.value = b.id;
    o.textContent = b.name;
    if (b.id === project.board) o.selected = true;
    boardSel.appendChild(o);
  }
}

function fillMap() {
  const board = boardById(project.board);
  const used = {};
  for (const d of project.devices) for (const n of d.pins) used[n] = d;
  mapEl.innerHTML = "";
  for (let col = 0; col < board.cols; col++) {
    const row = document.createElement("div");
    row.className = "pin-row";
    for (const side of [0, 1]) {
      const phys = col * 2 + side + 1;
      const p = pinAt(board, phys);
      const b = document.createElement("button");
      b.type = "button";
      b.className = "pin";
      const dev = used[phys];
      if (dev) {
        b.classList.add("used");
        b.style.background = dev.color;
      } else if (p.label === "GND") b.classList.add("gnd");
      else if (p.label.startsWith("5V")) b.classList.add("v5");
      else if (p.label.startsWith("3V3")) b.classList.add("v3");
      if (phys === 1) b.classList.add("pin1");
      b.innerHTML = `<b>${phys}</b><span>${p.label}</span>`;
      b.onclick = () => togglePin(phys);
      row.appendChild(b);
    }
    mapEl.appendChild(row);
  }
}

function togglePin(phys) {
  if (!selected) return;
  const dev = project.devices.find((d) => d.id === selected);
  if (!dev) return;
  const i = dev.pins.indexOf(phys);
  if (i >= 0) dev.pins.splice(i, 1);
  else {
    for (const o of project.devices) {
      o.pins = o.pins.filter((n) => n !== phys);
    }
    dev.pins.push(phys);
    dev.pins.sort((a, b) => a - b);
  }
  rebuild();
}

function fillDevices() {
  devicesEl.innerHTML = "";
  for (const d of project.devices) {
    const row = document.createElement("div");
    row.className = "dev" + (d.id === selected ? " on" : "");
    row.innerHTML = `
      <button type="button" class="pick" style="background:${d.color}"></button>
      <input class="nm" value="${d.name}">
      <input class="col" type="color" value="${toHex(d.color)}">
      <button type="button" class="kill">×</button>`;
    row.querySelector(".pick").onclick = () => { selected = d.id; fillDevices(); };
    row.querySelector(".nm").onchange = (e) => { d.name = e.target.value; save(); statusEl.textContent = legend(); };
    row.querySelector(".col").oninput = (e) => { d.color = e.target.value; rebuild(); };
    row.querySelector(".kill").onclick = () => {
      project.devices = project.devices.filter((x) => x.id !== d.id);
      if (selected === d.id) selected = project.devices[0]?.id || "";
      rebuild();
    };
    devicesEl.appendChild(row);
  }
}

function toHex(c) {
  if (c.startsWith("#") && c.length === 7) return c;
  const n = parseInt(c.replace("#", ""), 16);
  if (!Number.isFinite(n)) return "#ff6a00";
  return "#" + n.toString(16).padStart(6, "0");
}

boardSel.onchange = () => {
  project.board = boardSel.value;
  const ok = new Set(boardById(project.board).pins.map((p) => p.phys));
  for (const d of project.devices) d.pins = d.pins.filter((n) => ok.has(n));
  rebuild();
};
document.getElementById("thickness").oninput = (e) => {
  project.thickness = parseFloat(e.target.value);
  document.getElementById("thicknessVal").textContent = project.thickness.toFixed(1) + " mm";
};
document.getElementById("thickness").onchange = () => rebuild();
document.getElementById("hole").oninput = (e) => {
  project.hole = parseFloat(e.target.value);
  document.getElementById("holeVal").textContent = project.hole.toFixed(2) + " mm";
};
document.getElementById("hole").onchange = () => rebuild();
document.getElementById("cap").onchange = (e) => { project.capUnused = e.target.checked; rebuild(); };
document.getElementById("add").onclick = () => {
  const id = "dev" + Math.floor(Math.random() * 1e6);
  project.devices.push({
    id, name: "New device", note: "", color: "#6cff4d", pins: [],
  });
  selected = id;
  rebuild();
};
document.getElementById("reset").onclick = () => {
  project = defaultProject();
  selected = project.devices[0].id;
  syncSliders();
  rebuild();
};
document.getElementById("stl").onclick = () => {
  const { parts } = buildMeshes(project);
  downloadParts(parts);
};

function syncSliders() {
  document.getElementById("thickness").value = String(project.thickness);
  document.getElementById("thicknessVal").textContent = project.thickness.toFixed(1) + " mm";
  document.getElementById("hole").value = String(project.hole);
  document.getElementById("holeVal").textContent = project.hole.toFixed(2) + " mm";
  document.getElementById("cap").checked = !!project.capUnused;
}

function tick() {
  controls.update();
  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}

window.addEventListener("resize", fit);
syncSliders();
fit();
rebuild();
tick();
