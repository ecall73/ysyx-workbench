// See ../LICENSE.SiFive for license details.
//
// Modified from rocket-chip RVC.scala at the locked source revision. This
// version removes parameter plumbing and all non-RV32IMAC/FPU decode paths.
package npc.rocketmed

import chisel3._
import chisel3.util._

class RvcExpandedInstruction extends Bundle {
  val bits = UInt(32.W)
  val rd   = UInt(5.W)
  val rs1  = UInt(5.W)
  val rs2  = UInt(5.W)
  val rs3  = UInt(5.W)
}

private class Rv32cDecoder(x: UInt) {
  private def inst(
    bits: UInt,
    rd:   UInt = x(11, 7),
    rs1:  UInt = x(19, 15),
    rs2:  UInt = x(24, 20),
    rs3:  UInt = x(31, 27)
  ): RvcExpandedInstruction = {
    val result = Wire(new RvcExpandedInstruction)
    result.bits := bits
    result.rd   := rd
    result.rs1  := rs1
    result.rs2  := rs2
    result.rs3  := rs3
    result
  }

  private def rs1p        = Cat(1.U(2.W), x(9, 7))
  private def rs2p        = Cat(1.U(2.W), x(4, 2))
  private def rs2         = x(6, 2)
  private def rd          = x(11, 7)
  private def addi4spnImm = Cat(x(10, 7), x(12, 11), x(5), x(6), 0.U(2.W))
  private def lwImm       = Cat(x(5), x(12, 10), x(6), 0.U(2.W))
  private def lwspImm     = Cat(x(3, 2), x(12), x(6, 4), 0.U(2.W))
  private def swspImm     = Cat(x(8, 7), x(12, 9), 0.U(2.W))
  private def luiImm      = Cat(Fill(15, x(12)), x(6, 2), 0.U(12.W))
  private def addi16spImm = Cat(Fill(3, x(12)), x(4, 3), x(5), x(2), x(6), 0.U(4.W))
  private def addiImm     = Cat(Fill(7, x(12)), x(6, 2))
  private def jImm        = Cat(Fill(10, x(12)), x(8), x(10, 9), x(6), x(7), x(2), x(11), x(5, 3), 0.U(1.W))
  private def bImm        = Cat(Fill(5, x(12)), x(6, 5), x(2), x(11, 10), x(4, 3), 0.U(1.W))
  private def shamt       = Cat(x(12), x(6, 2))
  private def x0          = 0.U(5.W)
  private def ra          = 1.U(5.W)
  private def sp          = 2.U(5.W)

  private def unimplemented = inst(Cat(lwImm >> 5, rs2p, rs1p, 2.U(3.W), lwImm(4, 0), 0x3f.U(7.W)), rs2p, rs1p, rs2p)

  private def q0: Seq[RvcExpandedInstruction] = {
    val addi4spnOpcode = Mux(x(12, 5).orR, 0x13.U(7.W), 0x1f.U(7.W))
    val addi4spn       = inst(Cat(addi4spnImm, sp, 0.U(3.W), rs2p, addi4spnOpcode), rs2p, sp, rs2p)
    val lw             = inst(Cat(lwImm, rs1p, 2.U(3.W), rs2p, 0x03.U(7.W)), rs2p, rs1p, rs2p)
    val sw             = inst(Cat(lwImm >> 5, rs2p, rs1p, 2.U(3.W), lwImm(4, 0), 0x23.U(7.W)), rs2p, rs1p, rs2p)
    Seq(addi4spn, unimplemented, lw, unimplemented, unimplemented, unimplemented, sw, unimplemented)
  }

