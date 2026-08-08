`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
} axi_req_type_e;

class axi_lite_seq_item extends uvm_sequence_item;

    // Transaction parameters
    rand axi_req_type_e req_type;
    rand bit [31:0]     addr;
    rand bit [31:0]     data;     // Data to write (for WRITE)
    rand bit [3:0]      wstrb;    // Write strobe (usually 4'b1111)

    // Captured responses from the DUT (Not randomized)
    bit [31:0]          rdata;    // Data read back (for READ)
    bit [1:0]           resp;     // bresp or rresp status

    // UVM Automation Macros
    `uvm_object_utils_begin(axi_lite_seq_item)
        `uvm_field_enum(axi_req_type_e, req_type, UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(data,  UVM_ALL_ON)
        `uvm_field_int(wstrb, UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
        `uvm_field_int(resp,  UVM_ALL_ON)
    `uvm_object_utils_end

    // Constructor
    function new(string name = "axi_lite_seq_item");
        super.new(name);
    endfunction

    // Constraint: Usually we want full word accesses (4-byte aligned)
    constraint align_32 {
        addr % 4 == 0;
        wstrb == 4'b1111; 
    }

    virtual function string convert2string();
        if (req_type == AXI_WRITE)
            return $sformatf("WRITE -> Addr: 0x%08h | Data: 0x%08h | Strb: 4'b%04b | Resp: %0d", addr, data, wstrb, resp);
        else
            return $sformatf("READ  -> Addr: 0x%08h | RData: 0x%08h | Resp: %0d", addr, rdata, resp);
    endfunction

endclass