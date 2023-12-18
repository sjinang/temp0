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
  return (a > b) ? b : a;
  // END CODE HERE
}

/*
 *   Function: max
 *   Function Description: Returns the maximum value of two integers and b.
*/
int max(int a, int b)
{
  // START CODE HERE
  return (a > b) ? a : b;
  // END CODE HERE
}

/*
/   Function: floor_ss
/   Function Description: Returns a fixed point value rounded down to the subsample grid.
*/
int floor_ss(int val, int r_shift, int ss_w_lg2)
{
  // START CODE HERE
  int disBetween2Subsample = (1 << r_shift) >> ss_w_lg2; //express the distance between 2 subsamples as a fixed point num
  int delta = val % disBetween2Subsample; //compute the distance between the nearest lower subsample coordinate

  return (val - delta); //return the round down value
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
  int ll_x, ll_y, ur_x, ur_y;
  bool validBox;
  // initialize bounding box to first vertex
  ll_x = triangle.v[0].x; //initialize lower left as vertex 0
  ll_y = triangle.v[0].y;

  ur_x = triangle.v[0].x; //initialize upper right as vertex 0
  ur_y = triangle.v[0].y;
 
  // iterate over remaining vertices
  //ll_x
  ll_x = min(ll_x, triangle.v[1].x); //assign the ll_x to be the smallest x corrdinate
  ll_x = min(ll_x, triangle.v[2].x);

  //ll_y
  ll_y = min(ll_y, triangle.v[1].y); //assign the ll_y to be the smallest y corrdinate
  ll_y = min(ll_y, triangle.v[2].y);

  //ur_x
  ur_x = max(ur_x, triangle.v[1].x); //assign the ur_x to be the largest x corrdinate
  ur_x = max(ur_x, triangle.v[2].x);

  //ur_y
  ur_y = max(ur_y, triangle.v[1].y); //assign the ur_y to be the largest y corrdinate
  ur_y = max(ur_y, triangle.v[2].y);

  // round down to subsample grid
  ll_x = floor_ss(ll_x, config.r_shift, config.ss_w_lg2);
  ll_y = floor_ss(ll_y, config.r_shift, config.ss_w_lg2);
  ur_x = floor_ss(ur_x, config.r_shift, config.ss_w_lg2);
  ur_y = floor_ss(ur_y, config.r_shift, config.ss_w_lg2);

  // clip to screen
  ll_x = ll_x < 0 ? 0 : ll_x;
  ll_y = ll_y < 0 ? 0 : ll_y;
  ur_x = ur_x > screen.width ? screen.width : ur_x;
  ur_y = ur_y > screen.height ? screen.height : ur_y;

  // check if bbox is valid
  //if the box does not have width/height, is invalid
  validBox = true;
  validBox = (ll_x > ur_x) ? false : validBox;
  validBox = (ll_y > ur_y) ? false : validBox;

  //check if it is backfacing
  bool backfacing = (triangle.v[1].x - triangle.v[0].x) * (triangle.v[2].y - triangle.v[1].y)
                    - (triangle.v[2].x - triangle.v[1].x) * (triangle.v[1].y - triangle.v[0].y) > 0;
  // bbox is invalid if backfacig = true 
  validBox = !backfacing && validBox;
  // if(triangle.v[0].x==0x042bdc && triangle.v[0].y == 0x053b77 && triangle.v[0].z == 0xe926c7 && triangle.v[1].x == 0x042b53 && triangle.v[1].y == 0x053f3c && triangle.v[1].z == 0xe926c7){
  //   printf("llx:%d urx%d, valid:%d\n", ll_x, ur_x, validBox);
  // }

  bbox.lower_left.x = ll_x;
  bbox.lower_left.y = ll_y;
  bbox.upper_right.x = ur_x;
  bbox.upper_right.y = ur_y;
  bbox.valid = validBox;

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
  //for each edge, compute edgeTest = (x1-x)(y2-y)-(x2-x)(y1-y)
  //if edgeTest < 0, to the right of the edge
  int x1, y1, x2, y2, x, y;
  int edgeTest;

  //initialize x y as the sample corrdinate
  x = sample.x;
  y = sample.y;

  //edge v0->v1
  x1 = triangle.v[0].x;
  y1 = triangle.v[0].y;
  x2 = triangle.v[1].x;
  y2 = triangle.v[1].y;

  edgeTest = (x1 - x) * (y2 - y) - (x2 - x) * (y1 - y);
  if(edgeTest > 0){
    //on the edge or to the left
    return false;
  }

  //edge v1->v2
  x1 = triangle.v[1].x;
  y1 = triangle.v[1].y;
  x2 = triangle.v[2].x;
  y2 = triangle.v[2].y;

  edgeTest = (x1-x)*(y2-y)-(x2-x)*(y1-y);
  if(edgeTest >= 0){
    //on the edge or to the left
    return false;
  }

  //edge v2->v0
  x1 = triangle.v[2].x;
  y1 = triangle.v[2].y;
  x2 = triangle.v[0].x;
  y2 = triangle.v[0].y;

  edgeTest = (x1-x)*(y2-y)-(x2-x)*(y1-y);
  if(edgeTest > 0){
    //on the edge or to the left
    return false;
  }

  isHit = true;

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

      // if(sample.x==273152 && sample.y==343040 && triangle.v[0].R==1528){
      //   printf("v0x: %#08x, x0y: %#08x, x0z: %#08x, v1x: %#08x, x1y: %#08x, x1z: %#08x, r: %d , hit:%d \n", triangle.v[0].x, triangle.v[0].y, triangle.v[0].z, triangle.v[1].x, triangle.v[1].y, triangle.v[1].z, triangle.v[0].R, hit);
      //   printf("v2x: %#08x, x2y: %#08x, x2z: %#08x\n", triangle.v[2].x, triangle.v[2].y, triangle.v[2].z);
      //   printf("llx:%d urx:%d \n", bbox.lower_left.x, bbox.upper_right.x);
      // }

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
