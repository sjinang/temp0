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
  // START CODE HERE
  if (a < b)
  {
    return a;
  }
  else
  {
    return b;
  }
  // END CODE HERE
}

/*
 *   Function: max
 *   Function Description: Returns the maximum value of two integers and b.
*/
int max(int a, int b)
{
  // START CODE HERE
  if (a > b)
  {
    return a;
  }
  else{
    return b;
  }
  // END CODE HERE
}

/*
/   Function: floor_ss
/   Function Description: Returns a fixed point value rounded down to the subsample grid.
*/
int floor_ss(int val, int r_shift, int ss_w_lg2)
{
  // START CODE HERE
  // Assume that ss_w = 1, to round val down to the nearest subsample grid would be the same as rounding down to the nearest pixel. 
  // Thereofre, for ss_w = 1, can just shift val right by r_shift and then back left by r_shift
  // For ss_w > 1, we can first find the number of subsample grids contained in val: val/(1/ss_w) = val(ss_w)
  // Note val(ss_w) is the same as val shifted left by ss_w_lg2
  int num_ss_grid = val << ss_w_lg2;
  // Then we round the number of subsample grid to the nearest integer
  int num_ss_grid_f = (num_ss_grid >> r_shift) << r_shift;
  // Then we find the position of the last subsample grid: pos = num/ss_w = num >> ss_w_lg2
  int pos_ss_grid_f = num_ss_grid_f >> ss_w_lg2;
  
  return pos_ss_grid_f;
  // END CODE HERE
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
  int ll_x = triangle.v[0].x;
  int ll_y = triangle.v[0].y;
  int ur_x = triangle.v[0].x;
  int ur_y = triangle.v[0].y;
 
  // iterate over remaining vertices
  ll_x = min(ll_x, triangle.v[1].x);
  ll_x = min(ll_x, triangle.v[2].x);
  ll_y = min(ll_y, triangle.v[1].y);
  ll_y = min(ll_y, triangle.v[2].y);

  ur_x = max(ur_x, triangle.v[1].x);
  ur_x = max(ur_x, triangle.v[2].x);
  ur_y = max(ur_y, triangle.v[1].y);
  ur_y = max(ur_y, triangle.v[2].y);
  // round down to subsample grid
  ll_x = floor_ss(ll_x,config.r_shift,config.ss_w_lg2);
  ll_y = floor_ss(ll_y,config.r_shift,config.ss_w_lg2);
  ur_x = floor_ss(ur_x,config.r_shift,config.ss_w_lg2);
  ur_y = floor_ss(ur_y,config.r_shift,config.ss_w_lg2);
  
  // clip to screen
  ll_x = ll_x < 0? 0 : ll_x;
  ll_y = ll_y < 0? 0 : ll_y;
  ur_x = ur_x > screen.width ? screen.width : ur_x ;
  ur_y = ur_y > screen.height ? screen.height : ur_y ;

  // check if bbox is valid
  int v10_x = triangle.v[1].x - triangle.v[0].x;
  int v10_y = triangle.v[1].y - triangle.v[0].y;
  int v20_x = triangle.v[2].x - triangle.v[0].x;
  int v20_y = triangle.v[2].y - triangle.v[0].y;

  int normal_z = v10_x * v20_y - v20_x * v10_y;

  bool back_cull = (normal_z>=0);

  // If bbox is completely outside of the screen, then one the four happens:
  if (ll_x > ur_x || ll_y > ur_y || back_cull){
    bbox.valid = false;
  }
  else{
    bbox.valid = true;
  }

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

  // START CODE HERE
  // Shift vertices such that sample is in origin
  int v0_x = triangle.v[0].x - sample.x;
  int v0_y = triangle.v[0].y - sample.y;
  int v1_x = triangle.v[1].x - sample.x;
  int v1_y = triangle.v[1].y - sample.y;
  int v2_x = triangle.v[2].x - sample.x;
  int v2_y = triangle.v[2].y - sample.y;

  // Find distance of origin shifted edge
  // Although multiplication doesn't work the same with fixed point numbers, since we are comparing the difference of two products to zero, which is the same as comparing these two products themselves, it doesn't matter if the multiplication works the same or not.
  int dist0 = v0_x * v1_y - v1_x * v0_y ; // 0 -1 edge
  int dist1 = v1_x * v2_y - v2_x * v1_y ; // 1 -2 edge
  int dist2 = v2_x * v0_y - v0_x * v2_y ; // 2 -0 edge

  // Test if origin is on the right side of the shifted edge
  bool b0 = (dist0 <= 0);
  bool b1 = (dist1 < 0);
  bool b2 = (dist2 <= 0);

  // Consider only the front facing triangles (if sample is to the right of all edges)
  isHit = (b0 && b1 && b2);

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
