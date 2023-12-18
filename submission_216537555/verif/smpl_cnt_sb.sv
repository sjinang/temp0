/*
 * smpl_cnt_sb
 *
 *  This is a sample count scoreboard.  It checks
 *  to make sure that each triangle generates
 *  the correct number of fragments.
 *
 *  Combined with the correct sample test scoreboard
 *  both scoreboards should detect if a triangle
 *  generates any incorrect fragments
 *
 *
 */

  /****************************************************************************
 * Change bar:
 * -----------
 * Date           Author    Description
 * Sep 22, 2012   jingpu    ported from John's original code to Genesis
 *
 * ***************************************************************************/

import "DPI" pure function int check_hit_count(
    int   v0_x,   //triangle
    int   v0_y,        //triangle
    int   v1_x,        //triangle
    int   v1_y,        //triangle
    int   v2_x,        //triangle
    int   v2_y,        //triangle
    int   hits,        //Number of Samples in triangle
    int   ss_w_lg2,    //Subsample
    int   screen_w,    //Screen
    int   screen_h,    //Screen
    int   r_shift,     //Config
    int   r_val        //Congig
);

// Import the DPI function for checking the hash module
import "DPI" pure function int check_hash(
    int s_x,           //sample
    int s_y,           //sample
    int ss_w_lg2,      //Subsample
    int jitter_x,      //jitter
    int jitter_y,      //jitter
    int s_j_x,         //jittered_sample
    int s_j_y          //jittered_sample
);
// END CODE HERE

