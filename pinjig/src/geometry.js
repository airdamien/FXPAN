import * as THREE from "three";
import { boardById, pinXY, plateSize } from "./boards.js";

const NOTCH = 3.2;
const PIN_HOLE = 0.95;
const CELL_GAP = 0.2;
const WALL = 0.75;
const CAP_H = 5.2;
const CAP_ROOF = 0.5;
const SEG = 24;

function plateOutline(w, h, r, notch) {
  const x = -w / 2, y = -h / 2, X = w / 2, Y = h / 2;
  const s = new THREE.Shape();
  s.moveTo(x + r, y);
  s.lineTo(X - r, y);
  s.quadraticCurveTo(X, y, X, y + r);
  s.lineTo(X, Y - r);
  s.quadraticCurveTo(X, Y, X - r, Y);
  s.lineTo(x + notch, Y);
  s.lineTo(x, Y - notch);
  s.lineTo(x, y + r);
  s.quadraticCurveTo(x, y, x + r, y);
  return s;
}

function addHole(shape, x, y, r) {
  const hole = new THREE.Path();
  hole.absarc(x, y, r, 0, Math.PI * 2, true);
  shape.holes.push(hole);
}

function usedSet(project) {
  const s = new Set();
  for (const d of project.devices) for (const n of d.pins) s.add(n);
  return s;
}

function extrudeUp(shape, depth, y0) {
  const geo = new THREE.ExtrudeGeometry(shape, {
    depth, bevelEnabled: false, curveSegments: SEG,
  });
  geo.rotateX(-Math.PI / 2);
  geo.translate(0, y0, 0);
  return geo;
}

function roundedBox(x0, x1, y0, y1, r) {
  const s = new THREE.Shape();
  r = Math.max(0.05, Math.min(r, (x1 - x0) / 2 - 0.02, (y1 - y0) / 2 - 0.02));
  s.moveTo(x0 + r, y0);
  s.lineTo(x1 - r, y0);
  s.quadraticCurveTo(x1, y0, x1, y0 + r);
  s.lineTo(x1, y1 - r);
  s.quadraticCurveTo(x1, y1, x1 - r, y1);
  s.lineTo(x0 + r, y1);
  s.quadraticCurveTo(x0, y1, x0, y1 - r);
  s.lineTo(x0, y0 + r);
  s.quadraticCurveTo(x0, y0, x0 + r, y0);
  return s;
}

function asHole(shape) {
  const pts = shape.getPoints(24);
  const p = new THREE.Path();
  for (let i = pts.length - 1; i >= 0; i--) {
    if (i === pts.length - 1) p.moveTo(pts[i].x, pts[i].y);
    else p.lineTo(pts[i].x, pts[i].y);
  }
  p.closePath();
  return p;
}

function rowCol(phys) {
  return { col: Math.floor((phys - 1) / 2), row: (phys - 1) % 2 };
}

function adjacent(a, b) {
  const A = rowCol(a), B = rowCol(b);
  return Math.abs(A.col - B.col) + Math.abs(A.row - B.row) === 1;
}

function connectedGroups(pins) {
  const left = new Set(pins);
  const groups = [];
  while (left.size) {
    const start = left.values().next().value;
    const stack = [start];
    left.delete(start);
    const g = [start];
    while (stack.length) {
      const n = stack.pop();
      for (const m of [...left]) {
        if (!adjacent(n, m)) continue;
        left.delete(m);
        stack.push(m);
        g.push(m);
      }
    }
    groups.push(g);
  }
  return groups;
}

function cellBox(board, phys) {
  const { x, y } = pinXY(board, phys);
  const h = board.pitch / 2;
  return { x0: x - h, x1: x + h, y0: y - h, y1: y + h };
}

function mergeBoxes(boxes) {
  return {
    x0: Math.min(...boxes.map((b) => b.x0)),
    x1: Math.max(...boxes.map((b) => b.x1)),
    y0: Math.min(...boxes.map((b) => b.y0)),
    y1: Math.max(...boxes.map((b) => b.y1)),
  };
}

function insetBox(b, g) {
  return { x0: b.x0 + g, x1: b.x1 - g, y0: b.y0 + g, y1: b.y1 - g };
}

function deviceIslands(board, pins) {
  return connectedGroups(pins).map((g) =>
    insetBox(mergeBoxes(g.map((n) => cellBox(board, n))), CELL_GAP));
}

function eq(a, b) {
  return Math.abs(a - b) < 1e-6;
}

