#ifndef SDF_PRIMITIVES_SLANG
#define SDF_PRIMITIVES_SLANG

#include "glsl_to_hlsl.slang"
#include "common.slang"

// SDF primitives mostly copied from Inigo Quilez's SDF primitives https://iquilezles.org/articles/distfunctions/

float sdSphere(vec3 p, float r)
{
    return length(p) - r;
}

float sdBox(vec3 p, vec3 b)
{
    vec3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max3(d.x, d.y, d.z), 0.0);
}

float sdCylinder(vec3 p, float r) // Infinite
{
    return length(p.xz) - r;
}
float sdCylinder(vec3 p, float r, float h) // Capped
{
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdTorus(vec3 p, vec2 t) //t = vec2(R,r)
{
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdCone(vec3 p, float t)   // Infinite
{
    return (length(p.xz) - abs(p.y) * t) / sqrt(1. + t * t);
}

float sdPlane(vec3 p, vec3 n)
{
    return dot(p, n);
}

// Operations

#define REPLIM(p,c,l) ( (p) - (c) * clamp(round( (p) / (c) ),-l,l) )

//vec3 opRepLim(vec3 p, float c, in vec3 l)
//{
//    return p - c * clamp(round(p / c), -l, l);
//}
//#define REP(p,s) (fmod((p)+(s)*0.5,s)-(s)*0.5)

#endif
