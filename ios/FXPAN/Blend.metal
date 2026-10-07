#include <metal_stdlib>
using namespace metal;

/// The 5×5 pyramid kernel, edge-extended, matching the CPU convolution.
/// [1 4 6 4 1] / 16, applied as a square, then an optional gain.

constant float kBlend[5] = { 1.0f / 16.0f, 4.0f / 16.0f, 6.0f / 16.0f, 4.0f / 16.0f, 1.0f / 16.0f };

kernel void fxpanBlur5(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float &gain [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    int lastX = int(w) - 1;
    int lastY = int(h) - 1;
    float sum = 0.0f;
    for (int dy = -2; dy <= 2; dy++) {
        int y = clamp(int(gid.y) + dy, 0, lastY);
        float ky = kBlend[dy + 2];
        for (int dx = -2; dx <= 2; dx++) {
            int x = clamp(int(gid.x) + dx, 0, lastX);
            sum += src.read(uint2(uint(x), uint(y))).r * ky * kBlend[dx + 2];
        }
    }
    dst.write(float4(sum * gain, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanTakeEven(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    uint sx = min(gid.x * 2u, src.get_width() - 1u);
    uint sy = min(gid.y * 2u, src.get_height() - 1u);
    dst.write(float4(src.read(uint2(sx, sy)).r, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanExpand(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float v = 0.0f;
    if ((gid.x & 1u) == 0u && (gid.y & 1u) == 0u) {
        uint sx = gid.x >> 1;
        uint sy = gid.y >> 1;
        if (sx < src.get_width() && sy < src.get_height()) v = src.read(uint2(sx, sy)).r;
    }
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanSub(
    texture2d<float, access::read> a [[texture(0)]],
    texture2d<float, access::read> b [[texture(1)]],
    texture2d<float, access::write> dst [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float v = a.read(gid).r - b.read(gid).r;
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanAdd(
    texture2d<float, access::read> a [[texture(0)]],
    texture2d<float, access::read> b [[texture(1)]],
    texture2d<float, access::write> dst [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float v = a.read(gid).r + b.read(gid).r;
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanMask(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::read> mask [[texture(1)]],
    texture2d<float, access::write> dst [[texture(2)]],
    constant uint &invert [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float m = clamp(mask.read(gid).r, 0.0f, 1.0f);
    float w = invert != 0u ? (1.0f - m) : m;
    dst.write(float4(src.read(gid).r * w, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanExtract(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant uint &channel [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float4 p = src.read(gid);
    int a = int(round(p.a * 255.0f));
    float v = -1.0f;
    if (a > 32) {
        float c = channel == 0u ? p.r : (channel == 1u ? p.g : p.b);
        v = c * 255.0f;
    }
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

kernel void fxpanFillH(
    texture2d<float, access::read_write> img [[texture(0)]],
    uint gid [[thread_position_in_grid]]
) {
    uint w = img.get_width();
    uint h = img.get_height();
    if (gid >= h) return;
    float carry = -1.0f;
    for (uint x = 0; x < w; x++) {
        float v = img.read(uint2(x, gid)).r;
        if (v >= 0.0f) carry = v;
        else if (carry >= 0.0f) {
            v = carry;
            img.write(float4(v, 0.0f, 0.0f, 0.0f), uint2(x, gid));
        }
    }
    carry = -1.0f;
    for (int x = int(w) - 1; x >= 0; x--) {
        float v = img.read(uint2(uint(x), gid)).r;
        if (v >= 0.0f) carry = v;
        else if (carry >= 0.0f) img.write(float4(carry, 0.0f, 0.0f, 0.0f), uint2(uint(x), gid));
    }
}

kernel void fxpanFillV(
    texture2d<float, access::read_write> img [[texture(0)]],
    uint gid [[thread_position_in_grid]]
) {
    uint w = img.get_width();
    uint h = img.get_height();
    if (gid >= w) return;
    float carry = -1.0f;
    for (uint y = 0; y < h; y++) {
        float v = img.read(uint2(gid, y)).r;
        if (v >= 0.0f) carry = v;
        else if (carry >= 0.0f) img.write(float4(carry, 0.0f, 0.0f, 0.0f), uint2(gid, y));
    }
    carry = -1.0f;
    for (int y = int(h) - 1; y >= 0; y--) {
        float v = img.read(uint2(gid, uint(y))).r;
        if (v >= 0.0f) carry = v;
        else if (carry >= 0.0f) img.write(float4(carry, 0.0f, 0.0f, 0.0f), uint2(gid, uint(y)));
    }
}

kernel void fxpanFloor(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float v = src.read(gid).r;
    if (v < 0.0f) v = 0.0f;
    dst.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

struct BlendPack {
    uint channel;
    uint w;
    uint h;
    uint pad;
};

kernel void fxpanPack(
    texture2d<float, access::read> r [[texture(0)]],
    texture2d<float, access::read> t [[texture(1)]],
    texture2d<float, access::read> blended [[texture(2)]],
    device uchar4 *out [[buffer(0)]],
    constant BlendPack &u [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= u.w || gid.y >= u.h) return;
    float4 pr = r.read(gid);
    float4 pt = t.read(gid);
    int ra = int(round(pr.a * 255.0f));
    int ta = int(round(pt.a * 255.0f));
    bool hasR = ra > 32;
    bool hasT = ta > 32;
    float rv = (u.channel == 0u ? pr.r : (u.channel == 1u ? pr.g : pr.b)) * 255.0f;
    float tv = (u.channel == 0u ? pt.r : (u.channel == 1u ? pt.g : pt.b)) * 255.0f;
    float b = blended.read(gid).r;
    float value;
    if (hasR && hasT) value = min(max(rv, tv), max(min(rv, tv), b));
    else if (hasR) value = rv;
    else if (hasT) value = tv;
    else value = b;
    uint i = gid.y * u.w + gid.x;
    uchar4 p = out[i];
    uchar byte = uchar(clamp(round(value), 0.0f, 255.0f));
    if (u.channel == 0u) p.r = byte;
    else if (u.channel == 1u) p.g = byte;
    else {
        p.b = byte;
        p.a = (hasR || hasT) ? 255 : 0;
    }
    out[i] = p;
}

kernel void fxpanBalance(
    texture2d<float, access::read_write> img [[texture(0)]],
    device const float *scale [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = img.get_width();
    uint h = img.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float4 p = img.read(gid);
    if (int(round(p.a * 255.0f)) <= 32) return;
    float3 s = float3(scale[gid.y * 3u], scale[gid.y * 3u + 1u], scale[gid.y * 3u + 2u]);
    float3 v = p.rgb * 255.0f;
    float3 o = v;
    for (int c = 0; c < 3; c++) {
        if (s[c] < 0.999f) {
            float n = v[c] * s[c];
            if (n < v[c]) o[c] = round(n);
        }
    }
    p.rgb = o / 255.0f;
    img.write(p, gid);
}
