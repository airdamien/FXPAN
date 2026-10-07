#include <metal_stdlib>
using namespace metal;

/// Overlap SIFT. The pyramid, the extrema, the orientation, and the descriptor run here.
/// A descriptor is taken on that octave's gaussian, so the window stays a few dozen pixels.

struct SiftExtrema {
    float prelim;
    float scale;
    float sigma;
    float osigma;
    uint octave;
    uint layer;
    uint cap;
    uint pad;
};

struct SiftCand {
    float x;
    float y;
    float sigma;
    float response;
    float ox;
    float oy;
    float osigma;
    uint octave;
    uint layer;
    uint pad;
};

struct SiftKey {
    float x;
    float y;
    float sigma;
    float angle;
    float response;
    float ox;
    float oy;
    float osigma;
    uint octave;
    uint layer;
    uint pad0;
    uint pad1;
};

struct SiftDescIn {
    float ox;
    float oy;
    float osigma;
    float angle;
    uint index;
    uint pad0;
    uint pad1;
    uint pad2;
};

struct SiftMatchIn {
    uint nL;
    uint nR;
    float gate;
    uint pad;
};

kernel void fxpanBlurH(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float *weights [[buffer(0)]],
    constant uint &radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    int r = int(radius);
    int last = int(w) - 1;
    float sum = 0.0f;
    for (int i = -r; i <= r; i++) {
        int x = clamp(int(gid.x) + i, 0, last);
        sum += src.read(uint2(uint(x), gid.y)).r * weights[i + r];
    }
    dst.write(float4(sum, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanBlurV(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float *weights [[buffer(0)]],
    constant uint &radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    int r = int(radius);
    int last = int(h) - 1;
    float sum = 0.0f;
    for (int i = -r; i <= r; i++) {
        int y = clamp(int(gid.y) + i, 0, last);
        sum += src.read(uint2(gid.x, uint(y))).r * weights[i + r];
    }
    dst.write(float4(sum, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanDown2(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float v = src.read(uint2(gid.x * 2, gid.y * 2)).r;
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanDog(
    texture2d<float, access::read> a [[texture(0)]],
    texture2d<float, access::read> b [[texture(1)]],
    texture2d<float, access::write> dst [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= a.get_width() || gid.y >= a.get_height()) return;
    float v = a.read(gid).r - b.read(gid).r;
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanExtrema(
    texture2d<float, access::read> d0 [[texture(0)]],
    texture2d<float, access::read> d1 [[texture(1)]],
    texture2d<float, access::read> d2 [[texture(2)]],
    device SiftCand *out [[buffer(0)]],
    device atomic_uint *count [[buffer(1)]],
    constant SiftExtrema &u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = d1.get_width();
    uint h = d1.get_height();
    if (gid.x < 1 || gid.y < 1 || gid.x + 1 >= w || gid.y + 1 >= h) return;
    float c = d1.read(gid).r;
    if (fabs(c) < u.prelim) return;
    bool hi = c > 0.0f;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            uint2 p = uint2(int(gid.x) + dx, int(gid.y) + dy);
            float v0 = d0.read(p).r;
            float v2 = d2.read(p).r;
            if (hi ? (v0 >= c || v2 >= c) : (v0 <= c || v2 <= c)) return;
            if (dx == 0 && dy == 0) continue;
            float v1 = d1.read(p).r;
            if (hi ? (v1 >= c) : (v1 <= c)) return;
        }
    }
    float left = d1.read(uint2(gid.x - 1, gid.y)).r;
    float right = d1.read(uint2(gid.x + 1, gid.y)).r;
    float up = d1.read(uint2(gid.x, gid.y - 1)).r;
    float down = d1.read(uint2(gid.x, gid.y + 1)).r;
    float dxx = right + left - 2.0f * c;
    float dyy = down + up - 2.0f * c;
    float dxy = (
        d1.read(uint2(gid.x + 1, gid.y + 1)).r
        - d1.read(uint2(gid.x - 1, gid.y + 1)).r
        - d1.read(uint2(gid.x + 1, gid.y - 1)).r
        + d1.read(uint2(gid.x - 1, gid.y - 1)).r
    ) * 0.25f;
    float tr = dxx + dyy;
    float det = dxx * dyy - dxy * dxy;
    if (det <= 1e-12f) return;
    float edge = 10.0f;
    if (!(tr * tr * edge < (edge + 1.0f) * (edge + 1.0f) * det)) return;
    uint slot = atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
    if (slot >= u.cap) return;
    SiftCand cand;
    cand.x = float(gid.x) * u.scale;
    cand.y = float(gid.y) * u.scale;
    cand.sigma = u.sigma;
    cand.response = fabs(c);
    cand.ox = float(gid.x);
    cand.oy = float(gid.y);
    cand.osigma = u.osigma;
    cand.octave = u.octave;
    cand.layer = u.layer;
    cand.pad = 0;
    out[slot] = cand;
}

kernel void fxpanOrient(
    texture2d<float, access::read> img [[texture(0)]],
    const device SiftCand *in [[buffer(0)]],
    device SiftKey *out [[buffer(1)]],
    device uint *counts [[buffer(2)]],
    constant uint &n [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= n) return;
    SiftCand s = in[gid];
    int w = int(img.get_width());
    int h = int(img.get_height());
    float sigma = s.osigma;
    int radius = max(2, int(round(4.5f * sigma)));
    float hist[36];
    for (int i = 0; i < 36; i++) hist[i] = 0.0f;
    float sig = 1.5f * sigma;
    float sig2 = sig * sig;
    int ix = int(round(s.ox));
    int iy = int(round(s.oy));
    for (int yy = iy - radius; yy <= iy + radius; yy++) {
        if (yy < 1 || yy >= h - 1) continue;
        for (int xx = ix - radius; xx <= ix + radius; xx++) {
            if (xx < 1 || xx >= w - 1) continue;
            float dx = img.read(uint2(xx + 1, yy)).r - img.read(uint2(xx - 1, yy)).r;
            float dy = img.read(uint2(xx, yy + 1)).r - img.read(uint2(xx, yy - 1)).r;
            float mag = sqrt(dx * dx + dy * dy);
            float ang = atan2(dy, dx);
            if (ang < 0.0f) ang += 2.0f * M_PI_F;
            float dx0 = float(xx) - s.ox;
            float dy0 = float(yy) - s.oy;
            float wgt = exp(-0.5f * (dx0 * dx0 + dy0 * dy0) / sig2);
            float bin = ang * 36.0f / (2.0f * M_PI_F);
            int b0 = int(bin) % 36;
            float f = bin - floor(bin);
            hist[b0] += mag * wgt * (1.0f - f);
            hist[(b0 + 1) % 36] += mag * wgt * f;
        }
    }
    for (int pass = 0; pass < 2; pass++) {
        float next[36];
        for (int i = 0; i < 36; i++) {
            next[i] = (hist[(i + 35) % 36] + hist[i] + hist[(i + 1) % 36]) / 3.0f;
        }
        for (int i = 0; i < 36; i++) hist[i] = next[i];
    }
    float peak = 0.0f;
    for (int i = 0; i < 36; i++) peak = max(peak, hist[i]);
    uint written = 0;
    if (peak >= 1e-6f) {
        for (int i = 0; i < 36 && written < 4; i++) {
            float y0 = hist[(i + 35) % 36];
            float y1 = hist[i];
            float y2 = hist[(i + 1) % 36];
            if (y1 < 0.8f * peak || y1 <= y0 || y1 <= y2) continue;
            float denom = y0 - 2.0f * y1 + y2;
            float off = fabs(denom) < 1e-8f ? 0.0f : 0.5f * (y0 - y2) / denom;
            float ang = (float(i) + off) * 2.0f * M_PI_F / 36.0f;
            if (ang < 0.0f) ang += 2.0f * M_PI_F;
            if (ang >= 2.0f * M_PI_F) ang -= 2.0f * M_PI_F;
            SiftKey k;
            k.x = s.x;
            k.y = s.y;
            k.sigma = s.sigma;
            k.angle = ang;
            k.response = s.response;
            k.ox = s.ox;
            k.oy = s.oy;
            k.osigma = s.osigma;
            k.octave = s.octave;
            k.layer = s.layer;
            k.pad0 = 0;
            k.pad1 = 0;
            out[gid * 4 + written] = k;
            written++;
        }
    }
    if (written == 0) {
        SiftKey k;
        k.x = s.x;
        k.y = s.y;
        k.sigma = s.sigma;
        k.angle = 0.0f;
        k.response = s.response;
        k.ox = s.ox;
        k.oy = s.oy;
        k.osigma = s.osigma;
        k.octave = s.octave;
        k.layer = s.layer;
        k.pad0 = 0;
        k.pad1 = 0;
        out[gid * 4] = k;
        written = 1;
    }
    counts[gid] = written;
}

inline void fxpanSplat(thread float hist[128], float row, float col, float ob, float value) {
    int r0 = int(floor(row));
    int c0 = int(floor(col));
    int o0 = int(floor(ob)) % 8;
    float rf = row - float(r0);
    float cf = col - float(c0);
    float of = ob - floor(ob);
    for (int dr = 0; dr <= 1; dr++) {
        int rr = r0 + dr;
        if (rr < 0 || rr > 3) continue;
        float rw = dr == 0 ? (1.0f - rf) : rf;
        for (int dc = 0; dc <= 1; dc++) {
            int cc = c0 + dc;
            if (cc < 0 || cc > 3) continue;
            float cw = dc == 0 ? (1.0f - cf) : cf;
            for (int ddo = 0; ddo <= 1; ddo++) {
                int oo = (o0 + ddo) & 7;
                float ow = ddo == 0 ? (1.0f - of) : of;
                hist[(rr * 4 + cc) * 8 + oo] += value * rw * cw * ow;
            }
        }
    }
}

kernel void fxpanDescribe(
    texture2d<float, access::read> img [[texture(0)]],
    const device SiftDescIn *in [[buffer(0)]],
    device float *desc [[buffer(1)]],
    device uint *ok [[buffer(2)]],
    constant uint &n [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= n) return;
    SiftDescIn s = in[gid];
    int w = int(img.get_width());
    int h = int(img.get_height());
    float histWidth = 3.0f * s.osigma;
    if (histWidth < 1.0f) {
        ok[s.index] = 0;
        return;
    }
    int radius = int(round(histWidth * 2.5f * 1.41421356f));
    float cosT = cos(-s.angle);
    float sinT = sin(-s.angle);
    float hist[128];
    for (int i = 0; i < 128; i++) hist[i] = 0.0f;
    int ix = int(round(s.ox));
    int iy = int(round(s.oy));
    float winSig = 2.0f * histWidth;
    float win2 = winSig * winSig;
    for (int yy = iy - radius; yy <= iy + radius; yy++) {
        if (yy < 1 || yy >= h - 1) continue;
        for (int xx = ix - radius; xx <= ix + radius; xx++) {
            if (xx < 1 || xx >= w - 1) continue;
            float dx0 = float(xx) - s.ox;
            float dy0 = float(yy) - s.oy;
            float rx = cosT * dx0 - sinT * dy0;
            float ry = sinT * dx0 + cosT * dy0;
            float col = rx / histWidth + 1.5f;
            float row = ry / histWidth + 1.5f;
            if (col < -0.5f || col >= 3.5f || row < -0.5f || row >= 3.5f) continue;
            float gx = img.read(uint2(xx + 1, yy)).r - img.read(uint2(xx - 1, yy)).r;
            float gy = img.read(uint2(xx, yy + 1)).r - img.read(uint2(xx, yy - 1)).r;
            float mag = sqrt(gx * gx + gy * gy);
            float ang = atan2(gy, gx) - s.angle;
            if (ang < 0.0f) ang += 2.0f * M_PI_F;
            if (ang >= 2.0f * M_PI_F) ang -= 2.0f * M_PI_F;
            float ob = ang * 8.0f / (2.0f * M_PI_F);
            float wgt = exp(-0.5f * (rx * rx + ry * ry) / win2);
            fxpanSplat(hist, row, col, ob, mag * wgt);
        }
    }
    float norm = 0.0f;
    for (int i = 0; i < 128; i++) norm += hist[i] * hist[i];
    norm = sqrt(norm);
    if (norm < 1e-6f) {
        ok[s.index] = 0;
        return;
    }
    for (int i = 0; i < 128; i++) hist[i] /= norm;
    for (int i = 0; i < 128; i++) {
        if (hist[i] > 0.2f) hist[i] = 0.2f;
    }
    norm = 0.0f;
    for (int i = 0; i < 128; i++) norm += hist[i] * hist[i];
    norm = sqrt(norm);
    if (norm < 1e-6f) {
        ok[s.index] = 0;
        return;
    }
    device float *dst = desc + s.index * 128;
    for (int i = 0; i < 128; i++) dst[i] = hist[i] / norm;
    ok[s.index] = 1;
}

kernel void fxpanMatch(
    const device float *leftDesc [[buffer(0)]],
    const device float *leftY [[buffer(1)]],
    const device float *rightDesc [[buffer(2)]],
    const device float *rightY [[buffer(3)]],
    device uint *bestIndex [[buffer(4)]],
    device float2 *bestDist [[buffer(5)]],
    constant SiftMatchIn &u [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= u.nR) return;
    float qy = rightY[gid];
    const device float *q = rightDesc + gid * 128;
    float best = 1e30f;
    float second = 1e30f;
    uint who = 0xffffffffu;
    for (uint i = 0; i < u.nL; i++) {
        if (fabs(leftY[i] - qy) > u.gate) continue;
        const device float *c = leftDesc + i * 128;
        float s = 0.0f;
        for (uint k = 0; k < 128; k++) {
            float d = q[k] - c[k];
            s += d * d;
        }
        if (s < best) {
            second = best;
            best = s;
            who = i;
        } else if (s < second) {
            second = s;
        }
    }
    bestIndex[gid] = who;
    bestDist[gid] = float2(best, second);
}
