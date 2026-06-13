
#extension GL_ARB_compute_shader : enable
#extension GL_ARB_shader_image_load_store : enable

layout(binding=0) uniform const_buffer
{
    uvec4 Const0;
    uvec4 Const1;
    uvec4 Const2;
    uvec4 Const3;
    uvec4 Const0RCAS;
    uvec4 Extents;
    uvec4 Sample;
};

#define A_GPU 1
#define A_GLSL 1

#include "ffx_a.glsl"

#define SAMPLE_SLOW_FALLBACK 1
#define SAMPLE_EASU 1

#if SAMPLE_SLOW_FALLBACK
    layout(binding=1) uniform sampler2D InputTexture;
    layout(binding=2,rgba16f) uniform highp writeonly image2D OutputTexture;

    #if SAMPLE_EASU
        #define FSR_EASU_F 1
        AF4 FsrEasuRF(AF2 p) { AF4 res = textureGather(InputTexture, p, 0); return res; }
        AF4 FsrEasuGF(AF2 p) { AF4 res = textureGather(InputTexture, p, 1); return res; }
        AF4 FsrEasuBF(AF2 p) { AF4 res = textureGather(InputTexture, p, 2); return res; }
    #endif
#else
    #define A_HALF
    layout(binding=1) uniform texture2D InputTexture;
    layout(binding=2,rgba16f) uniform image2D OutputTexture;
    layout(binding=3) uniform sampler InputSampler;
    #if SAMPLE_EASU
        #define FSR_EASU_H 1
        AH4 FsrEasuRH(AF2 p) { AH4 res = AH4(textureGather(sampler2D(InputTexture,InputSampler), p, 0)); return res; }
        AH4 FsrEasuGH(AF2 p) { AH4 res = AH4(textureGather(sampler2D(InputTexture,InputSampler), p, 1)); return res; }
        AH4 FsrEasuBH(AF2 p) { AH4 res = AH4(textureGather(sampler2D(InputTexture,InputSampler), p, 2)); return res; }  
    #endif
#endif

#include "ffx_fsr1.glsl"

void CurrFilter(AU2 pos)
{
    #if SAMPLE_SLOW_FALLBACK
        AF3 c;
        FsrEasuF(c, pos, Const0, Const1, Const2, Const3);
        if( Sample.x == 1u )
            c *= c;
        AF2 uv = (AF2(pos) + 0.5) / AF2(imageSize(OutputTexture));
        AF4 sam = texture(InputTexture, uv);
        imageStore(OutputTexture, ASU2(pos), AF4(c, sam.a));
    #else
        AH3 c;
        FsrEasuH(c, pos, Const0, Const1, Const2, Const3);
        if( Sample.x == 1 )
            c *= c;
        AF2 uv = (AF2(pos) + 0.5) / AF2(imageSize(OutputTexture));
        AH4 sam = AH4(texture(sampler2D(InputTexture, InputSampler), uv));
        imageStore(OutputTexture, ASU2(pos), AH4(c, sam.a));
    #endif
}

layout(local_size_x=64) in;
void main()
{
    // Do remapping of local xy in workgroup for a more PS-like swizzle pattern.
    AU2 gxy = ARmp8x8(gl_LocalInvocationID.x) + AU2(gl_WorkGroupID.x << 4u, gl_WorkGroupID.y << 4u);
    CurrFilter(gxy);
    gxy.x += 8u;
    CurrFilter(gxy);
    gxy.y += 8u;
    CurrFilter(gxy);
    gxy.x -= 8u;
    CurrFilter(gxy);
}
