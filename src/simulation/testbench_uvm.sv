`include "uvm_macros.svh"
import uvm_pkg::*;

// Sequence Item
class ps2_item extends uvm_sequence_item;

	//bit ps2_clk;
	rand bit [9:0] ps2_dat;
	bit [15:0] out;
	
	`uvm_object_utils_begin(ps2_item)
		//`uvm_field_int(ps2_clk, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(ps2_dat, UVM_ALL_ON | UVM_BIN)
		`uvm_field_int(out, UVM_NOPRINT)
	`uvm_object_utils_end
	
	function new(string name = "ps2_item");
		super.new(name);
	endfunction
	
	virtual function string my_print();
		return $sformatf(
			"ps2_dat = %8b ps2_parity = %1b ps2_end = %1b out = %4h",
			ps2_dat[7:0], ps2_dat[8], ps2_dat[9], out
		);
	endfunction

endclass

// Sequence
class generator extends uvm_sequence;

	`uvm_object_utils(generator)
	
	function new(string name = "generator");
		super.new(name);
	endfunction
	
	int num = 2000;
	
	virtual task body();
		for (int i = 0; i < num; i++) begin
			ps2_item item = ps2_item::type_id::create("item");
			start_item(item);
			if(i % 4 == 0 && i > 0) begin
				item.ps2_dat = 10'b1111110000;
			end else begin
			 	item.randomize();
			end
			`uvm_info("Generator", $sformatf("Item %0d/%0d created", i + 1, num), UVM_LOW)
			item.print();
			finish_item(item);
		end

	endtask
	
endclass