  private def q1: Seq[RvcExpandedInstruction] = {
    val addi     = inst(Cat(addiImm, rd, 0.U(3.W), rd, 0x13.U(7.W)), rd, rd, rs2p)
    val jal      = inst(Cat(jImm(20), jImm(10, 1), jImm(11), jImm(19, 12), ra, 0x6f.U(7.W)), ra, rd, rs2p)
    val li       = inst(Cat(addiImm, x0, 0.U(3.W), rd, 0x13.U(7.W)), rd, x0, rs2p)
    val addi16sp = {
      val opcode = Mux(addiImm.orR, 0x13.U(7.W), 0x1f.U(7.W))
      inst(Cat(addi16spImm, rd, 0.U(3.W), rd, opcode), rd, rd, rs2p)
    }
    val lui      = {
      val opcode  = Mux(addiImm.orR, 0x37.U(7.W), 0x3f.U(7.W))
      val regular = inst(Cat(luiImm(31, 12), rd, opcode), rd, rd, rs2p)
      Mux(rd === x0 || rd === sp, addi16sp, regular)
    }
    val arith    = {
      val srli     = Cat(shamt, rs1p, 5.U(3.W), rs1p, 0x13.U(7.W))
      val srai     = srli | (1 << 30).U
      val andi     = Cat(addiImm, rs1p, 7.U(3.W), rs1p, 0x13.U(7.W))
      val funct    = VecInit(Seq(0.U(3.W), 4.U(3.W), 6.U(3.W), 7.U(3.W), 0.U(3.W), 0.U(3.W), 2.U(3.W), 3.U(3.W)))(
        Cat(x(12), x(6, 5))
      )
      val subtract = Mux(x(6, 5) === 0.U, (1 << 30).U, 0.U)
      val opcode   = Mux(x(12), 0x3b.U(7.W), 0x33.U(7.W))
      val rtype    = Cat(rs2p, rs1p, funct, rs1p, opcode) | subtract
      val bits     = VecInit(Seq(srli, srai, andi, rtype))(x(11, 10))
      inst(bits, rs1p, rs1p, rs2p)
    }
    val j        = inst(Cat(jImm(20), jImm(10, 1), jImm(11), jImm(19, 12), x0, 0x6f.U(7.W)), x0, rs1p, rs2p)
    val beqz     = inst(Cat(bImm(12), bImm(10, 5), x0, rs1p, 0.U(3.W), bImm(4, 1), bImm(11), 0x63.U(7.W)), rs1p, rs1p, x0)
    val bnez     = inst(Cat(bImm(12), bImm(10, 5), x0, rs1p, 1.U(3.W), bImm(4, 1), bImm(11), 0x63.U(7.W)), x0, rs1p, x0)
    Seq(addi, jal, li, lui, arith, j, beqz, bnez)
  }

  private def q2: Seq[RvcExpandedInstruction] = {
    val loadOpcode = Mux(rd.orR, 0x03.U(7.W), 0x1f.U(7.W))
    val slli       = inst(Cat(shamt, rd, 1.U(3.W), rd, 0x13.U(7.W)), rd, rd, rs2)
    val lwsp       = inst(Cat(lwspImm, sp, 2.U(3.W), rd, loadOpcode), rd, sp, rs2)
    val jalr       = {
      val mv           = inst(Cat(rs2, x0, 0.U(3.W), rd, 0x33.U(7.W)), rd, x0, rs2)
      val add          = inst(Cat(rs2, rd, 0.U(3.W), rd, 0x33.U(7.W)), rd, rd, rs2)
      val jr           = Cat(rs2, rd, 0.U(3.W), x0, 0x67.U(7.W))
      val reserved     = Cat(jr >> 7, 0x1f.U(7.W))
      val jrOrReserved = inst(Mux(rd.orR, jr, reserved), x0, rd, rs2)
      val jrOrMv       = Mux(rs2.orR, mv, jrOrReserved)
      val jalrBits     = Cat(rs2, rd, 0.U(3.W), ra, 0x67.U(7.W))
      val ebreak       = Cat(jr >> 7, 0x73.U(7.W)) | (1 << 20).U
      val jalrOrEbreak = inst(Mux(rd.orR, jalrBits, ebreak), ra, rd, rs2)
      val jalrOrAdd    = Mux(rs2.orR, add, jalrOrEbreak)
      Mux(x(12), jalrOrAdd, jrOrMv)
    }
    val swsp       = inst(Cat(swspImm >> 5, rs2, sp, 2.U(3.W), swspImm(4, 0), 0x23.U(7.W)), rd, sp, rs2)
    Seq(slli, unimplemented, lwsp, unimplemented, jalr, unimplemented, swsp, unimplemented)
  }

  private def passthrough = inst(x)

  val decoded: RvcExpandedInstruction = {
    val table = VecInit(q0 ++ q1 ++ q2 ++ Seq.fill(8)(passthrough))
    table(Cat(x(1, 0), x(15, 13)))
  }

  val illegal: Bool = {
    val q0Illegal = Seq(!x(12, 5).orR, true.B, false.B, true.B, true.B, true.B, false.B, true.B)
    val q1Illegal = Seq(false.B, false.B, false.B, !(x(12) || x(6, 2).orR), x(12, 10).andR, false.B, false.B, false.B)
    val q2Illegal = Seq(false.B, true.B, rd === 0.U, true.B, !x(12, 2).orR, true.B, false.B, true.B)
    VecInit(q0Illegal ++ q1Illegal ++ q2Illegal ++ Seq.fill(8)(false.B))(Cat(x(1, 0), x(15, 13)))
  }
}

class RvcExpander extends Module {
  val io = IO(new Bundle {
    val in      = Input(UInt(32.W))
    val out     = Output(new RvcExpandedInstruction)
    val rvc     = Output(Bool())
    val illegal = Output(Bool())
  })

  io.rvc := io.in(1, 0) =/= 3.U
  private val decoder = new Rv32cDecoder(io.in)
  io.out     := decoder.decoded
  io.illegal := decoder.illegal
}
