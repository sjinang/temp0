#include "rasterizer.h"
#include <stdlib.h>
#include <stdio.h>

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
    return (a < b ? a: b);
}

/*
 *   Function: max
 *   Function Description: Returns the maximum value of two integers and b.
*/
int max(int a, int b)
{
    return (a > b ? a: b);
}

/*
/   Function: floor_ss
/   Function Description: Returns a fixed point value rounded down to the subsample grid.
*/
int floor_ss(int val, int r_shift, int ss_w_lg2)
{
    unsigned int mask;
    if (r_shift > ss_w_lg2)
    {
        mask = (1<<(r_shift-ss_w_lg2))-1;
        val = val & (~mask);
    }
    return val;
}

bool backface_culling(Triangle triangle)
{
  bool b;
  int v01_x, v01_y, v02_x, v02_y;
  v01_x = triangle.v[1].x - triangle.v[0].x;
  v01_y = triangle.v[1].y - triangle.v[0].y; 
  v02_x = triangle.v[2].x - triangle.v[0].x;
  v02_y = triangle.v[2].y - triangle.v[0].y; 


  b = (v01_x*v02_y - v01_y*v02_x < 0);

  return b;
}

/*
 *  Function: rastBBox_bbox_fix
 *  Function Description: Determine a bounding box for the triangle.
 *  Note that this is a fixed point function.
*/
BoundingBox get_bounding_box(Triangle triangle, Screen screen, Config config)
{
  BoundingBox bbox;

  int ll_x, ll_y, ur_x, ur_y;
  
  // Do back face culling
  bbox.valid = backface_culling(triangle);
  
  ll_x = triangle.v[0].x;
  ll_y = triangle.v[0].y;
  ur_x = triangle.v[0].x;
  ur_y = triangle.v[0].y;
  
  for (int i=1; i<3; i++)
  {
    ll_x = min(triangle.v[i].x,ll_x);
    ll_y = min(triangle.v[i].y,ll_y);
    ur_x = max(triangle.v[i].x,ur_x);
    ur_y = max(triangle.v[i].y,ur_y);
  }
  
  ll_x = floor_ss(ll_x, config.r_shift, config.ss_w_lg2);
  ll_y = floor_ss(ll_y, config.r_shift, config.ss_w_lg2);
  ur_x = floor_ss(ur_x, config.r_shift, config.ss_w_lg2);
  ur_y = floor_ss(ur_y, config.r_shift, config.ss_w_lg2);
    
  // Check if bbox lies either entirely or partially inside the screen -> bbox is valid
  if (!(ur_x < 0 || ur_y < 0 || ll_x > screen.width || ll_y > screen.height))
  {   
      // clip to screen
      ur_x = ur_x > screen.width ? screen.width : ur_x ;
      ur_y = ur_y > screen.height ? screen.height : ur_y ;
      ll_x = ll_x < 0 ? 0 : ll_x ;
      ll_y = ll_y < 0 ? 0 : ll_y ;

      bbox.lower_left.x = ll_x;
      bbox.lower_left.y = ll_y;
      bbox.upper_right.x = ur_x;
      bbox.upper_right.y = ur_y;
  }
  else
  {
    bbox.valid = false;
  }

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
  bool isHit, b0, b1, b2;
  int v0_x, v0_y, v1_x, v1_y, v2_x, v2_y;
  int dist0, dist1, dist2;
  
  
  v0_x = triangle.v[0].x - sample.x;
  v0_y = triangle.v[0].y - sample.y;
  v1_x = triangle.v[1].x - sample.x;
  v1_y = triangle.v[1].y - sample.y;
  v2_x = triangle.v[2].x - sample.x;
  v2_y = triangle.v[2].y - sample.y;
  
  dist0 = v0_x * v1_y - v1_x * v0_y ; // 0 -1 edge
  dist1 = v1_x * v2_y - v2_x * v1_y ; // 1 -2 edge
  dist2 = v2_x * v0_y - v0_x * v2_y ; // 2 -0 edge
 
  // Test if origin is on right side of shifted edge
  b0 = dist0 <= 0;
  b1 = dist1 < 0;
  b2 = dist2 <= 0;
  
  // Triangle min terms with backface culling
  isHit = b0 && b1 && b2;
 
  return isHit;
}

int rasterize_triangle(Triangle triangle, ZBuff *z, Screen screen, Config config)
{
  int hit_count = 0;

  //Calculate BBox
  BoundingBox bbox = get_bounding_box(triangle, screen, config);

  if (bbox.valid)
  {
    //Iterate over samples and test if in triangle
    Sample sample;
    for (sample.x = bbox.lower_left.x; sample.x <= bbox.upper_right.x; sample.x += config.ss_i)
    {
      for (sample.y = bbox.lower_left.y; sample.y <= bbox.upper_right.y; sample.y += config.ss_i)
      {
        //printf("-");
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