function unusedEdges(board, pins) {
  const set = new Set(pins);
  const has = (col, row) => {
    if (row < 0 || row > 1 || col < 0) return false;
    return set.has(col * 2 + row + 1);
  };
  const edges = [];
  for (const phys of pins) {
    const { col, row } = rowCol(phys);
    const b = cellBox(board, phys);
    if (!has(col + 1, row)) edges.push({ x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y0 });
    if (!has(col, row + 1)) edges.push({ x0: b.x1, y0: b.y0, x1: b.x1, y1: b.y1 });
    if (!has(col - 1, row)) edges.push({ x0: b.x1, y0: b.y1, x1: b.x0, y1: b.y1 });
    if (!has(col, row - 1)) edges.push({ x0: b.x0, y0: b.y1, x1: b.x0, y1: b.y0 });
  }
  return edges;
}

function chainLoops(edges) {
  const left = edges.map((e) => ({ ...e, used: false }));
  const loops = [];
  for (let i = 0; i < left.length; i++) {
    if (left[i].used) continue;
    const sx = left[i].x0, sy = left[i].y0;
    let x = sx, y = sy;
    const loop = [];
    for (let n = 0; n < left.length + 2; n++) {
      const j = left.findIndex((e) => !e.used && eq(e.x0, x) && eq(e.y0, y));
      if (j < 0) break;
      left[j].used = true;
      x = left[j].x1;
      y = left[j].y1;
      loop.push({ x, y });
      if (loop.length > 1 && eq(x, sx) && eq(y, sy)) break;
    }
    if (loop.length >= 4) loops.push(simplifyRing(loop));
  }
  return loops;
}

function simplifyRing(pts) {
  const p = pts.filter((pt, i) => {
    if (i === pts.length - 1 && eq(pt.x, pts[0].x) && eq(pt.y, pts[0].y)) return false;
    return true;
  });
  const out = [];
  const n = p.length;
  for (let i = 0; i < n; i++) {
    const a = p[(i - 1 + n) % n], b = p[i], c = p[(i + 1) % n];
    const col = (eq(a.x, b.x) && eq(b.x, c.x)) || (eq(a.y, b.y) && eq(b.y, c.y));
    if (!col) out.push(b);
  }
  return out.length >= 4 ? out : p;
}

function ringArea(pts) {
  let a = 0;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.x * q.y - q.x * p.y;
  }
  return a / 2;
}

function ensureCCW(pts) {
  return ringArea(pts) < 0 ? pts.slice().reverse() : pts;
}

function offsetRing(pts, dist) {
  const r = ensureCCW(pts);
  const n = r.length;
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = r[(i - 1 + n) % n], b = r[i], c = r[(i + 1) % n];
    const d1x = Math.sign(b.x - a.x) || 0, d1y = Math.sign(b.y - a.y) || 0;
    const d2x = Math.sign(c.x - b.x) || 0, d2y = Math.sign(c.y - b.y) || 0;
    out.push({
      x: b.x + dist * (-d1y - d2y),
      y: b.y + dist * (d1x + d2x),
    });
  }
  return out;
}

function classifyLoops(loops) {
  const signed = loops.map((ring) => ({ ring: ensureCCW(ring), area: Math.abs(ringArea(ring)) }));
  signed.sort((a, b) => b.area - a.area);
  return { outer: signed[0]?.ring, holes: signed.slice(1).map((s) => s.ring) };
}

function offsetUnused(loops, dist) {
  const { outer, holes } = classifyLoops(loops);
  if (!outer) return null;
  return {
    outer: offsetRing(outer, dist),
    holes: holes.map((h) => offsetRing(h, -dist)),
  };
}

function ringSizeOk(pts, min = 0.55) {
  if (!pts || pts.length < 4) return false;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const p of pts) {
    if (p.x < x0) x0 = p.x;
    if (p.y < y0) y0 = p.y;
    if (p.x > x1) x1 = p.x;
    if (p.y > y1) y1 = p.y;
  }
  return x1 - x0 > min && y1 - y0 > min;
}

function poly(path, pts) {
  path.moveTo(pts[0].x, pts[0].y);
  for (let i = 1; i < pts.length; i++) path.lineTo(pts[i].x, pts[i].y);
  path.closePath();
}

