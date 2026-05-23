
module jtag_uart_0 (
	clk_clk,
	reset_reset_n,
	jtag_uart_0_avalon_jtag_slave_chipselect,
	jtag_uart_0_avalon_jtag_slave_address,
	jtag_uart_0_avalon_jtag_slave_read_n,
	jtag_uart_0_avalon_jtag_slave_readdata,
	jtag_uart_0_avalon_jtag_slave_write_n,
	jtag_uart_0_avalon_jtag_slave_writedata,
	jtag_uart_0_avalon_jtag_slave_waitrequest);	

	input		clk_clk;
	input		reset_reset_n;
	input		jtag_uart_0_avalon_jtag_slave_chipselect;
	input		jtag_uart_0_avalon_jtag_slave_address;
	input		jtag_uart_0_avalon_jtag_slave_read_n;
	output	[31:0]	jtag_uart_0_avalon_jtag_slave_readdata;
	input		jtag_uart_0_avalon_jtag_slave_write_n;
	input	[31:0]	jtag_uart_0_avalon_jtag_slave_writedata;
	output		jtag_uart_0_avalon_jtag_slave_waitrequest;
endmodule
