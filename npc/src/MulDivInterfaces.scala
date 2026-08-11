// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
package npc.rocketmed

import chisel3._

object MulDivFn {
  val Mul    = 0.U(3.W)
  val Mulh   = 1.U(3.W)
  val Mulhsu = 2.U(3.W)
  val Mulhu  = 3.U(3.W)
  val Div    = 4.U(3.W)
  val Divu   = 5.U(3.W)
  val Rem    = 6.U(3.W)
  val Remu   = 7.U(3.W)
}

object Rv32MultiplySign {
  val UnsignedUnsigned = 0.U(2.W)
  val SignedUnsigned   = 2.U(2.W)
  val SignedSigned     = 3.U(2.W)
}

abstract class Rv32Multiplier extends Module {
  // Requests are accepted on valid && ready. out_valid is a one-cycle
  // completion pulse with no backpressure; results are valid during that
  // cycle. flush has priority over acceptance and completion, and leaves the
  // unit ready on the following cycle.
  val mul_valid    = IO(Input(Bool()))
  val flush        = IO(Input(Bool()))
  val mul_signed   = IO(Input(UInt(2.W)))
  val multiplicand = IO(Input(UInt(32.W)))
  val multiplier   = IO(Input(UInt(32.W)))
  val mul_ready    = IO(Output(Bool()))
  val out_valid    = IO(Output(Bool()))
  val result_hi    = IO(Output(UInt(32.W)))
  val result_lo    = IO(Output(UInt(32.W)))
}

abstract class Rv32Divider extends Module {
  // RV32 has no DIVW/DIVUW distinction: every request operates on 32-bit
  // inputs.
  val div_valid  = IO(Input(Bool()))
  val flush      = IO(Input(Bool()))
  val div_signed = IO(Input(Bool()))
  val dividend   = IO(Input(UInt(32.W)))
  val divisor    = IO(Input(UInt(32.W)))
  val div_ready  = IO(Output(Bool()))
  val out_valid  = IO(Output(Bool()))
  val quotient   = IO(Output(UInt(32.W)))
  val remainder  = IO(Output(UInt(32.W)))
}