function shapeOuterHoles(outer, holes) {
  const s = new THREE.Shape();
  poly(s, ensureCCW(outer));
  for (const h of holes) {
    if (!h || h.length < 4) continue;
    const p = new THREE.Path();
    const cw = ringArea(h) > 0 ? h.slice().reverse() : h;
    poly(p, cw);
    s.holes.push(p);
  }
  return s;
}

function boxLoops(box) {
  return [[
    { x: box.x0, y: box.y0 },
    { x: box.x1, y: box.y0 },
    { x: box.x1, y: box.y1 },
    { x: box.x0, y: box.y1 },
  ]];
}

function addCavities(body, board, unused, T, mat) {
  for (const group of connectedGroups(unused)) {
    let loops = chainLoops(unusedEdges(board, group));
    if (!loops.length) {
      loops = boxLoops(mergeBoxes(group.map((n) => cellBox(board, n))));
    }
    const rim = offsetUnused(loops, CELL_GAP);
    if (!rim || !ringSizeOk(rim.outer)) continue;
    const inner = offsetUnused(loops, CELL_GAP + WALL);
    const wallHoles = [];
    if (inner && ringSizeOk(inner.outer)) wallHoles.push(inner.outer);
    body.add(new THREE.Mesh(extrudeUp(shapeOuterHoles(rim.outer, wallHoles), CAP_H, T), mat));
    for (let i = 0; i < rim.holes.length; i++) {
      const innerHole = inner?.holes[i];
      if (!innerHole || !ringSizeOk(rim.holes[i]) || !ringSizeOk(innerHole)) continue;
      body.add(new THREE.Mesh(extrudeUp(shapeOuterHoles(innerHole, [rim.holes[i]]), CAP_H, T), mat));
    }
    body.add(new THREE.Mesh(extrudeUp(shapeOuterHoles(rim.outer, rim.holes), CAP_ROOF, T + CAP_H), mat));
  }
}

export function buildMeshes(project) {
  const board = boardById(project.board);
  const T = Math.max(0.4, Number(project.thickness) || 0.5);
  const holeR = Math.max(0.4, (Number(project.hole) || PIN_HOLE) / 2);
  const margin = Math.max(2.2, Number(project.margin) || 3.2);
  const { w, h } = plateSize(board, margin);
  const used = usedSet(project);
  const cap = !!project.capUnused;
  const bodyMat = new THREE.MeshStandardMaterial({ color: 0x1a1d22, roughness: 0.55 });

  const plate = plateOutline(w, h, 1.2, NOTCH);
  for (const p of board.pins) {
    if (used.has(p.phys)) continue;
    const { x, y } = pinXY(board, p.phys);
    addHole(plate, x, y, holeR);
  }

  const pads = [];
  for (const dev of project.devices) {
    if (!dev.pins.length) continue;
    const islands = deviceIslands(board, dev.pins);
    const group = new THREE.Group();
    group.name = `device_${dev.id}`;
    const mat = new THREE.MeshStandardMaterial({
      color: new THREE.Color(dev.color), roughness: 0.4,
    });
    for (const box of islands) {
      const shape = roundedBox(box.x0, box.x1, box.y0, box.y1, 0.35);
      for (const n of dev.pins) {
        const { x, y } = pinXY(board, n);
        if (x >= box.x0 && x <= box.x1 && y >= box.y0 && y <= box.y1)
          addHole(shape, x, y, holeR);
      }
      plate.holes.push(asHole(roundedBox(box.x0, box.x1, box.y0, box.y1, 0.35)));
      group.add(new THREE.Mesh(extrudeUp(shape, T, 0), mat));
    }
    pads.push(group);
  }

  const body = new THREE.Group();
  body.name = "body";
  body.add(new THREE.Mesh(extrudeUp(plate, T, 0), bodyMat));

  if (cap) {
    const unused = board.pins.map((p) => p.phys).filter((n) => !used.has(n));
    addCavities(body, board, unused, T, bodyMat);
  }

  return { board, parts: [body, ...pads], size: { w, h, T } };
}

/** Grey header plastic under the jig. Preview only — not in STL parts. */
export function headerPreview(board) {
  const plastic = 2.5;
  const len = (board.cols - 1) * board.pitch + 1.2;
  const geo = new THREE.BoxGeometry(board.pitch + 0.2, plastic, len);
  const m = new THREE.Mesh(
    geo,
    new THREE.MeshStandardMaterial({ color: 0x2a2c30, roughness: 0.8 }),
  );
  m.position.y = -plastic / 2;
  m.name = "preview_header";
  return m;
}
