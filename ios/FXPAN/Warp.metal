#include <metal_stdlib>
using namespace metal;

struct FXPANWarp {
    uint sw;
    uint sh;
    uint cw;
    uint ch;
    float x0;
    float y0;
    float a;
    float b;
    float tx;
    float ty;
    uint kind;
    float seamX0;
    float seamX1;
    float refH;
    float4 stripDx0;
    float4 stripDx1;
    float stripDx8;
    float4 stripDy0;
    float4 stripDy1;
    float stripDy8;
};

inline float fxpanStripAt(float4 v0, float4 v1, float v8, int idx) {
    if (idx <= 0) return v0.x;
    if (idx == 1) return v0.y;
    if (idx == 2) return v0.z;
    if (idx == 3) return v0.w;
    if (idx == 4) return v1.x;
    if (idx == 5) return v1.y;
    if (idx == 6) return v1.z;
    if (idx == 7) return v1.w;
    return v8;
}

inline uchar fxpanByte(float v) {
    return uchar(clamp(floor(v + 0.5f), 0.0f, 255.0f));
}

/// kind 0 places R in the panorama. kind 1 inverse-maps T with the global similarity plus smooth 9-band vertical strip refinement.
kernel void fxpanWarp(
    const device uchar4 *src [[buffer(0)]],
    device uchar4 *dst [[buffer(1)]],
    constant FXPANWarp &u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= u.cw || gid.y >= u.ch) return;
    float x, y;
    if (u.kind == 0) {
        x = float(gid.x) + u.x0;
        y = float(gid.y) + u.y0;
    } else {
        float s2 = u.a * u.a + u.b * u.b;
        if (s2 < 1e-8f) {
            dst[gid.y * u.cw + gid.x] = uchar4(0);
            return;
        }
        float gx = float(gid.x);
        float gy = float(gid.y);
        float ldx = 0.0f;
        float ldy = 0.0f;
        if (u.refH > 1.0f && u.seamX1 > u.seamX0) {
            float olW = max(32.0f, u.seamX1 - u.seamX0);
            float wx = 0.0f;
            if (gx <= u.seamX1) {
                wx = 1.0f;
            } else if (gx < u.seamX1 + olW) {
                float t = (gx - u.seamX1) / olW;
                wx = 0.5f * (1.0f + cos(3.14159265f * t));
            }
            if (wx > 0.0f) {
                float pos = clamp((gy / u.refH) * 8.0f, 0.0f, 8.0f);
                int i0 = clamp(int(floor(pos)), 0, 8);
                int i1 = min(8, i0 + 1);
                float f = pos - float(i0);
                float sx0 = fxpanStripAt(u.stripDx0, u.stripDx1, u.stripDx8, i0);
                float sx1 = fxpanStripAt(u.stripDx0, u.stripDx1, u.stripDx8, i1);
                float sy0 = fxpanStripAt(u.stripDy0, u.stripDy1, u.stripDy8, i0);
                float sy1 = fxpanStripAt(u.stripDy0, u.stripDy1, u.stripDy8, i1);
                ldx = wx * mix(sx0, sx1, f);
                ldy = wx * mix(sy0, sy1, f);
            }
        }
        float dx = gx - u.tx - ldx;
        float dy = gy - u.ty - ldy;
        x = (u.a * dx + u.b * dy) / s2;
        y = (-u.b * dx + u.a * dy) / s2;
    }
    uint i = gid.y * u.cw + gid.x;
    if (x < 0.0f || y < 0.0f || x >= float(u.sw - 1) || y >= float(u.sh - 1)) {
        dst[i] = uchar4(0);
        return;
    }
    uint x0 = uint(x);
    uint y0 = uint(y);
    float fx = x - float(x0);
    float fy = y - float(y0);
    float ifx = 1.0f - fx;
    float ify = 1.0f - fy;
    uint w = u.sw;
    uchar4 p00 = src[y0 * w + x0];
    uchar4 p10 = src[y0 * w + x0 + 1];
    uchar4 p01 = src[(y0 + 1) * w + x0];
    uchar4 p11 = src[(y0 + 1) * w + x0 + 1];
    float4 c = ifx * ify * float4(p00) + fx * ify * float4(p10) + ifx * fy * float4(p01) + fx * fy * float4(p11);
    dst[i] = uchar4(fxpanByte(c.r), fxpanByte(c.g), fxpanByte(c.b), 255);
}
