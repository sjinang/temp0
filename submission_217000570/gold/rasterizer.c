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
  return a < b ? a : b;
  // END CODE HERE
}

/*
 *   Function: max
 *   Function Description: Returns the maximum value of two integers and b.
*/
int max(int a, int b)
{
  // START CODE HERE
  return a > b ? a : b;
  // END CODE HERE
}

/*
/   Function: floor_ss
/   Function Description: Returns a fixed point value rounded down to the subsample grid.
*/
int floor_ss(int val, int r_shift, int ss_w_lg2)
{
  // START CODE HERE
  if (ss_w_lg2 >= r_shift)
  	return val;
  int diff = r_shift - ss_w_lg2; //amount of bits we care about after the decimal point
  unsigned int shifter = -1; // all 1 mask
  int mask = shifter << (diff); //shift mask back-filling with zeros by diff
  return val & mask; 
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

  //determine if the triangle is back-ward facing, if so set bbox.valid to 0
  //and don't care about rest of other values
  int u_x = triangle.v[1].x - triangle.v[0].x;
  int u_y = triangle.v[1].y - triangle.v[0].y;

  int v_x = triangle.v[2].x - triangle.v[1].x;
  int v_y = triangle.v[2].y - triangle.v[1].y;

  int cross = (u_x * v_y) - (u_y * v_x);
  bool cross_valid = cross < 0; 


  // START CODE HERE
  // initialize bounding box to first vertex
  int vx_1 = triangle.v[0].x;
  int vx_2 = triangle.v[1].x;
  int vx_3 = triangle.v[2].x;
  int vy_1 = triangle.v[0].y;
  int vy_2 = triangle.v[1].y;
  int vy_3 = triangle.v[2].y;

  int ll_x = floor_ss(min(vx_3, min(vx_1, vx_2)), config.r_shift, config.ss_w_lg2);
  int ur_x = floor_ss(max(vx_3, max(vx_1, vx_2)), config.r_shift, config.ss_w_lg2);
  int ll_y = floor_ss(min(vy_3, min(vy_1, vy_2)), config.r_shift, config.ss_w_lg2);
  int ur_y = floor_ss(max(vy_3, max(vy_1, vy_2)), config.r_shift, config.ss_w_lg2);
 

  // iterate over remaining vertices

  // round down to subsample grid

  // clip to screen
  ur_x = ur_x > screen.width ? screen.width : ur_x;
  ur_y = ur_y > screen.height ? screen.height : ur_y;
  ll_x = ll_x < 0 ? 0 : ll_x;
  ll_y = ll_y < 0 ? 0 : ll_y;

  // check if bbox is valid
  bbox.valid = ur_x > 0 && ur_y > 0 && ll_x < screen.width && ll_y < screen.height && cross_valid;
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
  // shift vertices so that are at origin
  int v0_x = triangle.v[0].x - sample.x;
  int v0_y = triangle.v[0].y - sample.y;
  int v1_x = triangle.v[1].x - sample.x;
  int v1_y = triangle.v[1].y - sample.y;
  int v2_x = triangle.v[2].x - sample.x;
  int v2_y = triangle.v[2].y - sample.y;

  //develop distances
  int dist0 = (v0_x * v1_y) - (v1_x * v0_y);
  int dist1 = (v1_x * v2_y) - (v2_x * v1_y);
  int dist2 = (v2_x * v0_y) - (v0_x * v2_y);  

  //test origin is on the right side of shifted edge
  bool b0 = dist0 <= 0.0;
  bool b1 = dist1 < 0.0;
  bool b2 = dist2 <= 0.0; 

  //Triagnle min terms with backface culling
  isHit = b0 && b1 && b2; 
  // END CODE HERE

  return isHit;
}

int rasterize_triangle(Triangle triangle, ZBuff *z, Screen screen, Config config)
{
  int hit_count = 0;

  //Calculate BBox
  BoundingBox bbox = get_bounding_box(triangle, screen, config);

  if (bbox.valid){
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