module smpl_cnt_sb
#(
    parameter SIGFIG = 24, // Bits in color and position.
    parameter RADIX = 10, // Fraction bits in color and position
    parameter VERTS = 3, // Maximum Vertices in triangle
    parameter AXIS = 3, // Number of axis foreach vertex 3 is (x,y,z).
    parameter COLORS = 3, // Number of color channels
    parameter PIPE_DEPTH = 3, // Number of Pipe Stages in bbox module
    parameter FILENAME = "sb_log/smpl_cnt_sb.log" // Log file name
)
(
    input logic signed   [SIGFIG-1:0]   tri_R16S[VERTS-1:0][AXIS-1:0],  // 4 Sets X,Y Fixed Point Values
    input logic unsigned [SIGFIG-1:0]   color_R16U[COLORS-1:0],          // 4 Sets X,Y Fixed Point Values
    input logic                         validSamp_R16H,
    input logic signed   [SIGFIG-1:0]   sample_R16S[1:0],

    input logic                             clk,                // Clock
    input logic                             rst,                // Reset

    input logic signed [SIGFIG-1:0]     hit_R18S[AXIS-1:0],
    input logic signed [SIGFIG-1:0]     color_R18U[COLORS-1:0],
    input logic                         hit_valid_R18H,
    

    input logic        [SIGFIG-1:0]     screen_RnnnnS[1:0],      // Screen Size
    input logic        [3:0]            subSample_RnnnnU,    // Flag for subsample

    input logic signed [SIGFIG-1:0]     s_x_RnnS,
    input logic signed [SIGFIG-1:0]     s_y_RnnS,
    input logic signed [7:0]            jitter_x_RnnS,
    input logic signed [7:0]            jitter_y_RnnS,
    input logic signed [SIGFIG-1:0]     s_j_x_RnnS,
    input logic signed [SIGFIG-1:0]     s_j_y_RnnS,

    // multitest: sample b
    input logic                         hit_valid_R18H_B,
    input logic signed [SIGFIG-1:0]     s_x_RnnS_B,
    input logic signed [SIGFIG-1:0]     s_y_RnnS_B,
    input logic signed [7:0]            jitter_x_RnnS_B,
    input logic signed [7:0]            jitter_y_RnnS_B,
    input logic signed [SIGFIG-1:0]     s_j_x_RnnS_B,
    input logic signed [SIGFIG-1:0]     s_j_y_RnnS_B,
    // multitest: sample b
    input logic                         hit_valid_R18H_C,
    input logic signed [SIGFIG-1:0]     s_x_RnnS_C,
    input logic signed [SIGFIG-1:0]     s_y_RnnS_C,
    input logic signed [7:0]            jitter_x_RnnS_C,
    input logic signed [7:0]            jitter_y_RnnS_C,
    input logic signed [SIGFIG-1:0]     s_j_x_RnnS_C,
    input logic signed [SIGFIG-1:0]     s_j_y_RnnS_C
 );


    //Pipe Signals for Later Evaluation
    logic signed   [SIGFIG-1:0] tri_RnnS[VERTS-1:0][AXIS-1:0];    // 4 Sets X,Y Fixed Point Values
    logic signed   [SIGFIG-1:0] tri_Rn1S[VERTS-1:0][AXIS-1:0];    // 4 Sets X,Y Fixed Point Values
    logic unsigned [SIGFIG-1:0] color_RnnU[COLORS-1:0];
    logic                       validSamp_RnnH;
    logic signed   [SIGFIG-1:0] sample_RnnS[1:0];             //
    //Pipe Signals for Later Evaluation

    //Helper Signals
    int file;
    int one;
    int ss_w_lg2;
    assign one = 1 ;
    //Helper Signals

    //Bench Logic
    int   hit_count;
    int   hit_count_next;
    logic incr;
    logic incr_by_two;
    logic keep;
    logic reset_to_zero;
    logic reset_to_one;
    logic reset_to_two;
    //Bench Logic

    initial begin
        file = $fopen(FILENAME,"w");
    end

    always_comb begin
        unique case( 1'b1 )
            ( subSample_RnnnnU[0] ): ss_w_lg2 = 3;
            ( subSample_RnnnnU[1] ): ss_w_lg2 = 2;
            ( subSample_RnnnnU[2] ): ss_w_lg2 = 1;
            ( subSample_RnnnnU[3] ): ss_w_lg2 = 0;
        endcase
    end

    // Call the DPI function that checks that the hash produces the correct jittered samples
    // Should only be called if reset is not asserted
    always @( posedge clk ) begin
        #10;
        if (~rst) begin
            if (one != check_hash(
                    int'(s_x_RnnS), 
                    int'(s_y_RnnS), 
                    int'(ss_w_lg2),
                    int'(jitter_x_RnnS), 
                    int'(jitter_y_RnnS),
                    int'(s_j_x_RnnS),
                    int'(s_j_y_RnnS))) 
            assert(0) else $error("Hash check failed");
        end
    end
    // multitest: sample b
    always @( posedge clk ) begin
        #10;
        if (~rst) begin
            if (one != check_hash(
                    int'(s_x_RnnS_B), 
                    int'(s_y_RnnS_B), 
                    int'(ss_w_lg2),
                    int'(jitter_x_RnnS_B), 
                    int'(jitter_y_RnnS_B),
                    int'(s_j_x_RnnS_B),
                    int'(s_j_y_RnnS_B))) 
            assert(0) else $error("Hash check failed");
        end
    end
    // multitest: sample c 
    always @( posedge clk ) begin
        #10;
        if (~rst) begin
            if (one != check_hash(
                    int'(s_x_RnnS_C), 
                    int'(s_y_RnnS_C), 
                    int'(ss_w_lg2),
                    int'(jitter_x_RnnS_C), 
                    int'(jitter_y_RnnS_C),
                    int'(s_j_x_RnnS_C),
                    int'(s_j_y_RnnS_C))) 
            assert(0) else $error("Hash check failed");
        end
    end
    // END CODE HERE

    //Check that the Number of Hits is Correct
    always @( posedge clk ) begin
        #10;
        if( reset_to_zero && validSamp_RnnH ) begin
            //if(one != check_hit_count(
            //        int'(tri_RnnS[0][0]),   //triangle
            //        int'(tri_RnnS[0][1]),   //triangle
            //        int'(tri_RnnS[1][0]),   //triangle
            //        int'(tri_RnnS[1][1]),   //triangle
            //        int'(tri_RnnS[2][0]),   //triangle
            //        int'(tri_RnnS[2][1]),   //triangle
            //        hit_count,               //Number of Samples in triangle
            //        ss_w_lg2,                //Subsample
            //        int'(screen_RnnnnS[0] ), //Screen
            //        int'(screen_RnnnnS[1] ), //Screen
            //        RADIX,                   //Config
            //        int'( 128'd1 << RADIX )  //Congig
            //        )) begin

            //    $finish();
            //end
        end
    end

    //Sample hit Counter for

    //hit_count_next holds the number of hits in triangle 106 so far
    dff #(
        .WIDTH          (32 ),
        .PIPE_DEPTH     (1  ),
        .RETIME_STATUS  (0  ) // No retime
    )
    dc
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (hit_count_next ),
        .out    (hit_count      )
    );

    always_comb begin

        reset_to_zero = (tri_Rn1S != tri_RnnS) ; //New triangle
        reset_to_one = (reset_to_zero && hit_valid_R18H) || (reset_to_zero && hit_valid_R18H_B); //New triangle with hit
        reset_to_two = (reset_to_zero && hit_valid_R18H) && (reset_to_zero && hit_valid_R18H_B); //New triangle with hit
        incr_by_two = hit_valid_R18H && hit_valid_R18H_B; //both samples hit
        incr = hit_valid_R18H | hit_valid_R18H_B;
        keep = ~hit_valid_R18H && ~hit_valid_R18H_B ;

        priority case( 1'b1 )
            (reset_to_two): hit_count_next = 2;
            (reset_to_one): hit_count_next = 1;
            (reset_to_zero): hit_count_next = 0;
            (incr_by_two): hit_count_next = hit_count + 2;
            (incr): hit_count_next = hit_count + 1 ;
            (keep): hit_count_next = hit_count ;
            default: hit_count_next = 0;
        endcase // case ( 1'b1 )
    end
    //Sample Hit Counter

    //Pipe triangle Along
    dff3 #(
        .WIDTH          (SIGFIG     ),
        .ARRAY_SIZE1    (VERTS      ),
        .ARRAY_SIZE2    (AXIS       ),
        .PIPE_DEPTH     (PIPE_DEPTH ),
        .RETIME_STATUS  (0          )
    )
    d_01
    (
        .clk    (clk        ),
        .reset  (rst        ),
        .en     (1'b1       ),
        .in     (tri_R16S   ),
        .out    (tri_RnnS   )
    );

    dff3 #(
        .WIDTH          (SIGFIG         ),
        .ARRAY_SIZE1    (VERTS          ),
        .ARRAY_SIZE2    (AXIS           ),
        .PIPE_DEPTH     (PIPE_DEPTH - 1 ),
        .RETIME_STATUS  (0              )
    )
    d_011
    (
        .clk    (clk        ),
        .reset  (rst        ),
        .en     (1'b1       ),
        .in     (tri_R16S   ),
        .out    (tri_Rn1S   )
    );

    dff2 #(
        .WIDTH          (SIGFIG     ),
        .ARRAY_SIZE     (COLORS     ),
        .PIPE_DEPTH     (PIPE_DEPTH ),
        .RETIME_STATUS  (0          )
    )
    d_02
    (
        .clk    (clk        ),
        .reset  (rst        ),
        .en     (1'b1       ),
        .in     (color_R16U ),
        .out    (color_RnnU )
    );

    dff2 #(
        .WIDTH          (SIGFIG     ),
        .ARRAY_SIZE     (2          ),
        .PIPE_DEPTH     (PIPE_DEPTH ),
        .RETIME_STATUS  (0          )
    )
    d_03
    (
        .clk    (clk        ),
        .reset  (rst        ),
        .en     (1'b1       ),
        .in     (sample_R16S),
        .out    (sample_RnnS)
    );

    dff #(
        .WIDTH          (1          ),
        .PIPE_DEPTH     (PIPE_DEPTH ),
        .RETIME_STATUS  (0          ) // No retime
    )
    d_04
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (validSamp_R16H ),
        .out    (validSamp_RnnH )
    );

endmodule

