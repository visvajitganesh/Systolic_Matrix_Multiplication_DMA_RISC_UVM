module processing_element #(
    parameter int DATA_WIDTH = 4,
    parameter int PSUM_WIDTH = 4
) (
    input  logic clk,
    input  logic rst,

    input  logic pe_en,

    // INPUT SIGNALS
    input  logic [DATA_WIDTH - 1 : 0] in,       // HORIZONTAL INPUTS
    input  logic [DATA_WIDTH - 1 : 0] weight,   // VERTICAL WEIGHT LOADING inputs
    input  logic [PSUM_WIDTH - 1 : 0] psum_in,  // PSUM 

    // OUTPUT SIGNALS
    output logic [DATA_WIDTH - 1 : 0]  a_out,  
    output logic [PSUM_WIDTH - 1 : 0]  psum_out
);
    /*
    logic [DATA_WIDTH - 1 : 0]  weight_reg;
    logic [DATA_WIDTH - 1 : 0]  a_reg;

    // WEIGHT - STATIONARY REGISTER LOGIC 
    always_ff @(posedge clk or posedge rst) begin : weight_stationary
        if(rst) begin
            weight_reg <= '0;
        end 
        else if (pe_en) begin
            weight_reg <= weight;
        end
    end

    // HORIZONTAL INPUT LOGIC 
    always_ff @(posedge clk or posedge rst) begin : weight_loading
        if(rst) begin
            a_reg <= '0;
            a_out <= '0;
        end 
        else if (pe_en) begin
            a_reg <= in;
            a_out <= in;
        end
    end
    */

    // OUTPUT LOGIC
    always_ff @(posedge clk or posedge rst) begin : mac
        if(rst) begin
            psum_out <= '0;
            a_out    <= '0;
        end 
        else if (pe_en) begin
            // FORMULA FOR MAC OPERATION: PSUM_OUTPUT = PSUM_INPUT + (WEIGHT * INPUT)
            psum_out <= psum_in + (weight * in);
            a_out    <= in;
        end
    end

endmodule