// Driver
class driver extends uvm_driver #(ps2_item);
	
	`uvm_component_utils(driver)
	
	function new(string name = "driver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual ps2_if vif;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual ps2_if)::get(this, "", "ps2_vif", vif))
			`uvm_fatal("Driver", "No interface.")
	endfunction
	
	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		forever begin
			ps2_item item;
			seq_item_port.get_next_item(item);
			`uvm_info("Driver", $sformatf("%s", item.my_print()), UVM_LOW)
			vif.ps2_dat <= 1'b0;
			@(negedge vif.ps2_clk);
			
			@(posedge vif.clk);
			for(int i = 0; i < 10; i++) begin
				vif.ps2_dat <= item.ps2_dat[i];
				@(negedge vif.ps2_clk);
				
				@(posedge vif.clk);
			end
			seq_item_port.item_done();
		end
	endtask
	
endclass

// Monitor

class monitor extends uvm_monitor;
	
	`uvm_component_utils(monitor)
	
	function new(string name = "monitor", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual ps2_if vif;
	uvm_analysis_port #(ps2_item) mon_analysis_port;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual ps2_if)::get(this, "", "ps2_vif", vif))
			`uvm_fatal("Monitor", "No interface.")
		mon_analysis_port = new("mon_analysis_port", this);
	endfunction

	virtual task run_phase(uvm_phase phase);	
		super.run_phase(phase);
		//@(posedge vif.ps2_clk);
		//@(negedge vif.clk);
		forever begin
			ps2_item item = ps2_item::type_id::create("item");
			@(negedge vif.ps2_clk);
			@(posedge vif.clk);
			item.ps2_dat[0] = vif.ps2_dat;
			item.out = vif.out;
			`uvm_info("Monitor", $sformatf("ps2_dat = %1b, out = %4h", item.ps2_dat[0], vif.out), UVM_LOW)
			mon_analysis_port.write(item);
		end
	endtask
	
endclass

// Agent
class agent extends uvm_agent;
	
	`uvm_component_utils(agent)
	
	function new(string name = "agent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	driver d0;
	monitor m0;
	uvm_sequencer #(ps2_item) s0;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		d0 = driver::type_id::create("d0", this);
		m0 = monitor::type_id::create("m0", this);
		s0 = uvm_sequencer#(ps2_item)::type_id::create("s0", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		d0.seq_item_port.connect(s0.seq_item_export);
	endfunction
	
endclass

// Scoreboard
class scoreboard extends uvm_scoreboard;
	
	`uvm_component_utils(scoreboard)
	
	function new(string name = "scoreboard", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	uvm_analysis_imp #(ps2_item, scoreboard) mon_analysis_imp;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		mon_analysis_imp = new("mon_analysis_imp", this);
	endfunction
	
	bit [15:0] ps2 = 16'h0000; //to mi je ps2_out
	bit [7:0] ps2_data;
	bit ps2_parity = 1'b1;
	bit ps2_parity_err = 1'b0;
	bit [3:0] data_cnt=4'h0; //ide do 11 tj do 4'hB
	bit [2:0] i = 3'b000;
	bit ps2_posedge = 1'b1;
	bit ps2_curr_bit;
	
	localparam start_state  = 1;
    localparam data_state   = 2;
    localparam parity_state = 3;
    localparam end_state    = 4;
	localparam check_state = 5;

	int state = start_state;

	virtual function write(ps2_item item);
		ps2_curr_bit = item.ps2_dat[0];
		case (state)
            start_state: begin
                if ((ps2_curr_bit == 1'b0) && (ps2_posedge == 1'b1)) begin
                    state = data_state;
					ps2_parity_err = 1'b0;
                end
            end
            data_state: begin
                if (ps2_posedge == 1'b1) begin
                    ps2_data = {ps2_curr_bit, ps2_data[7:1]};
                    if (data_cnt == 4'h7) begin
                        data_cnt = 4'h0;
                        state    = parity_state;
                        end else begin
                            data_cnt = data_cnt + 1'b1;
                        end
                    end
                end
			parity_state:
			begin
				if (ps2_posedge == 1'b1) begin
					state = end_state;
					for(int i = 0; i < 8; i++) begin
						ps2_parity = ps2_parity ^ ps2_data[i];
					end
					if(ps2_parity != ps2_curr_bit) begin
						ps2_parity_err = 1'b1;
						//`uvm_error("Scoreboard", $sformatf("FAIL! Parity bit error, expected = %b, got = %b", ps2_parity, ps2_curr_bit))
					end
					ps2_parity = 1'b1;
				end
			end
			end_state:
			begin
				if (ps2_posedge == 1'b1) begin
					if(ps2_curr_bit == 1'b1) begin
						if(ps2_parity_err == 1'b0) begin
							if (i == 3'b000) begin
								ps2 = ps2_data;
								if(ps2_data == 8'hF0) begin
									i = 3'b000;
								end else begin
									i   = 3'b001;
								end	
							end else if (i == 3'b001) begin
								if (ps2_data == 8'hF0) begin
									i   = 3'b011;
									ps2 = {ps2_data , ps2[7:0]};
								end else if (ps2_data == ps2[7:0]) begin
									ps2 = ps2_data;
									i   = 3'b010;
								end else begin
									ps2 = { ps2[7:0], ps2_data};
									i   = 3'b100;
								end
							end else if (i == 3'b010) begin
								if (ps2_data == 8'hF0) begin
									i   = 3'b011;
									ps2 = {ps2_data , ps2[7:0]};
								end else begin
									i = 3'b010;
								end
							end else if (i == 3'b011) begin // zavrsno
								i = 3'b000;
							end else if (i == 3'b100) begin
								if (ps2_data == 8'hF0) begin
									i = 3'b011;
								end else begin
									i = 3'b100;
								end
							end
							if (ps2 == item.out)
							`uvm_info("Scoreboard", $sformatf("PASS! expected = %4h, got = %4h",  ps2, item.out), UVM_LOW)
							else
								`uvm_error("Scoreboard", $sformatf("FAIL! expected = %4h, got = %4h", ps2, item.out))
						end
					end else begin
						//`uvm_error("Scoreboard", $sformatf("FAIL! End bit error, expected = 1, got = %b", ps2_curr_bit))
					end
					state    = start_state;
					ps2_data = 8'h00;
				end
			end
			default:
			state = start_state;
        endcase
		
		
	endfunction
	
endclass

// Environment
class env extends uvm_env;
	
	`uvm_component_utils(env)
	
	function new(string name = "env", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	agent a0;
	scoreboard sb0;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		a0 = agent::type_id::create("a0", this);
		sb0 = scoreboard::type_id::create("sb0", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		a0.m0.mon_analysis_port.connect(sb0.mon_analysis_imp);
	endfunction
	
endclass

// Test
class test extends uvm_test;

	`uvm_component_utils(test)
	
	function new(string name = "test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual ps2_if vif;

	env e0;
	generator g0;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual ps2_if)::get(this, "", "ps2_vif", vif))
			`uvm_fatal("Test", "No interface.")
		e0 = env::type_id::create("e0", this);
		g0 = generator::type_id::create("g0");
	endfunction
	
	virtual function void end_of_elaboration_phase(uvm_phase phase);
		uvm_top.print_topology();
	endfunction
	
	virtual task run_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		vif.rst_n <= 0;
		#20 vif.rst_n <= 1;
		
		g0.start(e0.a0.s0);
		phase.drop_objection(this);
	endtask

endclass

// Interface
interface ps2_if (
	input bit clk,
	input bit ps2_clk
);

	logic rst_n;
    logic ps2_dat;
    logic [15:0] out;

endinterface

// Testbench
module testbench_uvm;

	reg clk;
	reg ps2_clk;
	
	ps2_if dut_if (
		.clk(clk),
		.ps2_clk(ps2_clk)
	);
	
	ps2 dut (
		.clk(clk),
		.ps2_clk(dut_if.ps2_clk),
		.rst_n(dut_if.rst_n),
		.ps2_dat(dut_if.ps2_dat),
		.out(dut_if.out)
	);

	initial begin
		clk = 0;
		forever begin
			#5 clk = ~clk;
		end
	end

	initial begin
		ps2_clk = 0;
		forever begin
			#499 ps2_clk = ~ps2_clk;
		end
	end

	initial begin
		uvm_config_db#(virtual ps2_if)::set(null, "*", "ps2_vif", dut_if);
		run_test("test");
	end

endmodule
