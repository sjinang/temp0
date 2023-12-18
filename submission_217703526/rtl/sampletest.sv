/*
 *  Performs Sample Test on triangle
 *
 *  Inputs:
 *    Sample and triangle Information
 *
 *  Outputs:
 *    Subsample Hit Flag, Subsample location, and triangle Information
 *
 *  Function:
 *    Utilizing Edge Equations determine whether the
 *    sample location lies inside the triangle.
 *    In the simple case of the triangle, this will
 *    occur when the sample lies to one side of all
 *    three lines (either all left or all right).
 *    This corresponds to the minterm 000 and 111.
 *    Additionally, if backface culling is performed,
 *    then only keep the case of all right.
 *
 *  Edge Equation:
 *    For an edge defined as travelling from the
 *    vertice (x_1,y_1) to (x_2,y_2), the sample
 *    (x_s,y_s) lies to the right of the line
 *    if the following expression is true:
 *
 *    0 >  ( x_2 - x_1 ) * ( y_s - y_1 ) - ( x_s - x_1 ) * ( y_2 - y_1 )
 *
 *    otherwise it lies on the line (exactly 0) or
 *    to the left of the line.
 *
 *    This block evaluates the six edges described by the
 *    triangles vertices,  to determine which
 *    side of the lines the sample point lies.  Then it
 *    determines if the sample point lies in the triangle
 *    by or'ing the appropriate minterms.  In the case of
 *    the triangle only three edges are relevant.  In the
 *    case of the quadrilateral five edges are relevant.
 *
 *
 *   Author: John Brunhaver
 *   Created:      Thu 07/23/09
 *   Last Updated: Tue 10/06/10
 *
 *   Copyright 2009 <jbrunhaver@gmail.com>
 *
 *
 */

/* A Note on Signal Names:
 *
 * Most signals have a suffix of the form _RxxxxN
 * where R indicates that it is a Raster Block signal
 * xxxx indicates the clock slice that it belongs to
 * and N indicates the type of signal that it is.
 * H indicates logic high, L indicates logic low,
 * U indicates unsigned fixed point, and S indicates
 * signed fixed point.
 *
 */

