module pe_int4 #(
    parameter int DATA_WIDTH = 4,
    parameter int PSUM_WIDTH = 16
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    weight_en,
    input  logic                    pe_en,
    input  logic                    mul_en,
    //input  logic                    adder_en, // (Currently unused but wired up)

    // INPUT SIGNALS
    input  logic [DATA_WIDTH -1:0]  in,       // HORIZONTAL INPUTS
    input  logic [DATA_WIDTH -1:0]  weight,   // VERTICAL WEIGHT LOADING inputs
    input  logic [PSUM_WIDTH -1:0]  psum,     // PSUM 

    // OUTPUT SIGNALS
    output logic [DATA_WIDTH -1:0]  row_out,  
    output logic [PSUM_WIDTH -1:0]  pe_output
);

    logic [DATA_WIDTH -1:0]  weight_reg;
    logic [DATA_WIDTH -1:0]  row_reg;

    // WEIGHT - STATIONARY REGISTER LOGIC 
    always_ff @(posedge clk or posedge rst) begin : weight_stationary
        if(rst) begin
            weight_reg <= '0;
        end else if (weight_en) begin
            weight_reg <= weight;
        end
    end

    // HORIZONTAL INPUT LOGIC 
    always_ff @(posedge clk or posedge rst) begin : weight_loading
        if(rst) begin
            row_reg <= '0;
            row_out <= '0;
        end else if (pe_en) begin
            row_reg <= in;
            row_out <= in;
        end
    end

    // MAC LOGIC 
    always_ff @(posedge clk or posedge rst) begin : mac
        if(rst) begin
            pe_output <= '0;
        end else if (mul_en) begin
            // FORMULA FOR MAC OPERATION: PSUM_OUTPUT = PSUM_INPUT + (WEIGHT * INPUT)
            pe_output <= psum + (weight_reg * row_reg);
        end
    end

endmodule

