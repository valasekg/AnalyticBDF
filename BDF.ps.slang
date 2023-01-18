#include "glsl_to_hlsl.slang"
#include "defines.slang"
#include "common.slang"
#include "SegmentTracing.slang"
#include "sdf_primitives.slang"
#include "bdf_primitives.slang"

cbuffer Camera
{
    float3 camEye;
    float4x4 camInvViewProj;
};


////////////////////////////////////////////////////////////////////////////
//
// Image
//
////////////////////////////////////////////////////////////////////////////

float sdMeta(vec3 p, float R) // optimized Vertex (unused)
{
    float y = 1. - clamp(dot2(p) / (R * R), 0.0, 1.0);
    return -y * y * y;
}

float sdBlobs(vec3 p)
{
    return -Object(p) / KGlobal();
    //float d = threshold;
    //d += sdMeta(p - vec3(-1, 0, 0), 2.);
    //d += sdMeta(p - vec3(1.0, 0, 0), 2.);
    //d += sdMeta(p - vec3(0.7, 2, 0), 2.);
    //return d / 0.645;
}
float bdBlobs(vec3 p)
{
    float d = 1e+10;
    float r = (1. - T) * radius;
    d = min(d, bdSphere(p - vec3(-radius / 2.0, 0, 0), r));
    d = min(d, bdSphere(p - vec3(radius / 2.0, 0, 0), r));
    d = min(d, bdSphere(p - vec3(radius / 3.0, radius, 0), r));
    float s = sdBlobs(p);
    float sd = sqrt(d * d + r) - r;
    return sd < T * radius ? s : d;
}
//loat bdf(vec3 p){return sdf(p);}

float sdPrimitives(vec3 p)
{
    float d = 1e+10;
    //p.xz = REP(p.xz,20.);
    d = min(d, sdBox(p, vec3(1)));
    d = min(d, sdSphere(p + vec3(-3, 0, 0), 1.4));
    d = min(d, sdCone(p + vec3(3, 0, 0), .3));
    d = min(d, sdCylinder(p + vec3(0, 0, -4), 1.5, 1.));
    d = min(d, sdTorus(p + vec3(0, 0, +4), vec2(1, .5)));
    d = min(d, sdPlane(p - vec3(0, -2, 0), vec3(0, 1, 0)));
    return d;
}
float bdPrimitives(vec3 p)
{
    float d = 1e+10;
    //p.xz = REP(p.xz,20.);
    d = min(d, bdBox(p, vec3(1)));
    d = min(d, bdSphere(p + vec3(-3, 0, 0), 1.4));
    d = min(d, bdCone(p + vec3(3, 0, 0), .3));
    d = min(d, bdCylinder(p + vec3(0, 0, -4), 1.5, 1.));
    d = min(d, bdTorus(p + vec3(0, 0, +4), vec2(1, .5)));
    d = min(d, bdPlane(p - vec3(0, -2, 0), vec3(0, 1, 0)));
    return d;
}

vec3 repetition(vec3 p)
{
#if P_REPEAT_X_NUM
    p.x = REPLIM(p.x, P_REPEAT_DIST.x, float(P_REPEAT_X_NUM));
#endif
#if P_REPEAT_Y_NUM
    p.y = REPLIM(p.y, P_REPEAT_DIST.y, float(P_REPEAT_Y_NUM));
#endif
#if P_REPEAT_Z_NUM
    p.z = REPLIM(p.z, P_REPEAT_DIST.z, float(P_REPEAT_Z_NUM));
#endif
    return p;
}
float sdPlaneAdd(float d, vec3 p)
{
#if P_PLANE_ON
    return min(d, sdPlane(p + vec3(0, P_PRIMITIVE_DATA.y, 0), vec3(0, 1, 0)));
#else
    return d;
#endif
}
float bdPlaneAdd(float d, vec3 p)
{
#if P_PLANE_ON
    return min(d, bdPlane(p + vec3(0, P_PRIMITIVE_DATA.y, 0), vec3(0, 1, 0)));
#else
    return d;
#endif
}