module sampletest
#(
    parameter SIGFIG        = 24, // Bits in color and position.
    parameter RADIX         = 10, // Fraction bits in color and position
    parameter VERTS         = 3, // Maximum Vertices in triangle
    parameter AXIS          = 3, // Number of axis foreach vertex 3 is (x,y,z).
    parameter COLORS        = 3, // Number of color channels
    parameter NUM_SAMPLES   = 2, // number of samples per cycle
    parameter PIPE_DEPTH    = 2 // How many pipe stages are in this block
)
(
    input logic signed [SIGFIG-1:0]     tri_R16S[VERTS-1:0][AXIS-1:0], // triangle to Iterate Over
    input logic unsigned [SIGFIG-1:0]   color_R16U[COLORS-1:0] , // Color of triangle
    input logic signed [SIGFIG-1:0]     sample_R16S[NUM_SAMPLES-1:0][1:0], // Sample Location
    input logic       [NUM_SAMPLES-1:0] validSamp_R16H, // A valid sample location

    input logic clk, // Clock
    input logic rst, // Reset

    output logic signed [SIGFIG-1:0]    hit_R18S[NUM_SAMPLES-1:0][AXIS-1:0], // Hit Location
    output logic unsigned [SIGFIG-1:0]  color_R18U[COLORS-1:0] , // Color of triangle
    output logic      hit_valid_R18H[NUM_SAMPLES-1:0]                  // Is hit good
);

    localparam EDGES = (VERTS == 3) ? 3 : 5;
    localparam SHORTSF = SIGFIG;
    localparam MROUND = (2 * SHORTSF) - RADIX;

    // output for retiming registers
    logic signed [SIGFIG-1:0]       hit_R18S_retime[NUM_SAMPLES-1:0][AXIS-1:0];   // Hit Location
    logic unsigned [SIGFIG-1:0]     color_R18U_retime[COLORS-1:0];   // Color of triangle
    logic          hit_valid_R18H_retime[NUM_SAMPLES-1:0];   // Is hit good
    // output for retiming registers

    // Signals in Access Order
    logic signed [SIGFIG-1:0]       tri_shift_R16S[NUM_SAMPLES-1:0][VERTS-1:0][1:0]; // triangle after coordinate shift
    logic signed [SIGFIG-1:0]       edge_R16S[NUM_SAMPLES-1:0][EDGES-1:0][1:0][1:0]; // Edges
    logic signed [(2*SHORTSF)-1:0]  dist_lg_R16S[NUM_SAMPLES-1:0][EDGES-1:0]; // Result of x_1 * y_2 - x_2 * y_1
    logic     hit_valid_R16H[NUM_SAMPLES-1:0] ; // Output (YOUR JOB!)
    logic signed [SIGFIG-1:0] hit_R16S[NUM_SAMPLES-1:0][AXIS-1:0]; // Sample position
    // Signals in Access Order

    // Your job is to produce the value for hit_valid_R16H signal, which indicates whether a sample lies inside the triangle.
    // hit_valid_R16H is high if validSamp_R16H && sample inside triangle (with back face culling)
    // Consider the following steps:

    // START CODE HERE
    // (1) Shift X, Y coordinates such that the fragment resides on the (0,0) position.
    // (2) Organize edges (form three edges for triangles)
    // (3) Calculate distance x_1 * y_2 - x_2 * y_1
    // (4) Check distance and assign hit_valid_R16H.
    
    generate
    for (genvar i = 0; i < NUM_SAMPLES; i++) begin
        always_comb begin
            // now testing multiple samples, need to change validSamp_R, sample_R, and hit_valid_R
            // (1) Shift X, Y coordinates such that the fragment resides on the (0,0) position.
            // vert 0
            tri_shift_R16S[i][0][0] = tri_R16S[0][0] - sample_R16S[i][0]; // x
            tri_shift_R16S[i][0][1] = tri_R16S[0][1] - sample_R16S[i][1]; // y

            // vert 1
            tri_shift_R16S[i][1][0] = tri_R16S[1][0] - sample_R16S[i][0]; // x
            tri_shift_R16S[i][1][1] = tri_R16S[1][1] - sample_R16S[i][1]; // y

            // vert 2
            tri_shift_R16S[i][2][0] = tri_R16S[2][0] - sample_R16S[i][0]; // x
            tri_shift_R16S[i][2][1] = tri_R16S[2][1] - sample_R16S[i][1]; // y

            // (2) Organize edges (form three edges for triangles)
            // edge 0 - 1
            edge_R16S[i][0][0][0] = tri_shift_R16S[i][0][0]; // vert 0 x
            edge_R16S[i][0][0][1] = tri_shift_R16S[i][0][1]; // vert 0 y
            edge_R16S[i][0][1][0] = tri_shift_R16S[i][1][0]; // vert 1 x
            edge_R16S[i][0][1][1] = tri_shift_R16S[i][1][1]; // vert 1 y

            // edge 1 - 2
            edge_R16S[i][1][0][0] = tri_shift_R16S[i][1][0]; // vert 1 x
            edge_R16S[i][1][0][1] = tri_shift_R16S[i][1][1]; // vert 1 y
            edge_R16S[i][1][1][0] = tri_shift_R16S[i][2][0]; // vert 2 x
            edge_R16S[i][1][1][1] = tri_shift_R16S[i][2][1]; // vert 2 y

            // edge 2 - 0
            edge_R16S[i][2][0][0] = tri_shift_R16S[i][2][0]; // vert 2 x
            edge_R16S[i][2][0][1] = tri_shift_R16S[i][2][1]; // vert 2 y
            edge_R16S[i][2][1][0] = tri_shift_R16S[i][0][0]; // vert 0 x
            edge_R16S[i][2][1][1] = tri_shift_R16S[i][0][1]; // vert 0 y

            // (3) Calculate distance x_1 * y_2 - x_2 * y_1
            // dist0 
            dist_lg_R16S[i][0] = (edge_R16S[i][0][0][0] * edge_R16S[i][0][1][1]) - (edge_R16S[i][0][1][0] * edge_R16S[i][0][0][1]);

            // dist1
            dist_lg_R16S[i][1] = (edge_R16S[i][1][0][0] * edge_R16S[i][1][1][1]) - (edge_R16S[i][1][1][0] * edge_R16S[i][1][0][1]);

            // dist2
            dist_lg_R16S[i][2] = (edge_R16S[i][2][0][0] * edge_R16S[i][2][1][1]) - (edge_R16S[i][2][1][0] * edge_R16S[i][2][0][1]);

            // (4) Check distance and assign hit_valid_R16H.
            hit_valid_R16H[i] = &{dist_lg_R16S[i][0] <= 0, dist_lg_R16S[i][1] < 0, dist_lg_R16S[i][2] <= 0, validSamp_R16H[i]};
        end
    end
    endgenerate
    // END CODE HERE

    //Assertions to help debug
    //Check if correct inequalities have been used
    // assert property( @(posedge clk) (dist_lg_R16S[1] == 0) |-> !hit_valid_R16H);

    //Calculate Depth as depth of first vertex
    // Note that a barrycentric interpolation would
    // be more accurate
    generate
    for (genvar i = 0; i < NUM_SAMPLES; i++) begin
        always_comb begin
            // change hit_R16S because sample_R16S changed
            hit_R16S[i][1:0] = sample_R16S[i][1:0]; //Make sure you use unjittered sample
            hit_R16S[i][2] = tri_R16S[0][2]; // z value equals the z value of the first vertex
        end
    end
    endgenerate

    /* Flop R16 to R18_retime with retiming registers*/
    dff3 #(
        .WIDTH          (SIGFIG         ),
        .ARRAY_SIZE1    (NUM_SAMPLES    ),
        .ARRAY_SIZE2    (AXIS           ),
        .PIPE_DEPTH     (PIPE_DEPTH - 1 ),
        .RETIME_STATUS  (1              )
    )
    d_samp_r1
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (hit_R16S       ),
        .out    (hit_R18S_retime)
    );

    dff2 #(
        .WIDTH          (SIGFIG         ),
        .ARRAY_SIZE     (COLORS         ),
        .PIPE_DEPTH     (PIPE_DEPTH - 1 ),
        .RETIME_STATUS  (1              )
    )
    d_samp_r2
    (
        .clk    (clk                ),
        .reset  (rst                ),
        .en     (1'b1               ),
        .in     (color_R16U         ),
        .out    (color_R18U_retime  )
    );

    dff2 #(
        .WIDTH          (1              ),
        .ARRAY_SIZE     (NUM_SAMPLES    ),
        .PIPE_DEPTH     (PIPE_DEPTH - 1 ),
        .RETIME_STATUS  (1              ) // RETIME
    )
    d_samp_r3
    (
        .clk    (clk                    ),
        .reset  (rst                    ),
        .en     (1'b1                   ),
        .in     (hit_valid_R16H         ),
        .out    (hit_valid_R18H_retime  )
    );
    /* Flop R16 to R18_retime with retiming registers*/

    /* Flop R18_retime to R18 with fixed registers */
    dff3 #(
        .WIDTH          (SIGFIG ),
        .ARRAY_SIZE1    (NUM_SAMPLES),
        .ARRAY_SIZE2    (AXIS   ),
        .PIPE_DEPTH     (1      ),
        .RETIME_STATUS  (0      )
    )
    d_samp_f1
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (hit_R18S_retime),
        .out    (hit_R18S       )
    );

    dff2 #(
        .WIDTH          (SIGFIG ),
        .ARRAY_SIZE     (COLORS ),
        .PIPE_DEPTH     (1      ),
        .RETIME_STATUS  (0      )
    )
    d_samp_f2
    (
        .clk    (clk                ),
        .reset  (rst                ),
        .en     (1'b1               ),
        .in     (color_R18U_retime  ),
        .out    (color_R18U         )
    );

    dff2 #(
        .WIDTH          (1  ),
        .ARRAY_SIZE     (NUM_SAMPLES),
        .PIPE_DEPTH     (1  ),
        .RETIME_STATUS  (0  ) // No retime
    )
    d_samp_f3
    (
        .clk    (clk                    ),
        .reset  (rst                    ),
        .en     (1'b1                   ),
        .in     (hit_valid_R18H_retime  ),
        .out    (hit_valid_R18H         )
    );

    /* Flop R18_retime to R18 with fixed registers */

endmodule



