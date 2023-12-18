/*
 * Reyes Style Hider:
 *
 *  This module accepts a stream of triangles
 *  and produces a stream of fragments
 *
 *  This module contains three submodules:
 *    -bounding box module which generates the bounding box
 *     for a triangle
 *    -test iterator module which iterates over the bounding
 *    -sample test function which tests to see if the sample
 *     location from the bounding box lay inside the triangle
 *
 *
 *   Author: John Brunhaver
 *   Created:          09/21/09
 *   Last Updated: TUE 10/20/09
 *
 *   Copyright 2009 <jbrunhaver@gmail.com>
 */


/* ***************************************************************************
 * Change bar:
 * -----------
 * Date           Author    Description
 * Sep 19, 2012   jingpu    ported from John's original code to Genesis
 *
 * ***************************************************************************/
//`include "rast_params.sv"
import rast_params::*;

module rast
#(
    parameter SIGFIG = rast_params::SIGFIG, // Bits in color and position.
    parameter RADIX = rast_params::RADIX, // Fraction bits in color and position
    parameter VERTS = rast_params::VERTS, // Maximum Vertices in triangle
    parameter AXIS = rast_params::AXIS, // Number of axis foreach vertex 3 is (x,y,z).
    parameter COLORS = rast_params::COLORS, // Number of color channels
    parameter PIPES_BOX = rast_params::PIPES_BOX, // Number of Pipe Stages in bbox module
    parameter PIPES_ITER = rast_params::PIPES_ITER, // Number of Pipe Stages in iter module
    parameter PIPES_HASH = rast_params::PIPES_HASH, // Number of pipe stages in hash module
    parameter PIPES_SAMP = rast_params::PIPES_SAMP, // Number of Pipe Stages in sample module

    parameter MULTI_SAMP = rast_params::MULTI_SAMP // Number of concurrently sampled signals
)
(
    // Input Signals
    input logic signed [SIGFIG-1:0]     tri_R10S[VERTS-1:0][AXIS-1:0], // Tri Position
    input logic unsigned [SIGFIG-1:0]   color_R10U[COLORS-1:0], // Color of Tri
    input logic                             validTri_R10H, // Valid Data for Operation

    // Input Control Signals ( ala CSR )
    input logic signed [SIGFIG-1:0] screen_RnnnnS[1:0], // Screen Dimensions
    input logic [3:0]                   subSample_RnnnnU, // SubSample_Interval

    // Global Signals
    input logic clk, // Clock
    input logic rst, // Reset

    // Output Control Signals
    output logic halt_RnnnnL,

    // Output Signals
    output logic signed [SIGFIG-1:0]    hit_R18S[MULTI_SAMP - 1:0][AXIS-1:0], // Hit Location
    output logic unsigned [SIGFIG-1:0]  color_R18U[COLORS-1:0], // Color of Tri
    output logic                            hit_valid_R18H[MULTI_SAMP - 1:0]   // Is this a hit?
);

    //Intermediate Signals
    logic signed [SIGFIG-1:0]   box_R13S[1:0][1:0];             // 2 Sets X,Y Fixed Point Values
    logic signed [SIGFIG-1:0]   tri_R13S[VERTS-1:0][AXIS-1:0]; // 4 Sets X,Y Fixed Point Values
    logic unsigned [SIGFIG-1:0] color_R13U[COLORS-1:0]  ;       // Color of Tri
    logic                           validTri_R13H;                 // Valid Data for Operation

    logic signed [SIGFIG-1:0]   tri_R14S[VERTS-1:0][AXIS-1:0]; //triangle to Sample Test
    logic unsigned [SIGFIG-1:0] color_R14U[COLORS-1:0];         // Color of Tri

    logic signed [SIGFIG-1:0]   sample_R14S[MULTI_SAMP - 1:0][1:0];               //Sample Location to Be Tested
    logic                           validSamp_R14H[MULTI_SAMP - 1:0];                 //Sample and triangle are Valid

    logic signed [SIGFIG-1:0]   tri_R16S[VERTS-1:0][AXIS-1:0]; //triangle to Sample Test
    logic unsigned [SIGFIG-1:0] color_R16U[COLORS-1:0];         //Color of Tri

    logic signed [SIGFIG-1:0]   sample_R16S[MULTI_SAMP - 1:0][1:0];               //Sample Location to Be Tested
    logic                           validSamp_R16H[MULTI_SAMP - 1:0];                 //Sample and triangle are Valid

    logic [SIGFIG-1:0]  zero;                     //fudge signal to hold zero as a reset value
    logic [127:0]           big_zero;                 //fudge signal to hold zero as a reset value
    //Intermediate Signals

    assign big_zero = 128'd0;
    assign zero = big_zero[SIGFIG-1:0];

    //TODO: Missing triangle color

    //TODO: Make param pipedepth work

    bbox #(
        .SIGFIG     (SIGFIG     ),
        .RADIX      (RADIX      ),
        .VERTS      (VERTS      ),
        .AXIS       (AXIS       ),
        .COLORS     (COLORS     ),
        .PIPE_DEPTH (PIPES_BOX  )
    )
    bbox
    (
        .tri_R10S           (tri_R10S           ),
        .color_R10U         (color_R10U         ),
        .validTri_R10H      (validTri_R10H      ),

        .halt_RnnnnL        (halt_RnnnnL        ),
        .screen_RnnnnS      (screen_RnnnnS      ),
        .subSample_RnnnnU   (subSample_RnnnnU   ),

        .clk                (clk                ),
        .rst                (rst                ),

        .tri_R13S           (tri_R13S           ),
        .color_R13U         (color_R13U         ),
        .box_R13S           (box_R13S           ),
        .validTri_R13H      (validTri_R13H      )
    );

    test_iterator #(
        .SIGFIG     (SIGFIG     ),
        .RADIX      (RADIX      ),
        .VERTS      (VERTS      ),
        .AXIS       (AXIS       ),
        .COLORS     (COLORS     ),
        .PIPE_DEPTH (PIPES_ITER ),
        .MULTI_SAMP (MULTI_SAMP )
    )
    test_iterator
    (
        .tri_R13S           (tri_R13S           ),
        .color_R13U         (color_R13U         ),
        .box_R13S           (box_R13S           ),
        .validTri_R13H      (validTri_R13H      ),

        .subSample_RnnnnU   (subSample_RnnnnU   ),
        .halt_RnnnnL        (halt_RnnnnL        ),

        .clk                (clk                ),
        .rst                (rst                ),

        .tri_R14S           (tri_R14S           ),
        .color_R14U         (color_R14U         ),
        .sample_R14S        (sample_R14S        ),
        .validSamp_R14H     (validSamp_R14H     )
    );

   hash_jtree #(
        .SIGFIG     (SIGFIG     ),
        .RADIX      (RADIX      ),
        .VERTS      (VERTS      ),
        .AXIS       (AXIS       ),
        .COLORS     (COLORS     ),
        .PIPE_DEPTH (PIPES_HASH ),
        
        .MULTI_SAMP (MULTI_SAMP)
    )
    hash_jtree
    (
        .tri_R14S           (tri_R14S           ),
        .color_R14U         (color_R14U         ),
        .sample_R14S        (sample_R14S        ),
        .validSamp_R14H     (validSamp_R14H     ),

        .subSample_RnnnnU   (subSample_RnnnnU   ),

        .clk                (clk                ),
        .rst                (rst                ),

        .tri_R16S           (tri_R16S           ),
        .color_R16U         (color_R16U         ),
        .sample_R16S        (sample_R16S        ),
        .validSamp_R16H     (validSamp_R16H     )
    );


    sampletest #(
        .SIGFIG     (SIGFIG     ),
        .RADIX      (RADIX      ),
        .VERTS      (VERTS      ),
        .AXIS       (AXIS       ),
        .COLORS     (COLORS     ),
        .PIPE_DEPTH (PIPES_SAMP ),
        
        .MULTI_SAMP (MULTI_SAMP)
    )
    sampletest
    (
        .tri_R16S       (tri_R16S       ),
        .color_R16U     (color_R16U     ),
        .sample_R16S    (sample_R16S    ),
        .validSamp_R16H (validSamp_R16H ),

        .clk            (clk            ),
        .rst            (rst            ),

        .hit_R18S       (hit_R18S       ),
        .color_R18U     (color_R18U     ),
        .hit_valid_R18H (hit_valid_R18H )
    );

endmodule
