// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
package npc.rocketmed

import chisel3._
import chisel3.util._

class IterativeDivider extends Rv32Divider {
  val idle :: divide :: output :: Nil = Enum(3)
  val state                           = RegInit(idle)
  val shiftedDividend                 = Reg(UInt(32.W))
  val savedDivisor                    = Reg(UInt(32.W))
  val partialRemainder                = Reg(UInt(33.W))
  val partialQuotient                 = Reg(UInt(32.W))
  val quotientNegative                = Reg(Bool())
  val remainderNegative               = Reg(Bool())
  val divideByZero                    = Reg(Bool())
  val overflow                        = Reg(Bool())
  val originalDividend                = Reg(UInt(32.W))
  val count                           = RegInit(0.U(6.W))

  div_ready := state === idle && !flush
  out_valid := state === output && !flush
  quotient  := partialQuotient
  remainder := partialRemainder(31, 0)

  when(flush) {
    state := idle
  }.otherwise {
    when(state === idle && div_valid) {
      val lhsNegative = div_signed && dividend(31)
      val rhsNegative = div_signed && divisor(31)

      shiftedDividend   := Mux(lhsNegative, (~dividend).asUInt + 1.U, dividend)
      savedDivisor      := Mux(rhsNegative, (~divisor).asUInt + 1.U, divisor)
      partialRemainder  := 0.U
      partialQuotient   := 0.U
      quotientNegative  := lhsNegative ^ rhsNegative
      remainderNegative := lhsNegative
      divideByZero      := divisor === 0.U
      overflow          := div_signed && dividend === "h80000000".U &&
        divisor === "hffffffff".U
      originalDividend  := dividend
      count             := 0.U
      state             := divide
    }

    when(state === divide) {
      val shiftedRemainder = Cat(partialRemainder(31, 0), shiftedDividend(31))
      val subtract         = shiftedRemainder >= Cat(0.U(1.W), savedDivisor)
      val nextRemainder    = Mux(
        subtract,
        shiftedRemainder - Cat(0.U(1.W), savedDivisor),
        shiftedRemainder
      )
      val nextQuotient     = Cat(partialQuotient(30, 0), subtract)

      partialRemainder := nextRemainder
      shiftedDividend  := Cat(shiftedDividend(30, 0), 0.U(1.W))
      partialQuotient  := nextQuotient
      count            := count + 1.U
      when(count === 31.U) {
        val signedQuotient     = Mux(
          quotientNegative,
          (~nextQuotient).asUInt + 1.U,
          nextQuotient
        )
        val remainderMagnitude = nextRemainder(31, 0)
        val signedRemainder    = Mux(
          remainderNegative,
          (~remainderMagnitude).asUInt + 1.U,
          remainderMagnitude
        )
        partialQuotient  := Mux(
          divideByZero,
          "hffffffff".U,
          Mux(overflow, "h80000000".U, signedQuotient)
        )
        partialRemainder := Cat(
          0.U(1.W),
          Mux(
            divideByZero,
            originalDividend,
            Mux(overflow, 0.U, signedRemainder)
          )
        )
        state            := output
      }
    }

    when(state === output) {
      state := idle
    }
  }
}
