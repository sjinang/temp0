/*
 * Bounding Box Module
 *
 * Inputs:
 *   3 x,y,z vertices corresponding to tri
 *   1 valid bit, indicating triangle is valid data
 *
 *  Config Inputs:
 *   2 x,y vertices indicating screen dimensions
 *   1 integer representing square root of SS (16MSAA->4)
 *      we will assume config values are held in some
 *      register and are valid given a valid triangle
 *
 *  Control Input:
 *   1 halt signal indicating that no work should be done
 *
 * Outputs:
 *   2 vertices describing a clamped bounding box
 *   1 Valid signal indicating that bounding
 *           box and triangle value is valid
 *   3 x,y vertices corresponding to tri
 *
 * Global Signals:
 *   clk, rst
 *
 * Function:
 *   Determine a bounding box for the triangle
 *   represented by the vertices.
 *
 *   Clamp the Bounding Box to the subsample pixel
 *   space
 *
 *   Clip the Bounding Box to Screen Space
 *
 *   Halt operating but retain values if next stage is busy
 *
 *
 * Long Description:
 *   This bounding box block accepts a triangle described with three
 *   vertices and determines a set of sample points to test against
 *   the triangle.  These sample points correspond to the
 *   either the pixels in the final image or the pixel fragments
 *   that compose the pixel if multisample anti-aliasing (MSAA)
 *   is enabled.
 *
 *   The inputs to the box are clocked with a bank of dflops.
 *
 *   After the data is clocked, a bounding box is determined
 *   for the triangle. A bounding box can be determined
 *   through calculating the maxima and minima for x and y to
 *   generate a lower left vertice and upper right
 *   vertice.  This data is then clocked.
 *
 *   The bounding box next needs to be clamped to the fragment grid.
 *   This can be accomplished through rounding the bounding box values
 *   to the fragment grid.  Additionally, any sample points that exist
 *   outside of screen space should be rejected.  So the bounding box
 *   can be clipped to the visible screen space.  This clipping is done
 *   using the screen signal.
 *
 *   The Halt signal is utilized to hold the current triangle bounding box.
 *   This is because one bounding box operation could correspond to
 *   multiple sample test operations later in the pipe.  As these samples
 *   can take a number of cycles to complete, the data held in the bounding
 *   box stage needs to be preserved.  The halt signal is also required for
 *   when the write device is full/busy.
 *
 *   The valid signal is utilized to indicate whether or not a triangle
 *   is actual data.  This can be useful if the device being read from,
 *   has no more triangles.
 *
 *
 *
 *   Author: John Brunhaver
 *   Created:      Thu 07/23/09
 *   Last Updated: Fri 09/30/10
 *
 *   Copyright 2009 <jbrunhaver@gmail.com>
 */


