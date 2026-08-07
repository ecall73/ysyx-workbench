// The request/response structure follows Rocket's shared iterative MulDiv
// organization. The fixed Med parameters are mulUnroll=8 and divUnroll=1.
package npc.rocketmed

import chisel3._
import chisel3.util._

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

class MulDivRequest extends Bundle {
  val fn  = UInt(3.W)
  val lhs = UInt(32.W)
  val rhs = UInt(32.W)
}

class IterativeMulDiv extends Module {
  val io = IO(new Bundle {
    val request  = Flipped(Decoupled(new MulDivRequest))
    val response = Decoupled(UInt(32.W))
  })

  val idle :: multiply :: divide :: finish :: Nil = Enum(4)
  val state                                       = RegInit(idle)
  val fn                                          = Reg(UInt(3.W))
  val result                                      = Reg(UInt(32.W))

  val mulAccumulator  = Reg(UInt(64.W))
  val mulMultiplicand = Reg(UInt(64.W))
  val mulMultiplier   = Reg(UInt(32.W))
  val mulNegative     = Reg(Bool())
  val mulCount        = RegInit(0.U(2.W))

  val divDividend          = Reg(UInt(32.W))
  val divDivisor           = Reg(UInt(32.W))
  val divRemainder         = Reg(UInt(33.W))
  val divQuotient          = Reg(UInt(32.W))
  val divQuotientNegative  = Reg(Bool())
  val divRemainderNegative = Reg(Bool())
  val divByZero            = Reg(Bool())
  val divOverflow          = Reg(Bool())
  val divOriginalLhs       = Reg(UInt(32.W))
  val divCount             = RegInit(0.U(6.W))

  io.request.ready  := state === idle
  io.response.valid := state === finish
  io.response.bits  := result

  when(io.response.fire) {
    state := idle
  }

  when(io.request.fire) {
    fn := io.request.bits.fn
    when(io.request.bits.fn < MulDivFn.Div) {
      val lhsSigned    = io.request.bits.fn === MulDivFn.Mulh ||
        io.request.bits.fn === MulDivFn.Mulhsu
      val rhsSigned    = io.request.bits.fn === MulDivFn.Mulh
      val lhsNegative  = lhsSigned && io.request.bits.lhs(31)
      val rhsNegative  = rhsSigned && io.request.bits.rhs(31)
      val lhsMagnitude = Mux(lhsNegative, (~io.request.bits.lhs).asUInt + 1.U, io.request.bits.lhs)
      val rhsMagnitude = Mux(rhsNegative, (~io.request.bits.rhs).asUInt + 1.U, io.request.bits.rhs)
      mulAccumulator  := 0.U
      mulMultiplicand := lhsMagnitude
      mulMultiplier   := rhsMagnitude
      mulNegative     := lhsNegative ^ rhsNegative
      mulCount        := 0.U
      state           := multiply
    }.otherwise {
      val signed      = io.request.bits.fn === MulDivFn.Div ||
        io.request.bits.fn === MulDivFn.Rem
      val lhsNegative = signed && io.request.bits.lhs(31)
      val rhsNegative = signed && io.request.bits.rhs(31)
      divDividend          := Mux(lhsNegative, (~io.request.bits.lhs).asUInt + 1.U, io.request.bits.lhs)
      divDivisor           := Mux(rhsNegative, (~io.request.bits.rhs).asUInt + 1.U, io.request.bits.rhs)
      divRemainder         := 0.U
      divQuotient          := 0.U
      divQuotientNegative  := lhsNegative ^ rhsNegative
      divRemainderNegative := lhsNegative
      divByZero            := io.request.bits.rhs === 0.U
      divOverflow          := signed && io.request.bits.lhs === "h80000000".U &&
        io.request.bits.rhs === "hffffffff".U
      divOriginalLhs       := io.request.bits.lhs
      divCount             := 0.U
      state                := divide
    }
  }

  when(state === multiply) {
    val partial         = (mulMultiplicand * mulMultiplier(7, 0))(63, 0)
    val nextAccumulator = mulAccumulator + partial
    mulAccumulator  := nextAccumulator
    mulMultiplicand := (mulMultiplicand << RocketMed.MulUnroll)(63, 0)
    mulMultiplier   := mulMultiplier >> RocketMed.MulUnroll
    mulCount        := mulCount + 1.U
    when(mulCount === 3.U) {
      val signedProduct = Mux(mulNegative, (~nextAccumulator).asUInt + 1.U, nextAccumulator)
      result := Mux(fn === MulDivFn.Mul, signedProduct(31, 0), signedProduct(63, 32))
      state  := finish
    }
  }

  when(state === divide) {
    val shiftedRemainder = Cat(divRemainder(31, 0), divDividend(31))
    val subtract         = shiftedRemainder >= Cat(0.U(1.W), divDivisor)
    val nextRemainder    = Mux(subtract, shiftedRemainder - Cat(0.U(1.W), divDivisor), shiftedRemainder)
    val nextQuotient     = Cat(divQuotient(30, 0), subtract)
    divRemainder := nextRemainder
    divDividend  := Cat(divDividend(30, 0), 0.U(1.W))
    divQuotient  := nextQuotient
    divCount     := divCount + 1.U
    when(divCount === 31.U) {
      val quotient           = Mux(divQuotientNegative, (~nextQuotient).asUInt + 1.U, nextQuotient)
      val remainderMagnitude = nextRemainder(31, 0)
      val remainder          = Mux(divRemainderNegative, (~remainderMagnitude).asUInt + 1.U, remainderMagnitude)
      val wantRemainder      = fn === MulDivFn.Rem || fn === MulDivFn.Remu
      result := Mux(
        divByZero,
        Mux(wantRemainder, divOriginalLhs, "hffffffff".U),
        Mux(divOverflow, Mux(wantRemainder, 0.U, "h80000000".U), Mux(wantRemainder, remainder, quotient))
      )
      state  := finish
    }
  }
}
