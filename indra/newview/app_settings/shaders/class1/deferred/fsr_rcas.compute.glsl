
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
#define SAMPLE_RCAS 1

#if SAMPLE_SLOW_FALLBACK
    layout(binding=1) uniform sampler2D InputTexture;
    layout(binding=2,rgba16f) uniform highp writeonly image2D OutputTexture;

    #if SAMPLE_RCAS
        #define FSR_RCAS_F 1
        AF4 FsrRcasLoadF(ASU2 p) { return texelFetch(InputTexture, ASU2(p), 0); }
        void FsrRcasInputF(inout AF1 r, inout AF1 g, inout AF1 b) {}
    #endif
#else
    #define A_HALF
    layout(binding=1) uniform texture2D InputTexture;
    layout(binding=2,rgba16f) uniform image2D OutputTexture;
    layout(binding=3) uniform sampler InputSampler;
    #if SAMPLE_RCAS
        #define FSR_RCAS_H
        AH4 FsrRcasLoadH(ASW2 p) { return AH4(texelFetch(sampler2D(InputTexture,InputSampler), ASU2(p), 0)); }
        void FsrRcasInputH(inout AH1 r,inout AH1 g,inout AH1 b){}
    #endif
#endif

#include "ffx_fsr1.glsl"

void CurrFilter(AU2 pos)
{
    #if SAMPLE_SLOW_FALLBACK
        AF3 c;
        FsrRcasF(c.r, c.g, c.b, pos, Const0RCAS);
        if( Sample.x == 1u )
            c *= c;
        AF4 sam = FsrRcasLoadF(ASU2(pos));
        imageStore(OutputTexture, ASU2(pos), AF4(c, sam.a));
    #else
        AH3 c;
        FsrRcasH(c.r, c.g, c.b, pos, Const0RCAS);
        if( Sample.x == 1 )
            c *= c;
        AH4 sam = AH4(FsrRcasLoadH(ASU2(pos)));
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
