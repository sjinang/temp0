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
    parameter PIPE_DEPTH    = 2 // How many pipe stages are in this block
)
(
    input logic signed [SIGFIG-1:0]     tri_R16S[VERTS-1:0][AXIS-1:0], // triangle to Iterate Over
    input logic unsigned [SIGFIG-1:0]   color_R16U[COLORS-1:0] , // Color of triangle
    input logic signed [SIGFIG-1:0]     sample_R16S[1:0], // Sample Location
    input logic                         validSamp_R16H, // A valid sample location

    input logic clk, // Clock
    input logic rst, // Reset

    output logic signed [SIGFIG-1:0]    hit_R18S[AXIS-1:0], // Hit Location
    output logic unsigned [SIGFIG-1:0]  color_R18U[COLORS-1:0] , // Color of triangle
    output logic                        hit_valid_R18H                   // Is hit good
);

    localparam EDGES = (VERTS == 3) ? 3 : 5;
    localparam SHORTSF = SIGFIG;
    localparam MROUND = (2 * SHORTSF) - RADIX;

    // output for retiming registers
    logic signed [SIGFIG-1:0]       hit_R18S_retime[AXIS-1:0];   // Hit Location
    logic unsigned [SIGFIG-1:0]     color_R18U_retime[COLORS-1:0];   // Color of triangle
    logic                           hit_valid_R18H_retime;   // Is hit good
    // output for retiming registers

    // Signals in Access Order
    logic signed [SIGFIG-1:0]       tri_shift_R16S[VERTS-1:0][1:0]; // triangle after coordinate shift
    logic signed [SIGFIG-5:0]       edge_R16S[EDGES-1:0][1:0][1:0]; // Edges
    logic signed [(2*SHORTSF)-17:0]  dist_lg_R16S[EDGES-1:0]; // Result of x_1 * y_2 - x_2 * y_1
    logic                           hit_valid_R16H ; // Output (YOUR JOB!)
    logic signed [SIGFIG-1:0]       hit_R16S[AXIS-1:0]; // Sample position
    // Signals in Access Order

    // Your job is to produce the value for hit_valid_R16H signal, which indicates whether a sample lies inside the triangle.
    // hit_valid_R16H is high if validSamp_R16H && sample inside triangle (with back face culling)
    // Consider the following steps:

    // START CODE HERE
    // (1) Shift X, Y coordinates such that the fragment resides on the (0,0) position.
    always_comb begin
        // TODO: compare performance/area/etc. when using for loops vs fully explicit bit assignment, as in other steps.
        // Convert to more efficient approach.
        for (int i = 0; i < VERTS; i = i + 1) begin
            tri_shift_R16S[i][0] = tri_R16S[i][0] - sample_R16S[0];
            tri_shift_R16S[i][1] = tri_R16S[i][1] - sample_R16S[1];
        end
    end

    // (2) Organize edges (form three edges for triangles)
    // 3 edges, 4 (X, Y) coordinates per edge (effectively form the box around the edge)
    // edges: [i][j][k] = [edge count][which vertex (first or second)][which coord (X or Y)]
    // vertices: [which vertex][X (0) or Y (1)]
    always_comb begin
        // E1 (V1 to V2)
        edge_R16S[0][0][0] = tri_shift_R16S[0][0][19:0]; // E1, V0, X: X of V1
        edge_R16S[0][0][1] = tri_shift_R16S[0][1][19:0]; // E1, V0, Y: Y of V1
        edge_R16S[0][1][0] = tri_shift_R16S[1][0][19:0]; // E1, V1, X: X of V2
        edge_R16S[0][1][1] = tri_shift_R16S[1][1][19:0]; // E1, V1, Y: Y of V2

        // E2 (V2 to V3)
        edge_R16S[1][0][0] = tri_shift_R16S[1][0][19:0]; // E2, V0, X: X of V2
        edge_R16S[1][0][1] = tri_shift_R16S[1][1][19:0]; // E2, V0, Y: Y of V2
        edge_R16S[1][1][0] = tri_shift_R16S[2][0][19:0]; // E2, V1, X: X of V3
        edge_R16S[1][1][1] = tri_shift_R16S[2][1][19:0]; // E2, V1, Y: Y of V3

        // E3 (V3 to V1)
        edge_R16S[2][0][0] = tri_shift_R16S[2][0][19:0]; // E3, V0, X: X of V2
        edge_R16S[2][0][1] = tri_shift_R16S[2][1][19:0]; // E3, V0, Y: Y of V2
        edge_R16S[2][1][0] = tri_shift_R16S[0][0][19:0]; // E3, V1, X: X of V0
        edge_R16S[2][1][1] = tri_shift_R16S[0][1][19:0]; // E3, V1, Y: Y of V0
    end

    always_comb begin
        dist_lg_R16S[0] = edge_R16S[0][0][1] * edge_R16S[0][1][0] - edge_R16S[0][0][0] * edge_R16S[0][1][1]; // flipped
        dist_lg_R16S[1] = edge_R16S[1][0][0] * edge_R16S[1][1][1] - edge_R16S[1][0][1] * edge_R16S[1][1][0];
        dist_lg_R16S[2] = edge_R16S[2][0][1] * edge_R16S[2][1][0] - edge_R16S[2][0][0] * edge_R16S[2][1][1]; // flipped
    end

    // (4) Check distance and assign hit_valid_R16H.
    logic [2:0] edge_check_R16S;
    always_comb begin
        edge_check_R16S[0] = (dist_lg_R16S[0][(2*SHORTSF)-17] == '0);
        edge_check_R16S[1] = (dist_lg_R16S[1] < 0);
        edge_check_R16S[2] = (dist_lg_R16S[2][(2*SHORTSF)-17] == '0);
    end

    assign hit_valid_R16H = validSamp_R16H && edge_check_R16S[0] && edge_check_R16S[1] && edge_check_R16S[2];
    
    // END CODE HERE

    //Assertions to help debug
    //Check if correct inequalities have been used
    assert property( @(posedge clk) (dist_lg_R16S[1] == 0) |-> !hit_valid_R16H);

    //Calculate Depth as depth of first vertex
    // Note that a barrycentric interpolation would
    // be more accurate
    always_comb begin
        hit_R16S[1:0] = sample_R16S[1:0]; //Make sure you use unjittered sample
        hit_R16S[2] = tri_R16S[0][2]; // z value equals the z value of the first vertex
    end

    // Clockgate below flops
    logic clk_gated;
    assign clk_gated = validSamp_R16H && clk;

    /* Flop R16 to R18_retime with retiming registers*/
    dff2 #(
        .WIDTH          (SIGFIG         ),
        .ARRAY_SIZE     (AXIS           ),
        .PIPE_DEPTH     (PIPE_DEPTH - 1 ),
        .RETIME_STATUS  (1              )
    )
    d_samp_r1
    (
        .clk    (clk_gated            ),
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
        .clk    (clk_gated                ),
        .reset  (rst                ),
        .en     (1'b1               ),
        .in     (color_R16U         ),
        .out    (color_R18U_retime  )
    );

    dff_retime #(
        .WIDTH          (1              ),
        .PIPE_DEPTH     (PIPE_DEPTH - 1 ),
        .RETIME_STATUS  (1              ) // RETIME
    )
    d_samp_r3
    (
        .clk    (clk_gated                    ),
        .reset  (rst                    ),
        .en     (1'b1                   ),
        .in     (hit_valid_R16H         ),
        .out    (hit_valid_R18H_retime  )
    );
    /* Flop R16 to R18_retime with retiming registers*/

    /* Flop R18_retime to R18 with fixed registers */
    dff2 #(
        .WIDTH          (SIGFIG ),
        .ARRAY_SIZE     (AXIS   ),
        .PIPE_DEPTH     (1      ),
        .RETIME_STATUS  (0      )
    )
    d_samp_f1
    (
        .clk    (clk_gated            ),
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
        .clk    (clk_gated                ),
        .reset  (rst                ),
        .en     (1'b1               ),
        .in     (color_R18U_retime  ),
        .out    (color_R18U         )
    );

    dff #(
        .WIDTH          (1  ),
        .PIPE_DEPTH     (1  ),
        .RETIME_STATUS  (0  ) // No retime
    )
    d_samp_f3
    (
        .clk    (clk_gated                    ),
        .reset  (rst                    ),
        .en     (1'b1                   ),
        .in     (hit_valid_R18H_retime  ),
        .out    (hit_valid_R18H         )
    );

    /* Flop R18_retime to R18 with fixed registers */

endmodule



