import { mergeGeometries, mergeVertices } from "three/addons/utils/BufferGeometryUtils.js";
import * as THREE from "three";

function save(name, blob) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

function toPositions(geometry) {
  const g = geometry.index ? geometry.toNonIndexed() : geometry.clone();
  const out = new THREE.BufferGeometry();
  out.setAttribute("position", g.getAttribute("position").clone());
  return out;
}

function collectGeometries(object) {
  object.updateWorldMatrix(true, true);
  const geos = [];
  object.traverse((child) => {
    if (!child.isMesh || !child.geometry) return;
    const g = child.geometry.clone();
    g.applyMatrix4(child.matrixWorld);
    geos.push(toPositions(g));
  });
  return geos;
}

function bakePart(object) {
  const geos = collectGeometries(object);
  if (!geos.length) return null;
  let merged = geos.length === 1 ? geos[0] : mergeGeometries(geos, false);
  if (!merged) return null;
  merged = mergeVertices(merged, 1e-3);
  merged.computeVertexNormals();
  merged.rotateX(Math.PI / 2);
  return merged;
}

function worldBox(geos) {
  const box = new THREE.Box3();
  for (const g of geos) {
    g.computeBoundingBox();
    box.union(g.boundingBox);
  }
  return box;
}

/** Binary STL with an 80-byte header slicers read as millimeters (1.0 = 1 mm). */
function binaryStlMm(geometry) {
  const geo = geometry.index ? geometry.toNonIndexed() : geometry;
  const pos = geo.getAttribute("position");
  const tris = Math.floor(pos.count / 3);
  const buf = new ArrayBuffer(84 + tris * 50);
  const view = new DataView(buf);
  const header = "UNITS=mm; pinjig; 1.0=1mm";
  for (let i = 0; i < 80; i++) view.setUint8(i, i < header.length ? header.charCodeAt(i) : 0);
  view.setUint32(80, tris, true);
  const ab = new THREE.Vector3(), cb = new THREE.Vector3(), n = new THREE.Vector3();
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3();
  let o = 84;
  for (let t = 0; t < tris; t++) {
    a.fromBufferAttribute(pos, t * 3);
    b.fromBufferAttribute(pos, t * 3 + 1);
    c.fromBufferAttribute(pos, t * 3 + 2);
    cb.subVectors(c, b);
    ab.subVectors(a, b);
    n.copy(cb).cross(ab);
    if (n.lengthSq() > 0) n.normalize();
    else n.set(0, 0, 0);
    view.setFloat32(o, n.x, true); o += 4;
    view.setFloat32(o, n.y, true); o += 4;
    view.setFloat32(o, n.z, true); o += 4;
    for (const v of [a, b, c]) {
      view.setFloat32(o, v.x, true); o += 4;
      view.setFloat32(o, v.y, true); o += 4;
      view.setFloat32(o, v.z, true); o += 4;
    }
    view.setUint16(o, 0, true); o += 2;
  }
  return buf;
}

export async function downloadParts(parts) {
  const baked = [];
  for (const part of parts) {
    const geometry = bakePart(part);
    if (!geometry) continue;
    baked.push({ name: part.name, geometry });
  }
  if (!baked.length) return;

  const box = worldBox(baked.map((p) => p.geometry));
  const shift = new THREE.Matrix4().makeTranslation(-box.min.x, -box.min.y, -box.min.z);
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, "");

  for (const part of baked) {
    part.geometry.applyMatrix4(shift);
    const slug = part.name.replace(/device_/, "").replace(/\s+/g, "_");
    save(
      `pinjig_${slug}_${stamp}_mm.stl`,
      new Blob([binaryStlMm(part.geometry)], { type: "model/stl" }),
    );
    await new Promise((r) => setTimeout(r, 250));
  }
}
