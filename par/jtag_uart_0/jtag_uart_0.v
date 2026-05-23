// jtag_uart_0.v — Standalone JTAG UART wrapper
//
// Direct instantiation of the JTAG UART megafunction without Platform Designer.
// Place this file in par/jtag_uart_0/ directory.
//
// Usage after synthesis:
//   nios2-terminal.exe (from Intel SoC EDS)
//   or: Quartus System Console → jtag_uart
module jtag_uart_0 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        av_chipselect,
    input  wire        av_address,      // 0=data, 1=control
    input  wire        av_read_n,
    output wire [31:0] av_readdata,
    input  wire        av_write_n,
    input  wire [31:0] av_writedata,
    output wire        av_waitrequest,
    output wire        av_irq
);

    // JTAG UART megafunction — Quartus synthesizes this directly
    jtag_uart #(
        .allowmultipleconnections("false"),
        .hubinstanceid(0),
        .read_buffer_depth(64),
        .read_irq_threshold(8),
        .siminteractiveoptions("NO_INTERACTIVE_WINDOWS"),
        .useregsforreadbuffer("false"),
        .useregsforwritebuffer("false"),
        .userelativepathforsimfile("false"),
        .write_buffer_depth(64),
        .write_irq_threshold(8),
        .clkfreq(50000000)
    ) u_jtag_uart (
        .clk            (clk),
        .rst_n          (rst_n),
        .av_chipselect  (av_chipselect),
        .av_address     (av_address),
        .av_read_n      (av_read_n),
        .av_readdata    (av_readdata),
        .av_write_n     (av_write_n),
        .av_writedata   (av_writedata),
        .av_waitrequest (av_waitrequest),
        .av_irq         (av_irq)
    );

endmodule
