/*
 *  Bounding Box Sample Test Iteration
 *
 *  Inputs:
 *    BBox and triangle Information
 *
 *  Outputs:
 *    Subsample location and triangle Information
 *
 *  Function:
 *    Iterate from left to right bottom to top
 *    across the bounding box.
 *
 *    While iterating set the halt signal in
 *    order to hold the bounding box pipeline in
 *    place.
 *
 *
 * Long Description:
 *    The iterator starts in the waiting state,
 *    when a valid triangle bounding box
 *    appears at the input. It will enter the
 *    testing state the next cycle with a
 *    sample equivelant to the lower left
 *    cooridinate of the bounding box.
 *
 *    While in the testing state, the next sample
 *    for each cycle should be one sample interval
 *    to the right, except when the current sample
 *    is at the right edge.  If the current sample
 *    is at the right edge, the next sample should
 *    be one row up.  Additionally, if the current
 *    sample is on the top row and the right edge,
 *    next cycles sample should be invalid and
 *    equivelant to the lower left vertice and
 *    next cycles state should be waiting.
 *
 *
 *   Author: John Brunhaver
 *   Created:      Thu 07/23/09
 *   Last Updated: Tue 10/01/10
 *
 *   Copyright 2009 <jbrunhaver@gmail.com>
 *
 */

/* ***************************************************************************
 * Change bar:
 * -----------
 * Date           Author    Description
 * Sep 19, 2012   jingpu    ported from John's original code to Genesis
 *
 * ***************************************************************************/

/* A Note on Signal Names:
 *
 * Most signals have a suffix of the form _RxxN
 * where R indicates that it is a Raster Block signal
 * xx indicates the clock slice that it belongs to
 * and N indicates the type of signal that it is.
 * H indicates logic high, L indicates logic low,
 * U indicates unsigned fixed point, and S indicates
 * signed fixed point.
 *
 * For all the signed fixed point signals (logic signed [`$sig_fig`-1:0]),
 * their highest `$sig_fig-$radix` bits, namely [`$sig_fig-1`:`$radix`]
 * represent the integer part of the fixed point number,
 * while the lowest `$radix` bits, namely [`$radix-1`:0]
 * represent the fractional part of the fixed point number.
 *
 *
 *
 * For signal subSample_RnnnnU (logic [3:0])
 * 1000 for  1x MSAA eq to 1 sample per pixel
 * 0100 for  4x MSAA eq to 4 samples per pixel,
 *              a sample is half a pixel on a side
 * 0010 for 16x MSAA eq to 16 sample per pixel,
 *              a sample is a quarter pixel on a side.
 * 0001 for 64x MSAA eq to 64 samples per pixel,
 *              a sample is an eighth of a pixel on a side.
 *
 */