float sdSphere(vec3 p)
{
    return sdPlaneAdd(sdSphere(repetition(p), P_PRIMITIVE_DATA.y), p);
}
float sdBox(vec3 p)
{
    return sdPlaneAdd(sdBox(repetition(p), P_PRIMITIVE_DATA.xyz), p);
}
float sdCylinder(vec3 p)
{
    return sdPlaneAdd(sdCylinder(repetition(p), P_PRIMITIVE_DATA.x, P_PRIMITIVE_DATA.y), p);
}
float sdTorus(vec3 p)
{
    return sdPlaneAdd(sdTorus(repetition(p), P_PRIMITIVE_DATA.xy), p);
}
float bdSphere(vec3 p)
{
    return bdPlaneAdd(bdSphere(repetition(p), P_PRIMITIVE_DATA.y), p);
}
float bdBox(vec3 p)
{
    return bdPlaneAdd(bdBox(repetition(p), P_PRIMITIVE_DATA.xyz), p);
}
float bdCylinder(vec3 p)
{
    return bdPlaneAdd(bdCylinder(repetition(p), P_PRIMITIVE_DATA.x, P_PRIMITIVE_DATA.y), p);
}
float bdTorus(vec3 p)
{
    return bdPlaneAdd(bdTorus(repetition(p), P_PRIMITIVE_DATA.xy), p);
}

vec3 normal(const in vec3 p)
{
    const vec2 eps0 = vec2(0.01, 0);
    return normalize(vec3(SCENE_SDF(p + eps0.xyy), SCENE_SDF(p + eps0.yxy), SCENE_SDF(p + eps0.yyx)) -
                     vec3(SCENE_SDF(p - eps0.xyy), SCENE_SDF(p - eps0.yxy), SCENE_SDF(p - eps0.yyx)));
}

TraceResult sdf_trace(in Ray ray, in SphereTraceDesc params)
{
    TraceResult ret = { ray.Tmin, 0, 0 };
    float d;
    do
    {
        d = SCENE_SDF(ray.P + ret.T * ray.V);
        ret.T += d;
        ++ret.steps;
    } while (ret.T < ray.Tmax && // Stay within bound box
              abs(d) > params.epsilon * ret.T && // Stop if cone is close to surface
              ret.steps < params.maxiters	      // Stop if too many iterations
    );
    ret.flags = int(ret.T >= ray.Tmax)
              | (int(abs(d) <= params.epsilon * ret.T) << 1)
              | (int(ret.steps >= params.maxiters) << 2);
    return ret;
}
TraceResult bdf_trace(in Ray ray, in SphereTraceDesc params)
{
    TraceResult ret = { ray.Tmin, 0, 0 };
    float d;
    do
    {
        d = SCENE_BDF(ray.P + ret.T * ray.V);
        ret.T += 0.99 * d;
        ++ret.steps;
    } while (ret.T < ray.Tmax && // Stay within bound box
              abs(d) > params.epsilon * ret.T && // Stop if cone is close to surface
              ret.steps < params.maxiters	      // Stop if too many iterations
    );
    ret.flags = int(ret.T >= ray.Tmax)
              | (int(abs(d) <= params.epsilon * ret.T) << 1)
              | (int(ret.steps >= params.maxiters) << 2);
    return ret;
}
TraceResult segment_trace(in Ray ray, in SphereTraceDesc params)
{   //wrap
    TraceResult ret;
    bool h;
    ret.T = SegmentTracing(ray.P, ray.V, h, ret.steps, ray.Tmin, ray.Tmax, S_MARCH_EPSILON, params.maxiters);
    ret.flags = int(ret.T >= ray.Tmax)
              | (int(h) << 1)
              | (int(ret.steps < params.maxiters) << 2);
    return ret;
}


TraceResult their_sphere_trace(in Ray ray, in SphereTraceDesc params)
{ //wrap
    TraceResult ret;
    bool h;
    ret.T = SphereTracing(ray.P, ray.V, h, ret.steps, ray.Tmin, ray.Tmax, S_MARCH_EPSILON, params.maxiters);
    ret.flags = int(ret.T >= ray.Tmax)
              | (int(h) << 1)
              | (int(ret.steps < params.maxiters) << 2);
    return ret;
}

TraceResult bdf_shadow(in Ray ray, in SphereTraceDesc params)
{
    TraceResult ret = { ray.Tmin, 0, 0 };
    float d;
    do
    {
        d = SCENE_BDF(ray.P + ret.T * ray.V);
        ret.T += 0.99 * d;
        ++ret.steps;
    } while (ret.T < ray.Tmax && // Stay within bound box
              d > params.epsilon * ret.T && // Stop if cone is close to surface
              ret.steps < params.maxiters	      // Stop if too many iterations
    );
    ret.flags = int(ret.T >= ray.Tmax)
              | (int(abs(d) <= params.epsilon * ret.T) << 1)
              | (int(ret.steps >= params.maxiters) << 2);
    return ret;
}
TraceResult no_shadow(in Ray ray, in SphereTraceDesc program)
{
    TraceResult res = { ray.Tmax, 1, 0 };
    return res;
}

