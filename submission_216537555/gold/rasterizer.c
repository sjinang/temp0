#include "rasterizer.h"
#include <stdlib.h>

#ifdef __cplusplus
#include <vector>
#endif

/* Utility Functions */

/*
 *   Function: min
 *  Function Description: Returns the minimum value of two integers and b.
*/
int min(int a, int b)
{
  return a<b?a:b;
}

/*
 *   Function: max
 *   Function Description: Returns the maximum value of two integers and b.
*/
int max(int a, int b)
{
  return a>b?a:b;
}

/*
/   Function: floor_ss
/   Function Description: Returns a fixed point value rounded down to the subsample grid.
*/
int floor_ss(int val, int r_shift, int ss_w_lg2)
{
  return (val >> (r_shift - ss_w_lg2)) << (r_shift - ss_w_lg2);
}

/*
 *  Function: rastBBox_bbox_fix
 *  Function Description: Determine a bounding box for the triangle.
 *  Note that this is a fixed point function.
*/
BoundingBox get_bounding_box(Triangle triangle, Screen screen, Config config)
{
  BoundingBox bbox;

  // START CODE HERE
  // initialize bounding box to first vertex
  int ll_x, ur_x, ll_y, ur_y;
  bool in_bound, back_cull;
  Vertex2D edge1, edge2;
  int angle_lg;

  // iterate over remaining vertices
  ll_x = min(triangle.v[0].x, min(triangle.v[1].x, triangle.v[2].x));
  ur_x = max(triangle.v[0].x, max(triangle.v[1].x, triangle.v[2].x));
  ll_y = min(triangle.v[0].y, min(triangle.v[1].y, triangle.v[2].y));
  ur_y = max(triangle.v[0].y, max(triangle.v[1].y, triangle.v[2].y));
  // round down to subsample grid
  ll_x = floor_ss(ll_x, config.r_shift, config.ss_w_lg2);
  ur_x = floor_ss(ur_x, config.r_shift, config.ss_w_lg2);
  ll_y = floor_ss(ll_y, config.r_shift, config.ss_w_lg2);
  ur_y = floor_ss(ur_y, config.r_shift, config.ss_w_lg2);
  // clip lower bound with 0
  ll_x = ll_x < 0 ? 0 : ll_x;
  ll_y = ll_y < 0 ? 0 : ll_y;
  // clip upper bound with width and height of screen
  ur_x = ur_x > screen.width  ? screen.width : ur_x;
  ur_y = ur_y > screen.height ? screen.height: ur_y;
  // check if bbox is valid
  edge1.x = triangle.v[1].x - triangle.v[0].x;
  edge1.y = triangle.v[1].y - triangle.v[0].y;
  edge2.x = triangle.v[2].x - triangle.v[1].x;
  edge2.y = triangle.v[2].y - triangle.v[1].y;
  angle_lg = edge1.x * edge2.y - edge2.x * edge1.y;
  back_cull = angle_lg > 0;
  in_bound =  ((ll_x <= ur_x) && (ll_y <= ur_y));
  bbox.valid =  in_bound && (!back_cull);
  // round up back to original, initialize bounding box coordinate
  bbox.lower_left.x = ll_x;
  bbox.lower_left.y = ll_y;
  bbox.upper_right.x = ur_x;
  bbox.upper_right.y = ur_y;
  // END CODE HERE
  return bbox;
}

/*
 *  Function: sample_test
 *  Function Description: Checks if sample lies inside triangle
 *
 *
 */
