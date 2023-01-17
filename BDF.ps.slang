
#include "common.slang"
#include "SegmentTracing.slang"
#include "sdf_primitives.slang"
#include "bdf_primitives.slang"

cbuffer Camera
{
    float3 camEye;
    float4x4 camInvViewProj;
};

#ifndef PRIMARY_MAXITER
#define PRIMARY_MAXITER 1024
#endif
#ifndef PRIMARY_MAXDIST
#define PRIMARY_MAXDIST 500.
#endif
#ifndef SECONDARY_MAXITER
#define SECONDARY_MAXITER 40
#endif
#ifndef SECONDARY_MAXDIST
#define SECONDARY_MAXDIST 40.
#endif
#ifndef SECONDARY_EPSILON
#define SECONDARY_EPSILON 0.003
#endif
#ifndef SECONDARY_MINDIST
#define SECONDARY_MINDIST 0.01
#endif
#ifndef SECONDARY_NOFFSET
#define SECONDARY_NOFFSET 0.01
#endif

// bdf_trace or sdf_trace
#ifndef TRACE
#define TRACE sdf_trace
#endif
// bdf_shadow or sdf_trace or no_shadow
#ifndef SHADOW
#define SHADOW no_shadow
#endif

#ifndef SCENE_SDF
#define SCENE_SDF sdf
#endif

#ifndef SCENE_BDF
#define SCENE_BDF bdf
#endif
static const vec3 EyeStartPosition = vec3(-3, 1, 5);

////////////////////////////////////////////////////////////////////////////
//
// Image
//
////////////////////////////////////////////////////////////////////////////


//VS

float sdMeta(vec3 p, float R)
{
    float y = 1. - clamp(dot2(p) / (R * R), 0.0, 1.0);
    return -y * y * y;
}

float sdf(vec3 p)
{
    return -Object(p) / KGlobal();    
    //float d = threshold;
    //d += sdMeta(p - vec3(-1, 0, 0), 2.);
    //d += sdMeta(p - vec3(1.0, 0, 0), 2.);
    //d += sdMeta(p - vec3(0.7, 2, 0), 2.);
    //return d / 0.645;
}
float bdf(vec3 p)
{
    float d = 1e+10;
    float r = (1. - T) * radius;
    d = min(d, bdSphere(p - vec3(-radius / 2.0, 0, 0), r));
    d = min(d, bdSphere(p - vec3(radius / 2.0, 0, 0), r));
    d = min(d, bdSphere(p - vec3(radius / 3.0, radius, 0), r));
    float s = sdf(p);
    float sd = sqrt(d * d + r) - r;
    return sd < T * radius ? s : d;
}
//loat bdf(vec3 p){return sdf(p);}

float sdf2(vec3 p)
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
float bdf2(vec3 p)
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
    ret.T = SphereTracing(ray.P, ray.V, h, ret.steps, ray.Tmin, ray.Tmax, params.epsilon, params.maxiters);
    ret.flags = int(ret.T >= ray.Tmax)
              | (int(h) << 1)
              | (int(ret.steps < params.maxiters) << 2);
    return ret;
}


TraceResult their_sphere_trace(in Ray ray, in SphereTraceDesc params)
{ //wrap
    TraceResult ret;
    bool h;
    ret.T = SphereTracing(ray.P, ray.V, h, ret.steps, ray.Tmin, ray.Tmax, params.epsilon, params.maxiters);
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

void mainImageBDF(out vec4 fragColor, in vec2 fragCoord)
{
    fragColor = vec4(0);
    float tanPix = 1. / length(iResolution.xy);
    Ray ray = getCameraRay(fragCoord);

    SphereTraceDesc stDesc = { tanPix, PRIMARY_MAXITER };    
    TraceResult ret = TRACE(ray, stDesc);
    
    if (bool(ret.flags & 1))
    { // background
        vec3 p = ray.P + ray.V * ray.Tmax;
        float d = SCENE_BDF(p) - SCENE_SDF(p);
        // = log(d);
        //d = 2.*atan(d);
        //fragColor.rgb += vec3(d,d,d*2.);
    }
    else if (bool(ret.flags & 2))
    { // shading
        vec3 p = ray.P + ray.V * ret.T;
        vec3 n = normal(p);
        fragColor.rgb += mix(vec3(.03, .04, .01), vec3(.04, .1, .2), 0.5 + 0.5 * p.y);
        for (float t = 0.; t < 2. * pi; t += 2. * pi / 3.)
        { // lights
            vec3 l = sqrt(.5) * vec3(cos(t), 1, sin(t));
            Ray shadowRay = { p + SECONDARY_NOFFSET * n, SECONDARY_MINDIST, l, SECONDARY_MAXDIST };
            SphereTraceDesc shadowDesc = { SECONDARY_EPSILON, SECONDARY_MAXITER };
            TraceResult sh = SHADOW(shadowRay, shadowDesc);
            fragColor.rgb += float((sh.flags & 1) != 0) * max(dot(n, l), 0.) * .5 * (1. + l.xyz); //
        }
    }
    else if (bool(ret.flags & 4))
    { //
        fragColor.rgb += vec3(1, 0, 0);
    }
    fragColor.rgb = Uncharted2ToneMapping(fragColor.rgb);
}

float4 main(noperspective float2 texC : TEXCOORD) : SV_TARGET
{
    float4 col;
    mainImageBDF(col, texC * iResolution);
    return col;
}
