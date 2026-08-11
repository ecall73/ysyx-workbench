// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
package npc.rocketmed

import chisel3._
import chisel3.util._

class IterativeMultiplier(bitsPerCycle: Int = 8) extends Rv32Multiplier {
  private val Cycles    = 32 / bitsPerCycle
  private val CountBits = math.max(1, log2Ceil(Cycles))

  require(bitsPerCycle > 0 && bitsPerCycle <= 32)
  require(32 % bitsPerCycle == 0)

  val idle :: multiply :: output :: Nil = Enum(3)
  val state                             = RegInit(idle)
  val accumulator                       = Reg(UInt(64.W))
  val shiftedMultiplicand               = Reg(UInt(64.W))
  val shiftedMultiplier                 = Reg(UInt(32.W))
  val negative                          = Reg(Bool())
  val count                             = RegInit(0.U(CountBits.W))

  mul_ready := state === idle && !flush
  out_valid := state === output && !flush
  result_hi := accumulator(63, 32)
  result_lo := accumulator(31, 0)

  when(flush) {
    state := idle
  }.otherwise {
    when(state === idle && mul_valid) {
      assert(mul_signed =/= 1.U, "RV32 multiplier signedness 01 is reserved")
      val lhsSigned    = mul_signed === Rv32MultiplySign.SignedUnsigned ||
        mul_signed === Rv32MultiplySign.SignedSigned
      val rhsSigned    = mul_signed === Rv32MultiplySign.SignedSigned
      val lhsNegative  = lhsSigned && multiplicand(31)
      val rhsNegative  = rhsSigned && multiplier(31)
      val lhsMagnitude = Mux(lhsNegative, (~multiplicand).asUInt + 1.U, multiplicand)
      val rhsMagnitude = Mux(rhsNegative, (~multiplier).asUInt + 1.U, multiplier)

      accumulator         := 0.U
      shiftedMultiplicand := lhsMagnitude
      shiftedMultiplier   := rhsMagnitude
      negative            := lhsNegative ^ rhsNegative
      count               := 0.U
      state               := multiply
    }

    when(state === multiply) {
      val partial         =
        (shiftedMultiplicand * shiftedMultiplier(bitsPerCycle - 1, 0))(63, 0)
      val nextAccumulator = accumulator + partial
      accumulator         := nextAccumulator
      shiftedMultiplicand := (shiftedMultiplicand << bitsPerCycle)(63, 0)
      shiftedMultiplier   := shiftedMultiplier >> bitsPerCycle
      count               := count + 1.U
      when(count === (Cycles - 1).U) {
        accumulator := Mux(negative, (~nextAccumulator).asUInt + 1.U, nextAccumulator)
        state       := output
      }
    }

    when(state === output) {
      state := idle
    }
  }
}
