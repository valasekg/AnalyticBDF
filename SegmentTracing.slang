#include "glsl_to_hlsl.slang"
#include "defines.slang"

///
///     Shadertoy source for Segment Tracing from https://www.shadertoy.com/view/WdVyDW
///         We left their code unchaned except some necessery changes to port the code.
///         Changed lines are marked with the "[changed]" text followed by a comment.
///==========================================================================================

// Shadertoy implementation of "Segment Tracing using Local Lipschitz Bounds" - Eurographics 2020
// Eric Galin, Eric Guérin, Axel Paris, Adrien Peytavie
// Paper:   https://hal.archives-ouvertes.fr/hal-02507361/document
// Video:	https://www.youtube.com/watch?v=NOinlrHyieE&feature=youtu.be
// Talk:	https://www.youtube.com/watch?v=KIOSbWNu-Ms&feature=youtu.be
// Github:  https://github.com/aparis69/Segment-Tracing
//
// Sphere tracing on the left - Segment tracing on the right.
// You can move the sliders with the mouse.
// MIT License

static const int StepsMax = PRIMARY_MAXITER; // Maximum step count for sphere & segment tracing // [changed] added UI support
static const float Epsilon = S_MARCH_EPSILON; // Marching epsilon                               // [changed] added UI support
static const float T = S_THRESHOLD; // Surface threshold.                                       // [changed] added UI support
 
static const float ra = 20.0; // Ray start interval
static const float rb = 60.0; // Ray end interval
static const float radius = S_BLOB_RADIUS; // Primitive radius                                  // [changed] added UI support
static const float kappa = S_KAPPA_FACTOR; // Segment tracing factor for next candidate segment // [changed] added UI support

// Transforms
vec3 RotateY(vec3 p, float a)
{
    float sa = sin(a);
    float ca = cos(a);
    return vec3(ca * p.x + sa * p.z, p.y, -sa * p.x + ca * p.z);
}

// Cubic falloff
// x: distance
// R: radius
float Falloff(float x, float R)
{
    float xx = clamp(x / R, 0.0, 1.0);
    float y = (1.0 - xx * xx);
    return y * y * y;
}

// Computes the global lipschitz bound of the falloff function
// e: energy
// R: radius
float FalloffK(float e, float R)
{
    return 1.72 * abs(e) / R;
}

// Computes the local lipschitz bound of the falloff function
// a: value at first bound
// b: value at second bound
// R: radius
// e: energy
float FalloffK(float a, float b, float R, float e)
{
    if (a > R)
        return 0.0;
    if (b < R / 5.0)
    {
        float t = (1.0 - b / R);
        return abs(e) * 6.0 * (sqrt(b) / R) * (t * t);
    }
    else if (a > (R * R) / 5.0)
    {
        float t = (1.0 - a / R);
        return abs(e) * 6.0 * (sqrt(a) / R) * (t * t);
    }
    else
        return FalloffK(e, R);
}

// Primitives
// Point primitive field function
// p: world point
// c: center
// R: radius
// e: energy
float Vertex(vec3 p, vec3 c, float R, float e)
{
    return e * Falloff(length(p - c), R);
}

// Evaluates the local lipschitz bound of a point primitive over a segment [a, b]
// c: center
// R: radius
// e: energy
// a: segment start
// b: segment end
float VertexKSegment(vec3 c, float R, float e, vec3 a, vec3 b)
{
    vec3 axis = normalize(b - a);
    float l = dot((c - a), axis);
    float kk = 0.0;
    if (l < 0.0)
    {
        kk = FalloffK(length(c - a), length(c - b), R, e);
    }
    else if (length(b - a) < l)
    {
        kk = FalloffK(length(c - b), length(c - a), R, e);
    }
    else
    {
        float dd = length(c - a) - (l * l);
        vec3 pc = a + axis * l;
        kk = FalloffK(dd, max(length(c - b), length(c - a)), R, e);
    }
    float grad = max(abs(dot(axis, normalize(c - a))), abs(dot(axis, normalize(c - b))));
    return kk * grad;
}

// Tree root
float Object(vec3 p)
{
    float I = Vertex(p, vec3(-radius / 2.0, 0, 0), radius, 1.0);
    I += Vertex(p, vec3(radius / 2.0, 0, 0), radius, 1.0);
    I += Vertex(p, vec3(radius / 3.0, radius, 0), radius, 1.0);
    return I - T;
}

// K root
float KSegment(vec3 a, vec3 b)
{
    float K = VertexKSegment(vec3(-radius / 2.0, 0, 0), radius, 1.0, a, b);
    K += VertexKSegment(vec3(radius / 2.0, 0, 0), radius, 1.0, a, b);
    K += VertexKSegment(vec3(radius / 3.0, radius, 0), radius, 1.0, a, b);
    return K;
}
float KGlobal()
{
    //return 0.645;
    return FalloffK(1.0, radius) * 3.0;
}

// Normal evaluation
vec3 ObjectNormal(in vec3 p)
{
    float eps = 0.001;
    float v = Object(p);
    vec3 n;
    n.x = Object(vec3(p.x + eps, p.y, p.z)) - v;
    n.y = Object(vec3(p.x, p.y + eps, p.z)) - v;
    n.z = Object(vec3(p.x, p.y, p.z + eps)) - v;
    return normalize(n);
}