module test_iterator
#(
    parameter SIGFIG = 24, // Bits in color and position.
    parameter RADIX = 10, // Fraction bits in color and position
    parameter VERTS = 3, // Maximum Vertices in triangle
    parameter AXIS = 3, // Number of axis foreach vertex 3 is (x,y,z).
    parameter COLORS = 3, // Number of color channels
    parameter PIPE_DEPTH = 1, // How many pipe stages are in this block
    parameter MOD_FSM = 0 // Use Modified FSM to eliminate a wait state
)
(
    //Input Signals
    input logic signed [SIGFIG-1:0]     tri_R13S[VERTS-1:0][AXIS-1:0], //triangle to Iterate Over
    input logic unsigned [SIGFIG-1:0]   color_R13U[COLORS-1:0] , //Color of triangle
    input logic signed [SIGFIG-1:0]     box_R13S[1:0][1:0], //Box to iterate for subsamples
    input logic                             validTri_R13H, //triangle is valid

    //Control Signals
    input logic [3:0]   subSample_RnnnnU , //Subsample width
    output logic        halt_RnnnnL , //Halt -> hold current microtriangle
    //Note that this block generates
    //Global Signals
    input logic clk, // Clock
    input logic rst, // Reset

    //Outputs
    output logic signed [SIGFIG-1:0]    tri_R14S[VERTS-1:0][AXIS-1:0], //triangle to Sample Test
    output logic unsigned [SIGFIG-1:0]  color_R14U[COLORS-1:0], //Color of triangle
    output logic signed [SIGFIG-1:0]    sample_R14S[3:0][1:0], //Sample Location to Be Tested // Vector Width 4
    output logic                   validSamp_R14H[3:0] //Sample and triangle are Valid // Vector Width 4
);

    // This module implement a Moore machine to iterarte sample points in bbox
    // Recall: a Moore machine is an FSM whose output values are determined
    // solely by its current state.
    // A simple way to build a Moore machine is to make states for every output
    // and the values of the current states are the outputs themselves

    // Now we create the signals for the next states of each outputs and
    // then instantiate registers for storing these states
    localparam SIGFIG_LESS = 24;
    localparam SIGFIG_DIFF = SIGFIG - SIGFIG_LESS;
    localparam  MULTITEST = 4;

    logic signed [SIGFIG-1:0]       next_tri_R14S[VERTS-1:0][AXIS-1:0];
    logic unsigned  [SIGFIG-1:0]    next_color_R14U[COLORS-1:0] ;
    logic signed [SIGFIG-1:0]       next_sample_R14S[MULTITEST-1:0][1:0];    // Vector Width 4
    logic [MULTITEST-1:0]                         next_validSamp_R14H;  // Vector Width 4
    logic                               next_halt_RnnnnL;

    // Instantiate registers for storing these states
    dff3 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE1(VERTS),
        .ARRAY_SIZE2(AXIS),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0)
    )
    d301
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (next_tri_R14S  ),
        .out    (tri_R14S       )
    );

    dff2 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE(COLORS),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0)
    )
    d302
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (next_color_R14U),
        .out    (color_R14U     )
    );
    genvar i;
    generate
        for(i = 0; i < MULTITEST; i = i + 1) begin
            dff2 #(
                .WIDTH(SIGFIG),
                .ARRAY_SIZE(2),
                .PIPE_DEPTH(1),
                .RETIME_STATUS(0)
            )
            d303
            (
                .clk    (clk                ),
                .reset  (rst                ),
                .en     (1'b1               ),
                .in     (next_sample_R14S[i]),
                .out    (sample_R14S[i]     )
            );

            dff #(
                .WIDTH(1),
                .PIPE_DEPTH(1),
                .RETIME_STATUS(0) // No retime
            )
            d304
            (
                .clk    (clk                                    ),
                .reset  (rst                                    ),
                .en     (1'b1                                   ),
                .in     (next_validSamp_R14H[i]                 ),
                .out    (validSamp_R14H[i]                      )          
            );
        end
    endgenerate
    dff #(
        .WIDTH(1),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0) // No retime
    )
    d304
    (
        .clk    (clk                                    ),
        .reset  (rst                                    ),
        .en     (1'b1                                   ),
        .in     (next_halt_RnnnnL                       ),
        .out    (halt_RnnnnL                            )
    );    
    // Instantiate registers for storing these states

    typedef enum logic {
                            WAIT_STATE,
                            TEST_STATE
                        } state_t;
generate
if(MOD_FSM == 0) begin // Using baseline FSM
    //////
    //////  RTL code for original FSM Goes Here
    //////

    // To build this FSM we want to have two more state: one is the working
    // status of this FSM, and the other is the current bounding box where
    // we iterate sample points

    // define two more states, box_R14S and state_R14H
    logic signed [SIGFIG_LESS-1:0]   box_R14S[1:0][1:0];    		// the state for current bounding box
    logic signed [SIGFIG_LESS-1:0]   next_box_R14S[1:0][1:0];

    state_t                     state_R14H;     //State Designation (Waiting or Testing)
    state_t                     next_state_R14H;        //Next Cycles State

    dff3 #(
        .WIDTH(SIGFIG_LESS),
        .ARRAY_SIZE1(2),
        .ARRAY_SIZE2(2),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0)
    )
    d305
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (1'b1           ),
        .in     (next_box_R14S  ),
        .out    (box_R14S       )
    );

    always_ff @(posedge clk, posedge rst) begin
        if(rst) begin
            state_R14H <= WAIT_STATE;
        end
        else begin
            state_R14H <= next_state_R14H;
        end
    end

    // define some helper signals
    logic signed [SIGFIG_LESS-1:0]   next_up_samp_R14S[MULTITEST-1:0][1:0]; //If jump up, next sample // Vector Width 4
    logic signed [SIGFIG-1:0]   next_rt_samp_R14S[MULTITEST-1:0][1:0]; //If jump right, next sample // Vector Width 4
    logic [MULTITEST-1:0]                 at_right_edg_R14H;      //Current sample at right edge of bbox? // Vector Width 4
    logic [MULTITEST-1:0]                 at_top_edg_R14H;        //Current sample at top edge of bbox? // Vector Width 4
    logic [MULTITEST-1:0]                 at_end_box_R14H;        //Current sample at end of bbox? // Vector Width 4

    // Additional signals to generate sample step value
    logic signed [SIGFIG-1:0] sample_step;
    // logic signed [SIGFIG-RADIX-2:0] zero_pad;
    // logic signed [RADIX:0] interm_sample_step;
    // assign interm_sample_step = subSample_RnnnnU<<(RADIX-3);
    // assign zero_pad = 0;   
    // assign sample_step = {zero_pad, interm_sample_step};
    assign sample_step = {{(SIGFIG-RADIX-1){1'b0}},{subSample_RnnnnU},{(RADIX-3){1'b0}}};

    //////
    ////// First calculate the values of the helper signals using CURRENT STATES
    //////

    // check the comments 'A Note on Signal Names'
    // at the begining of the module for the help on
    // understanding the signals here

    always_comb begin
        // START CODE HERE
        for(int i = 0; i < MULTITEST; i = i + 1) begin
            // The next up Sample will have the lower left "x" coordinate of current bounding box
            next_up_samp_R14S[i][0] = box_R14S[0][0];
            // The next up Sample will have the current "y" coordinate of present sample incremented by sample step // Vector Width 4
            next_up_samp_R14S[i][1] = sample_R14S[i][1] + MULTITEST * sample_step;
            // The next rt Sample will have the "x" coordinate of present sample incremented by sample step
            next_rt_samp_R14S[i][0] = sample_R14S[i][0] + sample_step;
            // The next rt Sample will have the current "y" coordinate of present sample
            next_rt_samp_R14S[i][1] = sample_R14S[i][1];
            // The current sample is at the top edge if current sample's y coordinates are == bounding box UR y coordinates
            at_top_edg_R14H[i] = (sample_R14S[i][1] >= box_R14S[1][1]);
            // The current sample is at the top edge if current sample's x coordinates are == bounding box UR x coordinates
            at_right_edg_R14H[i] = (sample_R14S[i][0] >= box_R14S[1][0]); 
            // The current sample is at the end box edge if current sample's x and y coordinates are == bounding box UR x and y coordinates
            at_end_box_R14H[i] = at_right_edg_R14H[i] && at_top_edg_R14H[i]; 
        end          
        // END CODE HERE
    end

    //////
    ////// Then complete the following combinational logic defining the
    ////// next states
    //////

    ////// COMPLETE THE FOLLOW ALWAYS_COMB BLOCK

    // Combinational logic for state transitions
    always_comb begin
        // START CODE HERE
        // Try using a case statement on state_R14H   
        case(state_R14H)
            WAIT_STATE: begin
                (* parallel_case *)
                case(validTri_R13H)
                    1'b1: begin
                        next_tri_R14S = tri_R13S;
                        next_color_R14U = color_R13U;
                        for(int i = 0; i < MULTITEST; i = i + 1) begin
                            next_sample_R14S[i][0]    = box_R13S[0][0];
                            next_sample_R14S[i][1]    = box_R13S[0][1] + i * sample_step;
                            next_validSamp_R14H[i] = 1'b1;
                        end
                        next_halt_RnnnnL = 1'b0;
                        next_box_R14S[0][0] = box_R13S[0][0][SIGFIG_LESS-1:0];
                        next_box_R14S[0][1] = box_R13S[0][1][SIGFIG_LESS-1:0];
                        next_box_R14S[1][0] = box_R13S[1][0][SIGFIG_LESS-1:0];
                        next_box_R14S[1][1] = box_R13S[1][1][SIGFIG_LESS-1:0];
                        next_state_R14H  = TEST_STATE;
                    end
                    default: begin
                        next_tri_R14S = tri_R13S;
                        next_color_R14U = color_R13U;
                        for(int i = 0; i < MULTITEST; i = i + 1) begin
                            next_sample_R14S[i][0]    = box_R13S[0][0];
                            next_sample_R14S[i][1]    = box_R13S[0][1] + i * sample_step;
                            next_validSamp_R14H[i] = 1'b0;
                        end
                        next_halt_RnnnnL = 1'b1;
                        next_box_R14S[0][0] = box_R13S[0][0][SIGFIG_LESS-1:0];
                        next_box_R14S[0][1] = box_R13S[0][1][SIGFIG_LESS-1:0];
                        next_box_R14S[1][0] = box_R13S[1][0][SIGFIG_LESS-1:0];
                        next_box_R14S[1][1] = box_R13S[1][1][SIGFIG_LESS-1:0];
                        next_state_R14H  = WAIT_STATE; 
                    end
                endcase 
            end
            TEST_STATE:begin // check: why not checking the valid_triangle
                case({&at_end_box_R14H,&at_right_edg_R14H,&at_top_edg_R14H})
                    3'b111: begin
                        next_tri_R14S = tri_R13S;
                        next_color_R14U = color_R13U;
                        for(int i = 0; i < MULTITEST; i = i + 1) begin
                            next_sample_R14S[i][0]    = box_R13S[0][0];
                            next_sample_R14S[i][1]    = box_R13S[0][1] + i * sample_step;
                            next_validSamp_R14H[i] = 1'b0;
                        end
                        next_halt_RnnnnL = 1'b1;
                        next_box_R14S[0][0] = box_R13S[0][0][SIGFIG_LESS-1:0];
                        next_box_R14S[0][1] = box_R13S[0][1][SIGFIG_LESS-1:0];
                        next_box_R14S[1][0] = box_R13S[1][0][SIGFIG_LESS-1:0];
                        next_box_R14S[1][1] = box_R13S[1][1][SIGFIG_LESS-1:0];
                        next_state_R14H  = WAIT_STATE;
                    end
                    3'b010: begin
                        next_tri_R14S = tri_R14S;
                        next_color_R14U = color_R14U;
                        for(int i = 0; i < MULTITEST; i = i + 1) begin
                            next_sample_R14S[i][0] = { {SIGFIG_DIFF{next_up_samp_R14S[i][0][SIGFIG_LESS-1]}}, next_up_samp_R14S[i][0][SIGFIG_LESS-1:0]};
                            next_sample_R14S[i][1] = { {SIGFIG_DIFF{next_up_samp_R14S[i][1][SIGFIG_LESS-1]}}, next_up_samp_R14S[i][1][SIGFIG_LESS-1:0]};
                            next_validSamp_R14H[i] = 1'b1;
                        end
                        next_halt_RnnnnL = 1'b0;
                        next_box_R14S[0][0] = box_R14S[0][0][SIGFIG_LESS-1:0];
                        next_box_R14S[0][1] = box_R14S[0][1][SIGFIG_LESS-1:0];
                        next_box_R14S[1][0] = box_R14S[1][0][SIGFIG_LESS-1:0];
                        next_box_R14S[1][1] = box_R14S[1][1][SIGFIG_LESS-1:0];
                        next_state_R14H  = TEST_STATE; 
                    end
                    default: begin
                        next_tri_R14S = tri_R14S;
                        next_color_R14U = color_R14U;
                        for(int i = 0; i < MULTITEST; i = i + 1) begin
                            next_sample_R14S[i]    = next_rt_samp_R14S[i];
                            next_validSamp_R14H[i] = 1'b1;
                        end
                        next_halt_RnnnnL = 1'b0;
                        next_box_R14S[0][0] = box_R14S[0][0][SIGFIG_LESS-1:0];
                        next_box_R14S[0][1] = box_R14S[0][1][SIGFIG_LESS-1:0];
                        next_box_R14S[1][0] = box_R14S[1][0][SIGFIG_LESS-1:0];
                        next_box_R14S[1][1] = box_R14S[1][1][SIGFIG_LESS-1:0];
                        next_state_R14H  = TEST_STATE;   
                    end
                endcase
            end 
        endcase
        // END CODE HERE
    end // always_comb

    //Assertions for testing FSM logic

    // Write assertions to verify your FSM transition sequence
    // Can you verify that:
    // 1) A validTri_R13H signal causes a transition from WAIT state to TEST state
    // 2) An end_box_R14H signal causes a transition from TEST state to WAIT state
    // 3) What are you missing?

    //Your assertions goes here
    // START CODE HERE
    // assert property(@(posedge clk) state_R14H==WAIT_STATE && validTri_R13H==1'b1 |-> next_state_R14H==TEST_STATE);
    // assert property(@(posedge clk) state_R14H==TEST_STATE && at_end_box_R14H==1'b1 |-> next_state_R14H==WAIT_STATE);
	// assert property( @(posedge clk) ((!validTri_R13H && (state_R14H == WAIT_STATE)) |-> (next_state_R14H == WAIT_STATE) ));
    // assert property( @(posedge clk) ((!at_end_box_R14H && (state_R14H == TEST_STATE)) |-> (next_state_R14H == TEST_STATE) ));
    // END CODE HERE
    // Assertion ends

    //////
    //////  RTL code for original FSM Finishes
    //////

     //Define a Less Than Property
    //
    //  a should be less than b
    property rb_lt( rst, a , b , c );
        @(posedge clk) rst | ((a<=b) | !c);
    endproperty

    //Check that Proposed Sample is in BBox
    // START CODE HERE
    // assert property( rb_lt( rst, next_sample_R14S[0], next_box_R14S[1][0], next_validSamp_R14H ));
    // assert property( rb_lt( rst, next_sample_R14S[1], next_box_R14S[1][1], next_validSamp_R14H ));

    // assert property( rb_lt( rst, next_box_R14S[0][0], next_sample_R14S[0], validTri_R13H ));
    // assert property( rb_lt( rst, next_box_R14S[0][1], next_sample_R14S[1], validTri_R13H ));

    // END CODE HERE
    //Check that Proposed Sample is in BBox

    //Error Checking Assertions
end 
else begin // Use modified FSM

    //////
    //////  RTL code for modified FSM Goes Here
    //////

    ////// PLACE YOUR CODE HERE

    //////
    //////  RTL code for modified FSM Finishes
    //////

end
endgenerate

endmodule   