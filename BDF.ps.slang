/***************************************************************************
 # Copyright (c) 2015-21, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
};

cbuffer Camera
{
    float3 camEye;
    float4x4 camInvViewProj;
};

// CSABA'S STUFF

////////////////////////////////////////////////////////////////////////////
//
// Common
//
////////////////////////////////////////////////////////////////////////////

#define mix lerp
#define vec2 float2
#define vec3 float3
#define vec4 float4

struct Ray
{
    vec3 P;
    float Tmin;
    vec3 V;
    float Tmax;
};

struct SphereTraceDesc
{
    float epsilon; //Stopping distance to surface
    int maxiters; //Maximum iteration count
};

struct TraceResult
{
    float T; // Distance taken on ray
    int flags; // flags bit 0:   distance condition:     true if travelled to far t > t_max
    int steps; // flags bit 1:   surface condition:      true if distance to surface is small < error threshold
};

#define PRIMARY_MAXITER 1024
#define PRIMARY_MAXDIST 500.
#define SECONDARY_EPSILON 0.01
#define SECONDARY_MAXITER 40
#define SECONDARY_MINDIST 0.01
#define SECONDARY_MAXDIST 40.
#define SECONDARY_NOFFSET 0.01

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

static const float pi = 3.1415926535897932384626433832795;
static const vec3 EyeStartPosition = vec3(-3, 1, 5);

vec3 Uncharted2ToneMapping(vec3 color)
{ //https://www.shadertoy.com/view/lslGzl
    const float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30, W = 11.2, exposure = 1., gammainv = 1. / 2.2;
    const float white = (W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F) - E / F;
    color *= exposure;
    color = (color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F) - E / F;
    return pow(color / white, vec3(gammainv));
}

float min3(float a, float b, float c)
{
    return min(min(a, b), c);
}
float max3(float a, float b, float c)
{
    return max(max(a, b), c);
}
float dot2(vec2 a)
{
    return dot(a, a);
}
float dot2(vec3 a)
{
    return dot(a, a);
}

float sdSphere(vec3 p, float s)
{
    return length(p) - s;
}

float bdSphere(vec3 p, float s)
{
    float d2 = dot(p, p);
    return d2 > s * s ? sqrt(d2 - s * s) : sqrt(d2) - s;
}

float sdBox(vec3 p, vec3 b)
{
    vec3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max3(d.x, d.y, d.z), 0.0);
}
float bdBoxOlder(vec3 p, vec3 b)
{
    vec3 q = abs(p) - b;
    float d = min3(
        dot2(q + vec3(2. * b.x, 0, 0)),
        dot2(q + vec3(0, 2. * b.y, 0)),
        dot2(q + vec3(0, 0, 2. * b.z))
    );
    vec3 m = max(q, 0.);
    d = q.z >= 0. ? d : min(d,
            dot2(vec3(m.xy, q.z))
        );
    d = q.y >= 0. ? d : min(d,
            dot2(vec3(m.xz, q.y))
        );
    d = q.x >= 0. ? d : min(d,
            dot2(vec3(m.yz, q.x))
        );
    float s = min(max3(q.x, q.y, q.z), 0.);
    return s < 0. ? s : sqrt(d);
}
float bdBox(vec3 p, vec3 b)
{
    vec3 q = abs(p) - b;
    float d = min3(
        dot2(q + vec3(2. * b.x, 0, 0)),
        dot2(q + vec3(0, 2. * b.y, 0)),
        dot2(q + vec3(0, 0, 2. * b.z))
    );
    vec3 m2 = max(q, 0.);
    m2 *= m2;
    vec3 q2 = q * q;
    d = q.z >= 0. ? d : min(d,
            m2.x + m2.y + q2.z
        );
    d = q.y >= 0. ? d : min(d,
            m2.x + q2.y + m2.z
        );
    d = q.x >= 0. ? d : min(d,
            q2.x + m2.y + m2.z
        );
    float s = min(max3(q.x, q.y, q.z), 0.);
    return s < 0. ? s : sqrt(d);
}
float bdCylinder(vec3 p, float r)
{
    float d2 = dot(p.xz, p.xz);
    return d2 > r * r ? sqrt(d2 - r * r) : sqrt(d2) - r;
}
float sdCylinder(vec3 p, float r)
{
    return length(p.xz) - r;
}
float sdCylinder(vec3 p, float r, float h)
{
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
float bdCylinder(vec3 p, float _r, float _h)
{
    float r = length(p.xz);
    vec2 q = vec2(r, abs(p.y)) - vec2(_r, _h);
    float d = dot2(vec2(max(q.x, 0.), q.y + 2. * _h));
  
    d = q.x >= 0. && q.y >= 0. ? d : min(d,
          dot2(q)
      );
    d = q.x <= 0. ? d : min(d,
          dot2(vec2(r, max(q.y, 0.))) - _r * _r
      );
      
    float s = min(max(q.x, q.y), 0.0);
    return s < 0. ? s : sqrt(d);
}

float sdTorus(vec3 p, vec2 t) //R,r
{
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
float bdTorus(vec3 p, vec2 t) //R,r
{
    float d2 = dot2(vec2(length(p.xz) - t.x, p.y));
    return d2 <= t.y * t.y ? sqrt(d2) - t.y : sqrt(d2 - t.y * t.y);
}
float sdCone(vec3 p, float t)
{ //return sdCylinder(p,abs(t*p.y));
    return (length(p.xz) - abs(p.y) * t) / sqrt(1. + t * t);
}
float bdCone(vec3 p, float t)
{
    float r = abs(p.y) * t;
    float d2 = dot(p.xz, p.xz);
    return d2 > r * r ? sqrt(d2 - r * r) : (sqrt(d2) - r) / sqrt(1. + t * t);
}
float sdPlane(vec3 p, vec3 n)
{
    return dot(p, n);
}
float bdPlane(vec3 p, vec3 n)
{
    float d = sdPlane(p, n);
    return d < 0. ? d : 2. * d;
}

vec3 opRepLim(vec3 p, float c, in vec3 l)
{
    return p - c * clamp(round(p / c), -l, l);
}
#define REP(p,s) (mod((p)+(s)*0.5,s)-(s)*0.5)

////////////////////////////////////////////////////////////////////////////
//
// Image
//
////////////////////////////////////////////////////////////////////////////

float Falloff(float x, float R)
{
    float xx = clamp(x / R, 0.0, 1.0);
    float y = (1.0 - xx * xx);
    return y * y * y;
}
float Vertex(vec3 p, vec3 c, float R, float e)
{
    return e * Falloff(length(p - c), R);
}

//VS

float sdMeta(vec3 p, float R)
{
    float y = 1. - clamp(dot2(p) / (R * R), 0.0, 1.0);
    return -y * y * y;
}

const static float threshold = 0.8;

float sdf(vec3 p)
{
    float d = threshold;
    d += sdMeta(p - vec3(-1, 0, 0), 2.);
    d += sdMeta(p - vec3(1.0, 0, 0), 2.);
    d += sdMeta(p - vec3(0.7, 2, 0), 2.);
    return d / 0.645;
}
float bdf(vec3 p)
{
    float d = 1e+10;
    float r = (1. - threshold) * 2.;
    d = min(d, bdSphere(p - vec3(-1., 0, 0), r));
    d = min(d, bdSphere(p - vec3(1.0, 0, 0), r));
    d = min(d, bdSphere(p - vec3(0.7, 2, 0), r));
    float s = sdf(p);
    float sd = sqrt(d * d + r) - r;
    return sd < threshold * 2. ? s : d;
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

void mainImage(out vec4 fragColor, in vec2 fragCoord)
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
    mainImage(col, texC * iResolution);
    return col;
}