bool sample_test(Triangle triangle, Sample sample)
{
  bool isHit;
  Vertex2D v[3];
  int dist[3];
  bool b[3];

  // START CODE HERE
  // Shift vertices such that sample is origin
  v[0].x = triangle.v[0].x - sample.x;
  v[0].y = triangle.v[0].y - sample.y;
  v[1].x = triangle.v[1].x - sample.x;
  v[1].y = triangle.v[1].y - sample.y;
  v[2].x = triangle.v[2].x - sample.x;
  v[2].y = triangle.v[2].y - sample.y;
  // Distance of origin shifted edge
  dist[0] = v[0].x * v[1].y - v[1].x * v[0].y ; // 0 -1 edge
  dist[1] = v[1].x * v[2].y - v[2].x * v[1].y ; // 1 -2 edge
  dist[2] = v[2].x * v[0].y - v[0].x * v[2].y ; // 2 -0 edge
  // Test if origin is on right side of shifted edge(notice: edge included)
  b[0] = (dist[0] <= 0.0);
  b[1] = (dist[1] < 0.0);
  b[2] = (dist[2] <= 0.0);
  // Triangle min terms with backface culling
  isHit = b[0] && b[1] && b[2];
  // END CODE HERE

  return isHit;
}

int rasterize_triangle(Triangle triangle, ZBuff *z, Screen screen, Config config)
{
  int hit_count = 0;
  //Calculate BBox
  BoundingBox bbox = get_bounding_box(triangle, screen, config);

  //Iterate over samples and test if in triangle
  Sample sample;
  for (sample.x = bbox.lower_left.x; sample.x <= bbox.upper_right.x; sample.x += config.ss_i)
  {
    for (sample.y = bbox.lower_left.y; sample.y <= bbox.upper_right.y; sample.y += config.ss_i)
    {

      Sample jitter = jitter_sample(sample, config.ss_w_lg2);
      jitter.x = jitter.x << 2;
      jitter.y = jitter.y << 2;

      Sample jittered_sample;
      jittered_sample.x = sample.x + jitter.x;
      jittered_sample.y = sample.y + jitter.y;

      bool hit = sample_test(triangle, jittered_sample);

      if (hit)
      {
        hit_count++;
        if (z != NULL)
        {
          Sample hit_location;
          hit_location.x = sample.x >> config.r_shift;
          hit_location.y = sample.y >> config.r_shift;

          Sample subsample;
          subsample.x = (sample.x - (hit_location.x << config.r_shift)) / config.ss_i;
          subsample.y = (sample.y - (hit_location.y << config.r_shift)) / config.ss_i;

          Fragment f;
          f.z = triangle.v[0].z;
          f.R = triangle.v[0].R;
          f.G = triangle.v[0].G;
          f.B = triangle.v[0].B;

          process_fragment(z, hit_location, subsample, f);
        }
      }
    }
  }

  return hit_count;
}

void hash_40to8(uchar *arr40, ushort *val, int shift)
{
  uchar arr32[4];
  uchar arr16[2];
  uchar arr8;

  ushort mask = 0x00ff;
  mask = mask >> shift;

  arr32[0] = arr40[0] ^ arr40[1];
  arr32[1] = arr40[1] ^ arr40[2];
  arr32[2] = arr40[2] ^ arr40[3];
  arr32[3] = arr40[3] ^ arr40[4];

  arr16[0] = arr32[0] ^ arr32[2];
  arr16[1] = arr32[1] ^ arr32[3];

  arr8 = arr16[0] ^ arr16[1];

  mask = arr8 & mask;
  val[0] = mask;
}

Sample jitter_sample(const Sample sample, const int ss_w_lg2)
{
  long x = sample.x >> 4;
  long y = sample.y >> 4;
  uchar arr40_1[5];
  uchar arr40_2[5];

  long *arr40_1_ptr = (long *)arr40_1;
  long *arr40_2_ptr = (long *)arr40_2;

  ushort val_x[1];
  ushort val_y[1];

  *arr40_1_ptr = (y << 20) | x;
  *arr40_2_ptr = (x << 20) | y;

  hash_40to8(arr40_1, val_x, ss_w_lg2);
  hash_40to8(arr40_2, val_y, ss_w_lg2);

  Sample jitter;
  jitter.x = val_x[0];
  jitter.y = val_y[0];

  return jitter;
}

