//  Shaders.metal
//  DcmSwift
//
//  Created by Thales on 2025/09/10.

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
    constant uint&         outComponents  [[ buffer(7) ]],
    uint                   gid            [[ thread_position_in_grid ]]
) {
    if (gid >= count) return;

    uint inBase = gid * inComponents;
    uint outBase = gid * outComponents;

    uint comp = min(inComponents, outComponents);
    for (uint c = 0; c < comp; ++c) {
        ushort src = inPixels[inBase + c];
        // Match CPU path exactly: clamp(src - winMin, 0, denom) * 255 / denom
        int val = int(src) - winMin;
        val = clamp(val, 0, int(denom));
        float y = float(val) * 255.0f / float(max(1u, denom));
        uchar v = (uchar)(y + 0.5f);
        if (invert) v = (uchar)(255 - v);
        outPixels[outBase + c] = v;
    }

    if (outComponents > 3 && comp < outComponents) {
        outPixels[outBase + 3] = 255; // opaque alpha when writing RGBA
    }
}

// MARK: - Render Pipeline Shaders

// Vertex shader for full-screen quad
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                            constant float4* vertices [[buffer(0)]]) {
    VertexOut out;
    out.position = vertices[vertexID];
    out.texCoord = vertices[vertexID].xy * 0.5 + 0.5; // Convert to 0-1 range
    return out;
}

// Parameters struct for window/level shader
struct WLParams {
    float windowCenter;
    float windowWidth;
    float rescaleSlope;
    float rescaleIntercept;
    bool inverted;
    float imageWidth;
    float imageHeight;
};

// Fragment shader for window/level with 16-bit input
fragment float4 fragment_wl(VertexOut in [[stage_in]],
                           texture2d<ushort> sourceTexture [[texture(0)]],
                           constant WLParams& params [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texCoord = in.texCoord;
    ushort rawValue = sourceTexture.sample(textureSampler, texCoord).r;
    
    // Apply rescale: HU = raw * slope + intercept
    float hu = float(rawValue) * params.rescaleSlope + params.rescaleIntercept;
    
    // Apply window/level: normalize to 0-1 range
    float normalized = (hu - params.windowCenter + params.windowWidth * 0.5) / max(1.0, params.windowWidth);
    normalized = clamp(normalized, 0.0, 1.0);
    
    if (params.inverted) {
        normalized = 1.0 - normalized;
    }
    
    return float4(normalized, normalized, normalized, 1.0);
}

// Fragment shader for RGB passthrough (no WL applied)
fragment float4 fragment_rgb(VertexOut in [[stage_in]],
                            texture2d<float> sourceTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return sourceTexture.sample(textureSampler, in.texCoord);
}

// MARK: - Compute Shaders

// VOI LUT mapping: 16-bit input -> 8-bit output via LUT (8-bit entries)
kernel void voiLUTKernel(
    device const ushort*   inPixels       [[ buffer(0) ]],
    device const uchar*    lut8           [[ buffer(1) ]],
    device uchar*          outPixels      [[ buffer(2) ]],
    constant uint&         count          [[ buffer(3) ]],
    constant bool&         invert         [[ buffer(4) ]],
    constant uint&         inComponents   [[ buffer(5) ]],
    constant uint&         outComponents  [[ buffer(6) ]],
    uint                   gid            [[ thread_position_in_grid ]]
) {
    if (gid >= count) return;
    uint inBase = gid * inComponents;
    uint outBase = gid * outComponents;
    uint comp = min(inComponents, outComponents);
    for (uint c = 0; c < comp; ++c) {
        ushort key = inPixels[inBase + c];
        uchar v = lut8[key];
        if (invert) v = (uchar)(255 - v);
        outPixels[outBase + c] = v;
    }
    if (outComponents > 3 && comp < outComponents) {
        outPixels[outBase + 3] = 255;
    }
}
