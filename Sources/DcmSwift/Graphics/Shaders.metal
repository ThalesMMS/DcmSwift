#include <metal_stdlib>
using namespace metal;

// Simple window/level mapping from 16-bit input to 8-bit output.
// Each thread maps one pixel. Inputs are in a 16-bit buffer; outputs in 8-bit buffer.

kernel void windowLevelKernel(
    device const ushort*   inPixels       [[ buffer(0) ]],
    device uchar*          outPixels      [[ buffer(1) ]],
    constant uint&         count          [[ buffer(2) ]],
    constant int&          winMin         [[ buffer(3) ]],
    constant uint&         denom          [[ buffer(4) ]],
    constant bool&         invert         [[ buffer(5) ]],
    constant uint&         inComponents   [[ buffer(6) ]],
    uint                   gid            [[ thread_position_in_grid ]]
) {
    if (gid >= count) return;

    uint inBase = gid * inComponents;
    uint outBase = gid * 4; // always produce RGBA (alpha filled if needed)

    for (uint c = 0; c < inComponents; ++c) {
        ushort src = inPixels[inBase + c];
        // Match CPU path exactly: clamp(src - winMin, 0, denom) * 255 / denom
        int val = int(src) - winMin;
        val = clamp(val, 0, int(denom));
        float y = float(val) * 255.0f / float(max(1u, denom));
        uchar v = (uchar)(y + 0.5f);
        if (invert) v = (uchar)(255 - v);
        outPixels[outBase + c] = v;
    }

    if (inComponents < 4) {
        outPixels[outBase + 3] = 255; // opaque alpha for RGB input
    }
}