// Trace ray using sphere tracing
// o : ray origin
// u : ray direction
// h : hit
// s : Number of steps
float SphereTracing(vec3 o, vec3 u, out bool h, out int s,
    float ra, float rb, float Epsilon, int StepsMax)             // [Changed] added to work with BDF code
{
    float kGlobal = KGlobal();
    float t = ra;
    h = false;
    s = 0;
    for (int i = 0; i < StepsMax; i++)
    {
        vec3 p = o + t * u;
        float v = Object(p);
        s++;

        // Hit object
        if (v > 0.0)
        {
            h = true;
            break;
        }
        
        // Move along ray
        t += max(Epsilon, abs(v) / kGlobal);
        
        // Escape marched far away
        if (t > rb)
            break;
    }
    return t;
}

float SphereTracing(vec3 o, vec3 u, out bool h, out int s)       // [Changed] to work with original code
{
    return SphereTracing(o, u, h, s, ra, rb, Epsilon, StepsMax); // [Changed] call the new signiture with the same constants
}

// Trace ray using ray marching
// o : ray origin
// u : ray direction
// h : hit
// s : Number of steps
float SegmentTracing(vec3 o, vec3 u, out bool h, out int s,
        float ra, float rb, float Epsilon, int StepsMax)         // [Changed] added to work with BDF code
{
    float t = ra;
    h = false;
    s = 0;
    float candidate = 1.0;
    for (int i = 0; i < StepsMax; i++)
    {
        s++;
        vec3 p = o + t * u;
        float v = Object(p);
        
        // Hit object
        if (v > 0.0)
        {
            h = true;
            break;
        }
        
        // Lipschitz constant on a segment
        float lipschitzSeg = KSegment(p, o + (t + candidate) * u);
        
        // Lipschitz marching distance
        float step = abs(v) / lipschitzSeg;
        
        // No further than the segment length
        step = min(step, candidate);
                     
        // But at least, Epsilon
        step = max(Epsilon, step);
        
        // Move along ray
        t += step;
        
        // Escape marched far away
        if (t > rb)
            break;
        
        candidate = kappa * step;
    }
    return t;
}

float SegmentTracing(vec3 o, vec3 u, out bool h, out int s)         // [Changed] to work with original code
{
    return SegmentTracing(o, u, h, s, ra, rb, Epsilon, StepsMax);   // [Changed] call the new signiture with the same constants
}

// Shading functions
vec3 Background(vec3 rd)
{
    const vec3 C1 = vec3(0.8, 0.8, 0.9);
    const vec3 C2 = vec3(0.6, 0.8, 1.0);
    return mix(C1, C2, rd.y * 1.0 + 0.25);
}
vec3 Shade(vec3 p, vec3 n)
{
    const vec3 l1 = normalize(vec3(-2.0, -1.0, -1.0));
    const vec3 l2 = normalize(vec3(2.0, 0.0, 1.0));
    float d1 = pow(0.5 * (1.0 + dot(n, l1)), 2.0);
    float d2 = pow(0.5 * (1.0 + dot(n, l2)), 2.0);
    return vec3(0.6) + 0.2 * (d1 + d2) * Background(n);
}
vec3 ShadeSteps(int n)
{
    const vec3 a = vec3(97, 130, 234) / vec3(255.0);
    const vec3 b = vec3(220, 94, 75) / vec3(255.0);
    const vec3 c = vec3(221, 220, 219) / vec3(255.0);
    float t = float(n) / float(StepsMax);
    if (t < 0.5)
        return mix(a, c, 2.0 * t);
    else
        return mix(c, b, 2.0 * t - 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Compute ray origin and direction
    vec2 pixel = (fragCoord.xy / iResolution.xy) * 2.0 - 1.0;
    float asp = iResolution.x / iResolution.y;
    vec3 rd = normalize(vec3(asp * pixel.x, pixel.y - 1.5, -4.0));
    vec3 ro = vec3(0.0, 18, 40.0);
    vec2 mouse = (iMouse.xy / iResolution.xy) * 2.0 - 1.0;
    if (mouse.y <= -0.9999) // show cost at frame 0
        mouse.xy = vec2(0.0);
 
    float a = (iTime * 0.25);
    ro = RotateY(ro, a);
    rd = RotateY(rd, a);
    
    // Trace ray
    bool hit; // Ray hit flag
    int s; // Number of steps
    float t; // Ray hit position
    float sep = mouse.x;
    
    // Sphere tracing on the left
    if (pixel.x < sep)
        t = SphereTracing(ro, rd, hit, s);
    // Segment tracing on the right
    else
        t = SegmentTracing(ro, rd, hit, s);

    // Shade this with object
    vec3 rgb = Background(rd);
    if (pixel.y > mouse.y)
    {
        if (hit)
        {
            vec3 pos = ro + t * rd;
            vec3 n = ObjectNormal(pos);
            rgb = Shade(pos, n);
        }
    }
    else
    {
        rgb = ShadeSteps(s);
    }
    rgb *= smoothstep(1.0, 2.0, abs(pixel.x - sep) / (2.0 / iResolution.x));
    rgb *= smoothstep(1.0, 2.0, abs(pixel.y - mouse.y) / (2.0 / iResolution.y));
    fragColor = vec4(rgb, 1.0);
}
