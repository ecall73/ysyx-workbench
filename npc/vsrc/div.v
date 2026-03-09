`timescale 1ns / 1ps

module div(
    input clk,
    input rst,
    input in_valid,
    input is_unsigned, // 1: Unsigned Mode, 0: Signed Mode
    input [31:0] dividend,
    input [31:0] divisor,
    output out_valid,
    output [31:0] quotient,
    output [31:0] remainder
    );

    // =================================================================================================
    // Architecture Overview
    // =================================================================================================
    // 1. Algorithm: Radix-4 Restoring Division (Implemented as 2x Unrolled Radix-2 Steps per Stage)
    // 2. Pipeline Depth: 18 Cycles Total
    //      - Stage 0: Input Pre-processing (Absolute Value Calculation)
    //      - Stage 1-16: Core Division Logic (Resolves 2 bits per stage)
    //      - Stage 17: Output Post-processing (Sign Restoration & Divide-by-Zero Handling)
    // 3. Goal: High Fmax (300MHz+ on UltraScale+), No DSP usage, Low Resource.

    // Valid Logic with Reset
    reg [17:0] valid_d;
    always @(posedge clk) begin
        if (rst) valid_d <= 18'b0;
        else     valid_d <= {valid_d[16:0], in_valid};
    end
    assign out_valid = valid_d[17];
    
    // =================================================================================================
    // Stage 0: Input Pre-processing
    // =================================================================================================
    // Converts signed inputs to absolute values for the core unsigned divider.
    // Captures original signs and control flags for post-processing.
    
    reg [31:0] div_reg_0;           // Abs(Divisor)
    reg [31:0] dividend_reg_0;      // Abs(Dividend)
    reg is_unsigned_reg_0;          // Pipeline: Mode
    reg dividend_sign_reg_0;        // Pipeline: Original Dividend Sign
    reg divisor_sign_reg_0;         // Pipeline: Original Divisor Sign
    reg div_zero_reg_0;             // Pipeline: Divide by Zero Flag

    always @(posedge clk) begin
        // Capture Sign Bits and Control Flags
        dividend_sign_reg_0 <= dividend[31];
        divisor_sign_reg_0 <= divisor[31];
        is_unsigned_reg_0 <= is_unsigned;
        div_zero_reg_0 <= (divisor == 0);

        // Calculate Absolute Value for Dividend
        // If Signed Mode AND Negative -> 2's Complement Negation
        if (!is_unsigned && dividend[31]) 
            dividend_reg_0 <= (~dividend + 1);
        else 
            dividend_reg_0 <= dividend;

        // Calculate Absolute Value for Divisor
        if (!is_unsigned && divisor[31]) 
            div_reg_0 <= (~divisor + 1);
        else 
            div_reg_0 <= divisor;
    end

    // =================================================================================================
    // Stages 1-16: Core Division Pipeline
    // =================================================================================================
    // Each stage implements 2 iterations of the Radix-2 Restoring Division algorithm.
    // Total bits resolved: 16 stages * 2 bits/stage = 32 bits.
    
    // 'work_reg' stores the partial remainder (high 32 bits) and the shifting dividend/quotient (low 32 bits).
    // Initial State (Input to Core): {32'b0, Abs(Dividend)}
    // Final State (Output of Core):  {Remainder_Unsigned, Quotient_Unsigned}
    
    reg [63:0] work_reg [1:16];         // Main Data Pipeline
    reg [31:0] div_pipeline [1:16];     // Divisor Pipeline (propagates down)
    
    // Core Logic Interconnects
    wire [63:0] work_in_core = {32'b0, dividend_reg_0};
    wire [31:0] div_in_core = div_reg_0;

    // -------------------------------------------------------------------------------------------------
    // Function: step_radix2
    // Performs a single Radix-2 Restoring Division Step (1-bit resolution)
    // -------------------------------------------------------------------------------------------------
    function [63:0] step_radix2;
        input [63:0] curr_work;
        input [31:0] curr_div;
        reg [63:0] shifted_work;
        reg [32:0] diff; // 33 bits to capture the borrow/sign bit
        begin
            // 1. Shift Left by 1
            shifted_work = {curr_work[62:0], 1'b0};
            
            // 2. Trial Subtraction: Partial Remainder - Divisor
            // Note: Partial Remainder is in the upper 32 bits [63:32]
            diff = {1'b0, shifted_work[63:32]} - {1'b0, curr_div};
            
            // 3. Check Result (Restore or Update)
            if (!diff[32]) begin 
                // Result is Positive (No Borrow) -> Subtraction successful
                // Update Remainder to 'diff', Shift in '1' to Quotient (LSB)
                step_radix2 = {diff[31:0], shifted_work[31:1], 1'b1};
            end else begin
                // Result is Negative (Borrow) -> Subtraction failed
                // Restore Remainder (Keep 'shifted_work' as is), Shift in '0' to Quotient
                step_radix2 = shifted_work;
            end
        end
    endfunction

    integer i;
    
    // Pipeline Stage 1 (Logic driven by Stage 0 registers)
    always @(posedge clk) begin
        // Execute 2 consecutive Radix-2 steps (Equivalent to 1 Radix-4 step)
        work_reg[1] <= step_radix2(step_radix2(work_in_core, div_in_core), div_in_core);
        div_pipeline[1] <= div_in_core;
    end
    
    // -------------------------------------------------------------------------------------------------
    // Sideband Signal Pipelining (Control Path)
    // -------------------------------------------------------------------------------------------------
    // Propagate control signals from Stage 1 to Stage 16 to align with data.
    
    reg [16:1] p_div_zero;
    reg [16:1] p_is_unsigned;
    reg [16:1] p_dividend_sign;
    reg [16:1] p_divisor_sign;

    always @(posedge clk) begin
        // Inject Stage 0 control signals into the pipeline start (Stage 1)
        p_div_zero[1] <= div_zero_reg_0;
        p_is_unsigned[1] <= is_unsigned_reg_0;
        p_dividend_sign[1] <= dividend_sign_reg_0;
        p_divisor_sign[1] <= divisor_sign_reg_0;

        // Propagate through Stages 2 to 16
        for (i = 1; i < 16; i = i + 1) begin
            // Data Path: 2x Radix-2 Steps
            work_reg[i+1] <= step_radix2(step_radix2(work_reg[i], div_pipeline[i]), div_pipeline[i]);
            div_pipeline[i+1] <= div_pipeline[i];
            
            // Control Path: Shift Register
            p_div_zero[i+1] <= p_div_zero[i];
            p_is_unsigned[i+1] <= p_is_unsigned[i];
            p_dividend_sign[i+1] <= p_dividend_sign[i];
            p_divisor_sign[i+1] <= p_divisor_sign[i];
        end
    end

    // =================================================================================================
    // Stage 17: Output Post-processing
    // =================================================================================================
    // Restores signs for Quotient and Remainder based on original inputs.
    // Handles Divide-by-Zero exception.
    
    reg [31:0] quotient_out;
    reg [31:0] remainder_out;
    
    // Extract signals from the end of the pipeline (Stage 16)
    wire [31:0] raw_quotient = work_reg[16][31:0];      // Unsigned Quotient
    wire [31:0] raw_remainder = work_reg[16][63:32];    // Unsigned Remainder
    wire final_div_zero      = p_div_zero[16];
    wire final_is_unsigned   = p_is_unsigned[16];
    wire final_dividend_sign = p_dividend_sign[16];
    wire final_divisor_sign  = p_divisor_sign[16];

    always @(posedge clk) begin
        if (final_div_zero) begin
            // ---------------------------------------------------------
            // Exception Handling: Divide by Zero
            // ---------------------------------------------------------
            // Quotient is forced to all 1s (-1 for signed, MaxUInt for unsigned)
            quotient_out <= 32'hFFFFFFFF;
            
            // Remainder should equal the Dividend.
            // 'raw_remainder' currently holds Abs(Dividend) because no subtractions occurred.
            // Restore sign if original Dividend was negative.
            if (!final_is_unsigned && final_dividend_sign)
                remainder_out <= (~raw_remainder + 1);
            else
                remainder_out <= raw_remainder;

        end else begin
            // ---------------------------------------------------------
            // Normal Operation: Sign Restoration
            // ---------------------------------------------------------
            
            // 1. Quotient Sign Correction
            // Rule: Quotient is negative if Dividend and Divisor signs differ.
            if (!final_is_unsigned && (final_dividend_sign ^ final_divisor_sign))
                quotient_out <= (~raw_quotient + 1);
            else
                quotient_out <= raw_quotient;
                
            // 2. Remainder Sign Correction
            // Rule: Remainder sign always follows the Dividend sign.
            if (!final_is_unsigned && final_dividend_sign)
                remainder_out <= (~raw_remainder + 1);
            else
                remainder_out <= raw_remainder;
        end
    end

    // Drive Final Outputs
    assign quotient = quotient_out;
    assign remainder = remainder_out;

endmodule