Ray getCameraRay(vec2 fragCoord)
{
    vec2 px = (2. * fragCoord - iResolution.xy) / iResolution.xy * float2(1, -1);
    float4 far = mul(float4(px, 1, 1), camInvViewProj);
    float4 near = mul(float4(px, 0, 1), camInvViewProj);
    float3 dir = normalize(far.xyz/far.w - near.xyz/near.w);
    Ray res = { camEye, 0.00, dir, PRIMARY_MAXDIST };
    return res;
}

float3 itershadeOld(float val)
{
    return lerp(float3(0, 1, 0), lerp(float3(1, 1, 0) * .95, float3(1, 0, 0), saturate(2 * val - 1)), saturate(2 * val));
}
float3 itershadeHSV(float v)
{
    return hsv2rgb(vec3(v, 1, 1));
}
float3 itershade2(float v)
{
    return mix(V_COLOR_A, V_COLOR_B, v);
}
float3 itershade3(float v)
{
    vec3 a = v < .5 ? V_COLOR_A : V_COLOR_B;
    vec3 b = v < .5 ? V_COLOR_B : V_COLOR_C;
    v = v < .5 ? 2. * v : 2.*v-1.;
    return mix(a, b, v);
}

void mainImageBDF(out vec4 fragColor, in vec2 fragCoord)
{
    fragColor = vec4(0);
    float tanPix = 1. / length(iResolution.xy);
    Ray ray = getCameraRay(fragCoord);

    SphereTraceDesc stDesc = { tanPix, PRIMARY_MAXITER };    
    TraceResult ret = TRACE(ray, stDesc);
#if V_COLORING == 1
    fragColor.rgb = V_COLORING_FUNC(float(ret.steps)/float(PRIMARY_MAXITER));
#else
    if (bool(ret.flags & 1))
    { // background
        fragColor.rgb += mix(vec3(111,78,55), vec3(135,206,235), ray.V.y*.5+.5)/255.0;
    }
    else if (bool(ret.flags & 2))
    { // shading
        vec3 p = ray.P + ray.V * ret.T;
        vec3 n = normal(p);
        fragColor.rgb += mix(vec3(.03, .04, .01), vec3(.04, .1, .2), 0.5 + 0.5 * p.y);
        int sh_steps = 0;
        for (float t = 0.; t < 2. * pi; t += 2. * pi / 3.)
        { // lights
            vec3 l = sqrt(.5) * vec3(cos(t), 1, sin(t));
            float minstep = tanPix * ret.T;
            Ray shadowRay = { p + (SECONDARY_NOFFSET + minstep) * n, SECONDARY_MINDIST + minstep, l, SECONDARY_MAXDIST };
            SphereTraceDesc shadowDesc = { SECONDARY_EPSILON, SECONDARY_MAXITER };
            TraceResult sh = SHADOW(shadowRay, shadowDesc);
            sh_steps += sh.steps;
#if V_COLORING != 2       
            fragColor.rgb += float((sh.flags & 1) != 0) * max(dot(n, l), 0.) * .5 * (1. + l.xyz); //
#endif
        }
        fragColor.rgb = Uncharted2ToneMapping(fragColor.rgb);
#if V_COLORING == 2
        fragColor.rgb = V_COLORING_FUNC(float(sh_steps) / float(3*SECONDARY_MAXITER));
#endif
    }
    else if (bool(ret.flags & 4))
    { //
        fragColor.rgb = vec3(1, 0, 0);
    }

#endif
}

float4 main(noperspective float2 texC : TEXCOORD) : SV_TARGET
{
    float4 col;
#if V_COLORING != 3
    mainImageBDF(col, texC*iResolution);
#else
    mainImage(col, texC*iResolution);
#endif
#if V_COLORING == 1 || V_COLORING == 2
    if (texC.x > 1-0.01)
    {
        col.rgb = V_COLORING_FUNC(1.-texC.y);
    }
#endif
    return col;
}
