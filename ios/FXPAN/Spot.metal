#include <metal_stdlib>
using namespace metal;

/// 512-point FFT along each row of a batched tile. vDSP's forward transform uses a positive exponent, so `sign` is +1 forward and -1 inverse.
/// One threadgroup is one row. The result is ordered, and the inverse is scaled by the caller.

constant uint kN = 512u;

kernel void spotFFTRows(
    device float2 *data [[buffer(0)]],
    constant int &sign [[buffer(1)]],
    uint lane [[thread_index_in_threadgroup]],
    uint row [[threadgroup_position_in_grid]]
) {
    threadgroup float2 buf0[512];
    threadgroup float2 buf1[512];
    uint rev = reverse_bits(lane) >> 23u;
    buf0[rev] = data[row * kN + lane];
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint s = 1u; s <= 9u; s++) {
        uint m = 1u << s;
        uint mh = m >> 1u;
        uint mask = m - 1u;
        bool odd = (s & 1u) == 1u;
        if ((lane & mask) < mh) {
            uint j = lane & (mh - 1u);
            uint i0 = (lane & ~mask) + j;
            uint i1 = i0 + mh;
            float ang = float(sign) * 2.0f * M_PI_F * float(j) / float(m);
            float2 w = float2(cos(ang), sin(ang));
            float2 u = odd ? buf0[i0] : buf1[i0];
            float2 v = odd ? buf0[i1] : buf1[i1];
            float2 t = float2(w.x * v.x - w.y * v.y, w.x * v.y + w.y * v.x);
            if (odd) {
                buf1[i0] = u + t;
                buf1[i1] = u - t;
            } else {
                buf0[i0] = u + t;
                buf0[i1] = u - t;
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    data[row * kN + lane] = buf1[lane];
}

kernel void spotTranspose(
    device const float2 *src [[buffer(0)]],
    device float2 *dst [[buffer(1)]],
    constant uint &tiles [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint base = gid.z * kN * kN;
    dst[base + gid.x * kN + gid.y] = src[base + gid.y * kN + gid.x];
}

kernel void spotPackReal(
    device const float *src [[buffer(0)]],
    device float2 *dst [[buffer(1)]],
    constant uint &tiles [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint i = gid.z * kN * kN + gid.y * kN + gid.x;
    dst[i] = float2(src[i], 0.0f);
}

kernel void spotTaper(
    device float *tile [[buffer(0)]],
    constant float *mean [[buffer(1)]],
    constant uint &tiles [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint e = min(min(gid.x, kN - 1u - gid.x), min(gid.y, kN - 1u - gid.y));
    if (e >= 64u) return;
    float w = 0.5f - 0.5f * cos(float(e) / 64.0f * M_PI_F);
    uint i = gid.z * kN * kN + gid.y * kN + gid.x;
    tile[i] = mean[gid.z] + (tile[i] - mean[gid.z]) * w;
}

/// conj(H) * Y, with H shared and Y packed per tile.
kernel void spotMulConjH(
    device float2 *spec [[buffer(0)]],
    device const float2 *H [[buffer(1)]],
    constant uint &tiles [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint local = gid.y * kN + gid.x;
    uint i = gid.z * kN * kN + local;
    float2 y = spec[i];
    float2 h = H[local];
    spec[i] = float2(h.x * y.x + h.y * y.y, h.x * y.y - h.y * y.x);
}

kernel void spotShrink(
    device const float *x [[buffer(0)]],
    device float *zx [[buffer(1)]],
    device float *zy [[buffer(2)]],
    constant float &threshold [[buffer(3)]],
    constant uint &tiles [[buffer(4)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint base = gid.z * kN * kN;
    uint i = base + gid.y * kN + gid.x;
    uint nx = gid.x + 1u;
    if (nx == kN) nx = 0u;
    uint ny = gid.y + 1u;
    if (ny == kN) ny = 0u;
    float c = x[i];
    float gx = x[base + gid.y * kN + nx] - c;
    float gy = x[base + ny * kN + gid.x] - c;
    float mag = sqrt(gx * gx + gy * gy);
    float s = mag > threshold ? (mag - threshold) / mag : 0.0f;
    zx[i] = gx * s;
    zy[i] = gy * s;
}

kernel void spotSolve(
    device const float2 *zx [[buffer(0)]],
    device const float2 *zy [[buffer(1)]],
    device const float2 *hy [[buffer(2)]],
    device const float2 *dx [[buffer(3)]],
    device const float2 *dy [[buffer(4)]],
    device const float *h2 [[buffer(5)]],
    device const float *d2 [[buffer(6)]],
    device float2 *out [[buffer(7)]],
    constant float &lambda [[buffer(8)]],
    constant float &beta [[buffer(9)]],
    constant uint &tiles [[buffer(10)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint local = gid.y * kN + gid.x;
    uint i = gid.z * kN * kN + local;
    float2 zxv = zx[i];
    float2 zyv = zy[i];
    float2 d = dx[local];
    float2 e = dy[local];
    float ar = d.x * zxv.x + d.y * zxv.y + e.x * zyv.x + e.y * zyv.y;
    float ai = d.x * zxv.y - d.y * zxv.x + e.x * zyv.y - e.y * zyv.x;
    float den = max(lambda * h2[local] + beta * d2[local], 1e-8f);
    float2 h = hy[i];
    out[i] = float2((lambda * h.x + beta * ar) / den, (lambda * h.y + beta * ai) / den);
}

kernel void spotTakeReal(
    device const float2 *src [[buffer(0)]],
    device float *dst [[buffer(1)]],
    constant float &scale [[buffer(2)]],
    constant uint &tiles [[buffer(3)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= kN || gid.y >= kN || gid.z >= tiles) return;
    uint i = gid.z * kN * kN + gid.y * kN + gid.x;
    dst[i] = src[i].x * scale;
}
