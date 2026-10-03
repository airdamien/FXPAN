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
    uint pad;
};

inline uchar fxpanByte(float v) {
    return uchar(clamp(floor(v + 0.5f), 0.0f, 255.0f));
}

/// kind 0 places R in the panorama. kind 1 inverse-maps T with the same similarity the CPU uses.
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
        float dx = float(gid.x) - u.tx;
        float dy = float(gid.y) - u.ty;
        if (s2 < 1e-8f) {
            dst[gid.y * u.cw + gid.x] = uchar4(0);
            return;
        }
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
