#ifndef DEFINES
#define DEFINES

#ifndef PRIMARY_MAXITER

#define PRIMARY_MAXITER 1024
#define PRIMARY_MAXDIST 500.
#define SECONDARY_MAXITER 40
#define SECONDARY_MAXDIST 40.
#define SECONDARY_MINDIST 0.01
#define SECONDARY_EPSILON 0.003
#define SECONDARY_NOFFSET 0.01

// blobs only

#define S_MARCH_EPSILON 0.1
#define S_KAPPA_FACTOR 2.
#define S_THRESHOLD 0.5
#define S_BLOB_RADIUS 8.

// Orimitive parameters

#define P_PRIMITIVE_DATA vec3(1)
#define P_REPEAT_X_NUM  3
#define P_REPEAT_Y_NUM  0
#define P_REPEAT_Z_NUM  3
#define P_REPEAT_DIST vec3(10)
#define P_PLANE_ON 1

// scene and trace

#define TRACE sdf_trace
#define SHADOW no_shadow
#define SCENE_SDF sdPrimitives
#define SCENE_BDF bdPrimitives

#endif

#endif

