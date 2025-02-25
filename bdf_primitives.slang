#ifndef BDF_PRIMITIVES_SLANG
#define BDF_PRIMITIVES_SLANG

#include "glsl_to_hlsl.slang"
#include "common.slang"

// SDF primitives mostly copied from Inigo Quilez's SDF primitives https://iquilezles.org/articles/distfunctions/

float bdSphere(vec3 p, float s)
{
    float d2 = dot2(p);
    return d2 > s * s ? sqrt(d2 - s * s) : sqrt(d2) - s;
}

float bdBoxOlder(vec3 p, vec3 b)
{
    vec3 q = abs(p) - b;
    float d = min3( //distances to the three corners
        dot2(q + vec3(2. * b.x, 0, 0)),
        dot2(q + vec3(0, 2. * b.y, 0)),
        dot2(q + vec3(0, 0, 2. * b.z))
    );
    
    vec3 m = max(q, 0.); // conditional distances to three edges:
    d = q.z >= 0. ? d : min(d,
            dot2(vec3(m.xy, q.z))
        );
    d = q.y >= 0. ? d : min(d,
            dot2(vec3(m.xz, q.y))
        );
    d = q.x >= 0. ? d : min(d,
            dot2(vec3(m.yz, q.x))
        );
    float s = max3(q.x, q.y, q.z);
    return s < 0. ? s : sqrt(d);
}

float bdBoxOldish(vec3 p, vec3 b)
{
    vec3 q = abs(p) - b;
    float d = min3( // minimum distance to face-diagonal vertices
        dot2(q + vec3(2. * b.x, 0, 0)),
        dot2(q + vec3(0, 2. * b.y, 0)),
        dot2(q + vec3(0, 0, 2. * b.z))
    );
    vec3 q2 = q * q; // conditional distances to three edges/faces
    vec3 m2 = (q >= 0.) * q2;
    //d = min(d, m2.x + m2.y + m2.z);
    d = q.z >= 0. ? d : min(d,
            m2.x + m2.y + q2.z
        );
    d = q.y >= 0. ? d : min(d,
            m2.x + q2.y + m2.z
        );
    d = q.x >= 0. ? d : min(d,
            q2.x + m2.y + m2.z
        );
    float s = max3(q.x, q.y, q.z);
    return s < 0. ? s : sqrt(d);
}

float bdBox1(vec3 p, vec3 b)
{ // optimized
    vec3 q = abs(p) - b;
    vec3 q2 = max(q, 0.) * q;
    float  d = q2.y + q2.z + dot2(q.x + (q.x < 0. ? 0. : 2. * b.x));
    d = min(d, q2.z + q2.x + dot2(q.y + (q.y < 0. ? 0. : 2. * b.y)));
    d = min(d, q2.x + q2.y + dot2(q.z + (q.z < 0. ? 0. : 2. * b.z)));
    float s = max3(q.x, q.y, q.z);
    return s < 0. ? s : sqrt(d);
}
float bdBox2(vec3 p, vec3 b)
{ // optimized
    vec3 q = abs(p) - b;
    float qq = dot2(q);
    vec3 tmp = 2. * vec3(q >= 0.) * b;
    vec3 q2 = max(q, 0.) * q;
    float  d = q2.y + q2.z + dot2(q.x + tmp.x);
    d = min(d, q2.z + q2.x + dot2(q.y + tmp.y));
    d = min(d, q2.x + q2.y + dot2(q.z + tmp.z));
    float s = max3(q.x, q.y, q.z);
    return s < 0. ? s : sqrt(d);
}

float bdBox3(vec3 p, vec3 b) { // optimized
    vec3 q = abs(p) - b;
    vec3 b2q = 2. * vec3(q > 0.) * b + q;
    vec3 q2 = max(q, 0.) * q;
    float s = max3(q);
    return s < 0. ? s : sqrt(min3(q2.yzx + q2.zxy + b2q*b2q));
}

float bdBox(vec3 p,vec3 b)
{
    return bdBox3(p, b);
}

float bdCylinder(vec3 p, float r) // Infinite
{
    float d2 = dot(p.xz, p.xz);
    return d2 > r * r ? sqrt(d2 - r * r) : sqrt(d2) - r;
}

float bdCylinder(vec3 p, float _r, float _h)
{
    float r = length(p.xz);
    vec2 q = vec2(r, abs(p.y)) - vec2(_r, _h);
    float d = dot2(vec2(max(q.x, 0.), q.y + 2. * _h));
    d = q.x >= 0. && q.y >= 0. ? d : min(d,
          .95 * dot2(q)
      );
    d = q.x <= 0. ? d : min(d,
          1.0 * (dot2(vec2(r, max(q.y, 0.))) - _r * _r)
      );
    float s = max(q.x, q.y);
    return s < 0. ? s : sqrt(d);
}

float bdTorus(vec3 p, vec2 t) //t = vec2(R,r)
{
    float d2 = dot2(vec2(length(p.xz) - t.x, p.y));
    return d2 <= t.y * t.y ? sqrt(d2) - t.y : sqrt(d2 - t.y * t.y);
}

float bdCone(vec3 p, float t) // Infinite
{
    float r = abs(p.y) * t;
    float d2 = dot(p.xz, p.xz);
    return d2 > r * r ? sqrt(d2 - r * r) : (sqrt(d2) - r) / sqrt(1. + t * t);
}

float bdPlane(vec3 p, vec3 n)
{
    float d = dot(p, n); // = sdPlane(p, n);
    return d < 0. ? d : 2. * d + 2.;
    // Technically the BDF would be infinite, but since we have to sphere trace
    // back from the inside to the ray-surface intersection, we take an arbitrary
    // value for the BDF. This is the only place where we do that.
}

#endif
