#include "rasterizer.h"
#include <stdlib.h>
#include <stdint.h>

#ifdef __cplusplus
#include <vector>
#endif

/* Utility Functions */

/*
 *  Function: min
 *  Function Description: Returns the minimum value of two integers and b.
 */
int min(int a, int b) { return (a < b) ? a : b; }

/*
 *   Function: max
 *   Function Description: Returns the maximum value of two integers and b.
 */
int max(int a, int b) { return (a > b) ? a : b; }

/*
/   Function: floor_ss
/   Function Description: Returns a fixed point value rounded down to the
/   subsample grid.
*/
int floor_ss(int val, int r_shift, int ss_w_lg2) {
  // The subsample grid is the "grid" on which we do triangle tests. Without
  // anti-aliasing, we would test on the grid of pixels. For anti-aliasing, we
  // divide each pixel into ss_w**2 subpixels and test on the top-left corner of
  // each of them. This grid has spacing 2**r_shift / ss_w, and we can test that
  // by setting ss_w = 1 to disable anti-aliasing.
  //
  // In essence, we'd like to round down to the nearest multiple of
  // 2**(r_shift - ss_w_lg2). This entails clearing the bottom bits of the
  // value.

  // Assume: r_shift >= ss_w_lg2
  // Return: val with the bottom r_shift - ss_w_lg2 bits cleared
  unsigned shamt = r_shift - ss_w_lg2;
  return (val >> shamt) << shamt;
}

/*
 *  Function: rastBBox_bbox_fix
 *  Function Description: Determine a bounding box for the triangle.
 *  Note that this is a fixed point function.
 */
BoundingBox get_bounding_box(Triangle triangle, Screen screen, Config config) {
  BoundingBox bbox;

  // Find the maximum and minimum coordinates over the triangle. We initialize
  // the bounding box to that of one vertex, then expand it with the other two.
  bbox.lower_left.x = triangle.v[0].x;
  bbox.lower_left.y = triangle.v[0].y;
  bbox.upper_right.x = triangle.v[0].x;
  bbox.upper_right.y = triangle.v[0].y;
  for (size_t i = 1; i < 3; i++) {
    bbox.lower_left.x = min(bbox.lower_left.x, triangle.v[i].x);
    bbox.lower_left.y = min(bbox.lower_left.y, triangle.v[i].y);
    bbox.upper_right.x = max(bbox.upper_right.x, triangle.v[i].x);
    bbox.upper_right.y = max(bbox.upper_right.y, triangle.v[i].y);
  }

  // Round down the entire bounding box to the subsample grid
  bbox.lower_left.x =
      floor_ss(bbox.lower_left.x, config.r_shift, config.ss_w_lg2);
  bbox.lower_left.y =
      floor_ss(bbox.lower_left.y, config.r_shift, config.ss_w_lg2);
  bbox.upper_right.x =
      floor_ss(bbox.upper_right.x, config.r_shift, config.ss_w_lg2);
  bbox.upper_right.y =
      floor_ss(bbox.upper_right.y, config.r_shift, config.ss_w_lg2);

  // Clip each corner of the bounding box to the screen
  bbox.lower_left.x = max(0, bbox.lower_left.x);
  bbox.lower_left.y = max(0, bbox.lower_left.y);
  bbox.upper_right.x = min(screen.width, bbox.upper_right.x);
  bbox.upper_right.y = min(screen.height, bbox.upper_right.y);

  // That last step may have moved the bottom-left corner of the bounding box
  // above or right of the upper-right corner. Check for this, and reject the
  // bounding box entirely if that happened.
  bbox.valid = (bbox.lower_left.x <= bbox.upper_right.x) &&
               (bbox.lower_left.y <= bbox.upper_right.y);

  // Do backface culling
  Vertex2D u = {
    .x = triangle.v[1].x - triangle.v[0].x,
    .y = triangle.v[1].y - triangle.v[0].y
  };
  Vertex2D v = {
    .x = triangle.v[2].x - triangle.v[0].x,
    .y = triangle.v[2].y - triangle.v[0].y
  };

  // Raw culling
  int64_t cross = (int64_t)u.x * (int64_t)v.y - (int64_t)u.y * (int64_t)v.x;
  if (cross >= 0)
    bbox.valid = false;

  return bbox;
}

/*
 *  Function: sample_test
 *  Function Description: Checks if sample lies inside triangle
 *
 *
 */
bool sample_test(Triangle triangle, Sample sample) {
  // Just copy the pseudocode

  // Shift vertices such that sample is origin
  int v0_x = triangle.v[0].x - sample.x;
  int v0_y = triangle.v[0].y - sample.y;
  int v1_x = triangle.v[1].x - sample.x;
  int v1_y = triangle.v[1].y - sample.y;
  int v2_x = triangle.v[2].x - sample.x;
  int v2_y = triangle.v[2].y - sample.y;

  // Distance of origin shifted edge
  int dist0 = v0_x * v1_y - v1_x * v0_y;
  int dist1 = v1_x * v2_y - v2_x * v1_y;
  int dist2 = v2_x * v0_y - v0_x * v2_y;

  // Test if origin is on right side of shifted edge
  bool b0 = dist0 <= 0;
  bool b1 = dist1 < 0;
  bool b2 = dist2 <= 0;

  return b0 && b1 && b2;
}

int rasterize_triangle(Triangle triangle, ZBuff *z, Screen screen,
                       Config config) {
  int hit_count = 0;

  // Calculate BBox
  BoundingBox bbox = get_bounding_box(triangle, screen, config);

  // If culled die
  if (!bbox.valid)
    return 0;

  // Iterate over samples and test if in triangle
  Sample sample;
  for (sample.x = bbox.lower_left.x; sample.x <= bbox.upper_right.x;
       sample.x += config.ss_i) {
    for (sample.y = bbox.lower_left.y; sample.y <= bbox.upper_right.y;
         sample.y += config.ss_i) {

      Sample jitter = jitter_sample(sample, config.ss_w_lg2);
      jitter.x = jitter.x << 2;
      jitter.y = jitter.y << 2;

      Sample jittered_sample;
      jittered_sample.x = sample.x + jitter.x;
      jittered_sample.y = sample.y + jitter.y;

      bool hit = sample_test(triangle, jittered_sample);

      if (hit) {
        hit_count++;
        if (z != NULL) {
          Sample hit_location;
          hit_location.x = sample.x >> config.r_shift;
          hit_location.y = sample.y >> config.r_shift;

          Sample subsample;
          subsample.x =
              (sample.x - (hit_location.x << config.r_shift)) / config.ss_i;
          subsample.y =
              (sample.y - (hit_location.y << config.r_shift)) / config.ss_i;

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

void hash_40to8(uchar *arr40, ushort *val, int shift) {
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

Sample jitter_sample(const Sample sample, const int ss_w_lg2) {
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
