
#ifndef COMMON_SLANG
#define COMMON_SLANG

#include "glsl_to_hlsl.slang"

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

static const float pi = 3.1415926535897932384626433832795;

vec3 Uncharted2ToneMapping(vec3 color)
{ //https://www.shadertoy.com/view/lslGzl
    const float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30, W = 11.2, exposure = 1., gammainv = 1. / 2.2;
    const float white = (W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F) - E / F;
    color *= exposure;
    color = (color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F) - E / F;
    return pow(color / white, vec3(gammainv));
}

vec3 hsv2rgb(vec3 c)
{
    const vec4 K = vec4(1, 2. / 3., 1. / 3., 3);
    return c.z * mix(K.xxx, clamp(abs(fract(c.xxx + K.xyz) * 6. - K.www) - K.xxx, 0., 1.), c.y);
} //fragColor.rgb = hsv2rgb(vec3(fragCoord.x/iResolution.x,1.,fragCoord.y/iResolution.y));

float min3(float a, float b, float c)
{
    return min(min(a, b), c);
}
float min3(vec3 a)
{
    return min(a.x, min(a.y, a.z));
}

float max3(float a, float b, float c)
{
    return max(max(a, b), c);
}
float max3(vec3 a)
{
    return max(a.x, max(a.y, a.z));
}

float dot2(vec2 a)
{
    return dot(a, a);
}

float dot2(vec3 a)
{
    return dot(a, a);
}
float dot2(float a)
{
    return a*a;
}

#endif