/* A Note on Signal Names:
 *
 * Most signals have a suffix of the form _RxxxxN
 * where R indicates that it is a Raster Block signal
 * xxxx indicates the clock slice that it belongs to
 * N indicates the type of signal that it is.
 *    H indicates logic high,
 *    L indicates logic low,
 *    U indicates unsigned fixed point,
 *    S indicates signed fixed point.
 *
 * For all the signed fixed point signals (logic signed [SIGFIG-1:0]),
 * their highest `$sig_fig-$radix` bits, namely [`$sig_fig-1`:RADIX]
 * represent the integer part of the fixed point number,
 * while the lowest RADIX bits, namely [`$radix-1`:0]
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

module bbox
#(
    parameter SIGFIG        = 24, // Bits in color and position.
    parameter RADIX         = 10, // Fraction bits in color and position
    parameter VERTS         = 4, // Maximum Vertices in triangle
    parameter AXIS          = 3, // Number of axis foreach vertex 3 is (x,y,z).
    parameter COLORS        = 3, // Number of color channels
    parameter PIPE_DEPTH    = 3 // How many pipe stages are in this block
)
(
    //Input Signals
    input logic signed [SIGFIG-1:0]     tri_R10S[VERTS-1:0][AXIS-1:0] , // Sets X,Y Fixed Point Values
    input logic unsigned [SIGFIG-1:0]   color_R10U[COLORS-1:0] , // Color of Tri
    input logic                             validTri_R10H , // Valid Data for Operation

    //Control Signals
    input logic                         halt_RnnnnL , // Indicates No Work Should Be Done
    input logic signed [SIGFIG-1:0] screen_RnnnnS[1:0] , // Screen Dimensions
    input logic [3:0]                   subSample_RnnnnU , // SubSample_Interval
    //input logic                         Is_Triangle, //1 => triangle, 0 => quadrilateral

    //Global Signals
    input logic clk, // Clock
    input logic rst, // Reset

    //Outout Signals
    output logic signed [SIGFIG-1:0]    tri_R13S[VERTS-1:0][AXIS-1:0], // 4 Sets X,Y Fixed Point Values
    output logic unsigned [SIGFIG-1:0]  color_R13U[COLORS-1:0] , // Color of Tri
    output logic signed [SIGFIG-1:0]    box_R13S[1:0][1:0], // 2 Sets X,Y Fixed Point Values
    output logic                            validTri_R13H                  // Valid Data for Operation
);

    //Signals In Clocking Order

    //Begin R10 Signals

    // Step 1 Result: LL and UR X, Y Fixed Point Values determined by calculating min/max vertices
    // box_R10S[0][0]: LL X
    // box_R10S[0][1]: LL Y
    // box_R10S[1][0]: UR X
    // box_R10S[1][1]: UR Y
    logic signed [SIGFIG-1:0]   box_R10S[1:0][1:0];
    // Step 2 Result: LL and UR Rounded Down to SubSample Interval
    logic signed [SIGFIG-1:0]   rounded_box_R10S[1:0][1:0];
    // Step 3 Result: LL and UR X, Y Fixed Point Values after Clipping
    logic signed [SIGFIG-1:0]   out_box_R10S[1:0][1:0];      // bounds for output
    // Step 3 Result: valid if validTri_R10H && BBox within screen
    logic                           outvalid_R10H;               // output is valid

    //End R10 Signals

    // Begin output for retiming registers
    logic signed [SIGFIG-1:0]   tri_R13S_retime[VERTS-1:0][AXIS-1:0]; // 4 Sets X,Y Fixed Point Values
    logic unsigned [SIGFIG-1:0] color_R13U_retime[COLORS-1:0];        // Color of Tri
    logic signed [SIGFIG-1:0]   box_R13S_retime[1:0][1:0];             // 2 Sets X,Y Fixed Point Values
    logic                           validTri_R13H_retime ;                 // Valid Data for Operation
    // End output for retiming registers

    // ********** Step 1:  Determining a Bounding Box **********
    // Here you need to determine the bounding box by comparing the vertices
    // and assigning box_R10S to be the proper coordinates

    // START CODE HERE

    // This select signal structure may help you in selecting your bbox coordinates
    logic [3:0] bbox_sel_R10H [1:0][1:0];
    // The above structure consists of a 3-bit select signal for each coordinate of the 
    // bouding box. The leftmost [1:0] dimensions refer to LL/UR, while the rightmost 
    // [1:0] dimensions refer to X or Y coordinates. Each select signal should be a 3-bit 
    // one-hot signal, where the bit that is high represents which one of the 3 triangle vertices 
    // should be chosen for that bbox coordinate. As an example, if we have: bbox_sel_R10H[0][0] = 3'b001
    // then this indicates that the lower left x-coordinate of your bounding box should be assigned to the 
    // x-coordinate of triangle "vertex a". 
    
    //  DECLARE ANY OTHER SIGNALS YOU NEED
    logic [RADIX-4:0]   zero_append;
    logic [RADIX:0]     mask_intermediate;
    logic [RADIX-1:0]   and_mask;
    logic outvalid_bbox;
    int mask_width = RADIX - 1;

    // Backfacing Culling
    logic signed [2*SIGFIG-18:0] triangle_edges [1:0][1:0];
    logic signed [2*SIGFIG-18:0] crossproduct;
    logic to_cull;
    
    // Bubble Smashing 
    logic halt_bubble;
    logic                         Is_Triangle, //1 => triangle, 0 => quadrilateral
    assign Is_Triangle = 1'b1;
    assign halt_bubble = halt_RnnnnL; //|| ~validTri_R13H;

    always_comb begin //logic related to backface culling
        triangle_edges[0][0] = tri_R10S[1][0][SIGFIG-1:0] - tri_R10S[0][0][SIGFIG-1:0];
        triangle_edges[0][1] = tri_R10S[1][1][SIGFIG-1:0] - tri_R10S[0][1][SIGFIG-1:0];

        triangle_edges[1][0] = tri_R10S[2][0][SIGFIG-1:0] - tri_R10S[1][0][SIGFIG-1:0];
        triangle_edges[1][1] = tri_R10S[2][1][SIGFIG-1:0] - tri_R10S[1][1][SIGFIG-1:0];

        crossproduct = (triangle_edges[0][0]*triangle_edges[1][1])-(triangle_edges[0][1]*triangle_edges[1][0]); //z output of cross product
        to_cull = (crossproduct[2*SIGFIG-18] == 1'b0) ? 1'b1 : 1'b0; 
    end 


    // ADDIONAL ASSIGNMENTS
    assign zero_append = 0; // Lint clean
    assign and_mask_intermediate = {subSample_RnnnnU, zero_append} - 1'b1; // Lint clean
    assign and_mask = ~(and_mask_intermediate); 

    // Try declaring an always_comb block to assign values to box_R10S

    always_comb begin
        //[0][0]: LL X; [0][1]: LL Y; [1][0]: UR X; [1][1]: UR Y;
        // Initializing the bbox with first vertex
        // Initializing the bbox with first vertex

        // TODO: Might be better to spilt into 4 chunks as the if conditions are independent 
        // and donot need to be executed in order (decouple from compiler dependent opt)
        // if it's a triangle
		case({(Is_Triangle == 1'b1), (tri_R10S[0][0] <= tri_R10S[1][0]),(tri_R10S[0][0] <= tri_R10S[2][0]),(tri_R10S[1][0] <= tri_R10S[2][0])})
            4'b1000: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b0001;end
            4'b1001: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b0001;end
            4'b1011: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b0100;end
            4'b1100: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b0010;end
            4'b1110: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0010;end
            4'b1111: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0100;end
            default: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0001;end
		endcase 
		
		case({(Is_Triangle == 1'b1),(tri_R10S[0][1] <= tri_R10S [1][1]),(tri_R10S[0][1] <= tri_R10S[2][1]),(tri_R10S[1][1] <= tri_R10S[2][1])})
			4'b1000: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b0001;end
			4'b1001: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b0001;end
			4'b1011: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b0100;end
			4'b1100: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b0010;end
			4'b1110: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0010;end
			4'b1111: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0100;end
			default: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0001;end
		endcase 

        // if it's a quadrilateral (Is_Triangle == 1'b0)
		case({(Is_Triangle == 1'b0),(tri_R10S[0][0] <= tri_R10S[1][0]),(tri_R10S[0][0] <= tri_R10S[2][0]),(tri_R10S[0][0] <= tri_R10S[3][0]),
        (tri_R10S[1][0] <= tri_R10S[2][0]),(tri_R10S[1][0] <= tri_R10S[3][0]),(tri_R10S[2][0] <= tri_R10S[3][0])})
            //7'b0xx0x00
            7'b0000000: begin bbox_sel_R10H[0][0] = 4'b1000; bbox_sel_R10H[1][0] = 4'b0001;end
            7'b0000100: begin bbox_sel_R10H[0][0] = 4'b1000; bbox_sel_R10H[1][0] = 4'b0001;end
            7'b0010100: begin bbox_sel_R10H[0][0] = 4'b1000; bbox_sel_R10H[1][0] = 4'b0100;end
            7'b0100000: begin bbox_sel_R10H[0][0] = 4'b1000; bbox_sel_R10H[1][0] = 4'b0010;end
            7'b0110000: begin bbox_sel_R10H[0][0] = 4'b1000; bbox_sel_R10H[1][0] = 4'b0010;end
            7'b0110100: begin bbox_sel_R10H[0][0] = 4'b1000; bbox_sel_R10H[1][0] = 4'b0100;end
            
            //7'b0x0x0x1
            7'b0000001: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b0001;end
            7'b0000011: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b0001;end
            7'b0001011: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b1000;end
            7'b0100001: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b0010;end
            7'b0101001: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b0010;end
            7'b0101011: begin bbox_sel_R10H[0][0] = 4'b0100; bbox_sel_R10H[1][0] = 4'b1000;end
            
            //7'b00xx11x
            7'b0000110: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b0001;end
            7'b0000111: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b0001;end
            7'b0001111: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b1000;end
            7'b0010110: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b0100;end
            7'b0011110: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b0100;end
            7'b0011111: begin bbox_sel_R10H[0][0] = 4'b0010; bbox_sel_R10H[1][0] = 4'b1000;end

            //7'b0111xxx
            7'b0111000: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0010;end
            7'b0111001: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0010;end
            7'b0111011: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b1000;end
            7'b0111100: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0100;end
            7'b0111110: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0100;end
            7'b0111111: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b1000;end
            default: begin bbox_sel_R10H[0][0] = 4'b0001; bbox_sel_R10H[1][0] = 4'b0001;end
		endcase 
		
		case({(Is_Triangle == 1'b0),(tri_R10S[0][1] <= tri_R10S [1][1]),(tri_R10S[0][1] <= tri_R10S[2][1]),((tri_R10S[0][1] <= tri_R10S[3][1])),
        (tri_R10S[1][1] <= tri_R10S[2][1]),(tri_R10S[1][1] <= tri_R10S[3][1]),(tri_R10S[2][1] <= tri_R10S[3][1])})
			//6'bxx0x00
            7'b0000000: begin bbox_sel_R10H[0][1] = 4'b1000; bbox_sel_R10H[1][1] = 4'b0001;end
            7'b0000100: begin bbox_sel_R10H[0][1] = 4'b1000; bbox_sel_R10H[1][1] = 4'b0001;end
            7'b0010100: begin bbox_sel_R10H[0][1] = 4'b1000; bbox_sel_R10H[1][1] = 4'b0100;end
            7'b0100000: begin bbox_sel_R10H[0][1] = 4'b1000; bbox_sel_R10H[1][1] = 4'b0010;end
            7'b010000: begin bbox_sel_R10H[0][1] = 4'b1000; bbox_sel_R10H[1][1] = 4'b0010;end
            7'b0110100: begin bbox_sel_R10H[0][1] = 4'b1000; bbox_sel_R10H[1][1] = 4'b0100;end
            
            //6'bx0x0x1
            7'b0000001: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b0001;end
            7'b0000011: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b0001;end
            7'b0001011: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b1000;end
            7'b0100001: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b0010;end
            7'b0101001: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b0010;end
            7'b0101011: begin bbox_sel_R10H[0][1] = 4'b0100; bbox_sel_R10H[1][1] = 4'b1000;end
            
            //6'b0xx11x
            7'b0000110: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b0001;end
            7'b0000111: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b0001;end
            7'b0001111: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b1000;end
            7'b0010110: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b0100;end
            7'b0011110: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b0100;end
            7'b0011111: begin bbox_sel_R10H[0][1] = 4'b0010; bbox_sel_R10H[1][1] = 4'b1000;end

            //6'b111xxx
            7'b0111000: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0010;end
            7'b0111001: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0010;end
            7'b0111011: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b1000;end
            7'b0111100: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0100;end
            7'b0111110: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0100;end
            7'b0111111: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b1000;end
            default: begin bbox_sel_R10H[0][1] = 4'b0001; bbox_sel_R10H[1][1] = 4'b0001;end
		endcase



		case (bbox_sel_R10H [0][0])
			4'b0001: box_R10S[0][0] = tri_R10S[0][0];
			4'b0010: box_R10S[0][0] = tri_R10S[1][0];
			4'b0100: box_R10S[0][0] = tri_R10S[2][0];
            4'b1000: box_R10S[0][0] = tri_R10S[3][0];
			default: box_R10S[0][0] = tri_R10S[0][0];
		endcase

		case (bbox_sel_R10H [0][1])
			4'b0001: box_R10S[0][1] = tri_R10S[0][1];
			4'b0010: box_R10S[0][1] = tri_R10S[1][1];
			4'b0100: box_R10S[0][1] = tri_R10S[2][1];
            4'b1000: box_R10S[0][1] = tri_R10S[3][1];
			default: box_R10S[0][1] = tri_R10S[0][1];
		endcase

		case (bbox_sel_R10H [1][0])
			4'b0001: box_R10S[1][0] = tri_R10S[0][0];
			4'b0010: box_R10S[1][0] = tri_R10S[1][0];
			4'b0100: box_R10S[1][0] = tri_R10S[2][0];
            4'b1000: box_R10S[1][0] = tri_R10S[3][0];
			default: box_R10S[1][0] = tri_R10S[0][0];
		endcase

		case (bbox_sel_R10H [1][1])
			4'b0001: box_R10S[1][1] = tri_R10S[0][1];
			4'b0010: box_R10S[1][1] = tri_R10S[1][1];
			4'b0100: box_R10S[1][1] = tri_R10S[2][1];
            4'b1000: box_R10S[1][1] = tri_R10S[3][1];
			default: box_R10S[1][1] = tri_R10S[0][1];
		endcase
	end

    // END CODE HERE

    // Assertions to check if box_R10S is assigned properly
    // We want to check the following properties:
    // 1) Each of the coordinates box_R10S are always and uniquely assigned
    // 2) Upper right coordinate is never less than lower left

    // START CODE HERE
    //Assertions to check if all cases are covered and assignments are unique 
    // (already done for you if you use the bbox_sel_R10H select signal as declared)
    assert property(@(posedge clk) $onehot(bbox_sel_R10H[0][0]));
    assert property(@(posedge clk) $onehot(bbox_sel_R10H[0][1]));
    assert property(@(posedge clk) $onehot(bbox_sel_R10H[1][0]));
    assert property(@(posedge clk) $onehot(bbox_sel_R10H[1][1]));

    //Assertions to check UR is never less than LL
    property rb_lt1(rst, a, b);
        @(posedge clk) rst | (a<=b) ;
    endproperty

    assert property( rb_lt1( rst, box_R10S[0][0], box_R10S[1][0]));
    assert property( rb_lt1( rst, box_R10S[0][1], box_R10S[1][1]));    
    // END CODE HERE


    // ***************** End of Step 1 *********************


    // ********** Step 2:  Round Values to Subsample Interval **********

    // We will use the floor operation for rounding.
    // To floor a signal, we simply turn all of the bits
    // below a specific RADIX to 0.
    // The complication here is that there are 4 setting.
    // 1x MSAA eq. to 1 sample per pixel
    // 4x MSAA eq to 4 samples per pixel, a sample is
    // half a pixel on a side
    // 16x MSAA eq to 16 sample per pixel, a sample is
    // a quarter pixel on a side.
    // 64x MSAA eq to 64 samples per pixel, a sample is
    // an eighth of a pixel on a side.

    // Note: Cleverly converting the MSAA signal
    //       to a mask would allow you to do this operation
    //       as a bitwise and operation.

//Round LowerLeft and UpperRight for X and Y
logic [RADIX-1:0] mask;
// assign mask = (~((subSample_RnnnnU<<(RADIX-3))-1));
assign mask = (~({subSample_RnnnnU,{(RADIX-3){1'b0}}}-1'b1));

//Round LowerLeft and UpperRight for X and Y
generate
for(genvar i = 0; i < 2; i = i + 1) begin
    for(genvar j = 0; j < 2; j = j + 1) begin

        always_comb begin
            //Integer Portion of LL and UR Remains the Same
            rounded_box_R10S[i][j][SIGFIG-1:RADIX] = box_R10S[i][j][SIGFIG-1:RADIX];

            // TODO : Can alternatively be implemented using multiple bit selection
            //rounded_box_R10S[i][j][RADIX-1:0]   = box_R10S[i][j][RADIX-1:0] & and_mask;
            
            rounded_box_R10S[i][j][RADIX-1:0] = box_R10S[i][j][RADIX-1:0] & mask;
        end // always_comb

    end
end
endgenerate

    //Assertion to help you debug errors in rounding
    assert property( @(posedge clk) (box_R10S[0][0] - rounded_box_R10S[0][0]) <= {subSample_RnnnnU,7'b0});
    assert property( @(posedge clk) (box_R10S[0][1] - rounded_box_R10S[0][1]) <= {subSample_RnnnnU,7'b0});
    assert property( @(posedge clk) (box_R10S[1][0] - rounded_box_R10S[1][0]) <= {subSample_RnnnnU,7'b0});
    assert property( @(posedge clk) (box_R10S[1][1] - rounded_box_R10S[1][1]) <= {subSample_RnnnnU,7'b0});

    // ***************** End of Step 2 *********************


    // ********** Step 3:  Clipping or Rejection **********

    // Clamp if LL is down/left of screen origin
    // Clamp if UR is up/right of Screen
    // Invalid if BBox is up/right of Screen
    // Invalid if BBox is down/left of Screen
    // outvalid_R10H high if validTri_R10H && BBox is valid

    always_comb begin

        //////// ASSIGN "out_box_R10S" and "outvalid_R10H"
        // START CODE HERE
    
        outvalid_bbox = 1'b1;
        // below/left of the screen or above/right
        case ({(rounded_box_R10S[0][1] > screen_RnnnnS[1]),
                (rounded_box_R10S[0][1] > screen_RnnnnS[1]),
                (rounded_box_R10S[1][0][SIGFIG-1]),
                (rounded_box_R10S[1][1][SIGFIG-1]),
                to_cull,
                validTri_R10H})
            6'b000001: outvalid_R10H = 1'b1;
            default: outvalid_R10H = 1'b0;  
        endcase


         // initialize out_box with rounded_box to be used later for clipping
        // Clip the bbox to screen dimensions
        case ((rounded_box_R10S[0][0][SIGFIG-1]))
            1'b1: out_box_R10S[0][0] = 0;
            default: out_box_R10S[0][0] = rounded_box_R10S[0][0];
        endcase    
        case ((rounded_box_R10S[0][1][SIGFIG-1]))
            1'b1: out_box_R10S[0][1] = 0;
            default: out_box_R10S[0][1] = rounded_box_R10S[0][1];
        endcase   
        case ((rounded_box_R10S[1][0] > screen_RnnnnS[0]))
            1'b1: out_box_R10S[1][0] = screen_RnnnnS[0];
            default: out_box_R10S[1][0] = rounded_box_R10S[1][0];
        endcase   
        case ((rounded_box_R10S[1][1] > screen_RnnnnS[1]))
            1'b1: out_box_R10S[1][1] = screen_RnnnnS[1];
            default: out_box_R10S[1][1] = rounded_box_R10S[1][1];
        endcase     
        // END CODE HERE

    end

    //Assertion for checking if outvalid_R10H has been assigned properly
    assert property( @(posedge clk) (outvalid_R10H |-> out_box_R10S[1][0] <= screen_RnnnnS[0] ));
    assert property( @(posedge clk) (outvalid_R10H |-> out_box_R10S[1][1] <= screen_RnnnnS[1] ));

    // ***************** End of Step 3 *********************

    dff3 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE1(VERTS),
        .ARRAY_SIZE2(AXIS),
        .PIPE_DEPTH(PIPE_DEPTH - 1),
        .RETIME_STATUS(1)
    )
    d_bbx_r1
    (
        .clk    (clk                ),
        .reset  (rst                ),
        .en     (halt_bubble        ),
        .in     (tri_R10S          ),
        .out    (tri_R13S_retime   )
    );

    dff2 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE(COLORS),
        .PIPE_DEPTH(PIPE_DEPTH - 1),
        .RETIME_STATUS(1)
    )
    d_bbx_r2
    (
        .clk    (clk                ),
        .reset  (rst                ),
        .en     (halt_bubble        ),
        .in     (color_R10U         ),
        .out    (color_R13U_retime  )
    );

    dff3 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE1(2),
        .ARRAY_SIZE2(2),
        .PIPE_DEPTH(PIPE_DEPTH - 1),
        .RETIME_STATUS(1)
    )
    d_bbx_r3
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (halt_bubble    ),
        .in     (out_box_R10S   ),
        .out    (box_R13S_retime)
    );

    dff_retime #(
        .WIDTH(1),
        .PIPE_DEPTH(PIPE_DEPTH - 1),
        .RETIME_STATUS(1) // Retime
    )
    d_bbx_r4
    (
        .clk    (clk                    ),
        .reset  (rst                    ),
        .en     (halt_bubble            ),
        .in     (outvalid_R10H          ),
        .out    (validTri_R13H_retime   )
    );
    //Flop Clamped Box to R13_retime with retiming registers

    //Flop R13_retime to R13 with fixed registers
    dff3 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE1(VERTS),
        .ARRAY_SIZE2(AXIS),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0)
    )
    d_bbx_f1
    (
        .clk    (clk                ),
        .reset  (rst                ),
        .en     (halt_bubble        ),
        .in     (tri_R13S_retime    ),
        .out    (tri_R13S           )
    );

    dff2 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE(COLORS),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0)
    )
    d_bbx_f2
    (
        .clk    (clk                ),
        .reset  (rst                ),
        .en     (halt_bubble        ),
        .in     (color_R13U_retime  ),
        .out    (color_R13U         )
    );

    dff3 #(
        .WIDTH(SIGFIG),
        .ARRAY_SIZE1(2),
        .ARRAY_SIZE2(2),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0)
    )
    d_bbx_f3
    (
        .clk    (clk            ),
        .reset  (rst            ),
        .en     (halt_bubble    ),
        .in     (box_R13S_retime),
        .out    (box_R13S       )
    );

    dff #(
        .WIDTH(1),
        .PIPE_DEPTH(1),
        .RETIME_STATUS(0) // No retime
    )
    d_bbx_f4
    (
        .clk    (clk                    ),
        .reset  (rst                    ),
        .en     (halt_bubble            ),
        .in     (validTri_R13H_retime   ),
        .out    (validTri_R13H          )
    );
    //Flop R13_retime to R13 with fixed registers

    //Error Checking Assertions

    //Define a Less Than Property
    //
    //  a should be less than b
    property rb_lt( rst, a, b, c );
        @(posedge clk) rst | ((a<=b) | !c);
    endproperty

    //Check that Lower Left of Bounding Box is less than equal Upper Right
    assert property( rb_lt( rst, box_R13S[0][0], box_R13S[1][0], validTri_R13H ));
    assert property( rb_lt( rst, box_R13S[0][1], box_R13S[1][1], validTri_R13H ));
    //Check that Lower Left of Bounding Box is less than equal Upper Right

    //Error Checking Assertions

endmodule