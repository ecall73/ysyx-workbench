// See ../LICENSE.SiFive for license details.
//
// Modified from rocket-chip IBuf.scala at the locked source revision. This
// version fixes fetchWidth=2 and decodeWidth=1 and exposes a small standalone
// interface suitable for the NPC frontend.
package npc.rocketmed

import chisel3._
import chisel3.util._

class FetchPacket extends Bundle {
  // PC of the first requested halfword; data remains aligned to PC & ~3.
  val pc          = UInt(32.W)
  val data        = UInt(32.W)
  val pageFault   = Bool()
  val accessFault = Bool()
}

class BufferedInstruction extends Bundle {
  val pc           = UInt(32.W)
  val raw          = UInt(32.W)
  val expanded     = new RvcExpandedInstruction
  val rvc          = Bool()
  val illegal      = Bool()
  val pageFault0   = Bool()
  val pageFault1   = Bool()
  val accessFault0 = Bool()
  val accessFault1 = Bool()
}

class InstructionBuffer extends Module {
  val io = IO(new Bundle {
    val fetch       = Flipped(Decoupled(new FetchPacket))
    val kill        = Input(Bool())
    val instruction = Decoupled(new BufferedInstruction)
  })

  val count      = RegInit(0.U(2.W))
  val basePc     = Reg(UInt(32.W))
  val half0      = Reg(UInt(16.W))
  val half1      = Reg(UInt(16.W))
  val fault0     = Reg(Bool())
  val fault1     = Reg(Bool())
  val pageFault0 = Reg(Bool())
  val pageFault1 = Reg(Bool())

  val firstIsCompressed   = half0(1, 0) =/= 3.U
  val candidateRaw        = WireDefault(0.U(32.W))
  val candidateFault1     = WireDefault(false.B)
  val candidatePageFault1 = WireDefault(false.B)

  when(count === 2.U) {
    candidateRaw        := Cat(half1, half0)
    candidateFault1     := fault1
    candidatePageFault1 := pageFault1
  }.elsewhen(count === 1.U) {
    when(firstIsCompressed) {
      candidateRaw := Cat(0.U(16.W), half0)
    }.otherwise {
      candidateRaw        := Cat(io.fetch.bits.data(15, 0), half0)
      candidateFault1     := io.fetch.bits.accessFault
      candidatePageFault1 := io.fetch.bits.pageFault
    }
  }

  val expander = Module(new RvcExpander)
  expander.io.in := candidateRaw

  io.fetch.ready                   := false.B
  io.instruction.valid             := false.B
  io.instruction.bits.pc           := basePc
  io.instruction.bits.raw          := candidateRaw
  io.instruction.bits.expanded     := expander.io.out
  io.instruction.bits.rvc          := expander.io.rvc
  io.instruction.bits.illegal      := expander.io.illegal
  io.instruction.bits.pageFault0   := pageFault0
  io.instruction.bits.pageFault1   := Mux(expander.io.rvc, false.B, candidatePageFault1)
  io.instruction.bits.accessFault0 := fault0
  io.instruction.bits.accessFault1 := Mux(expander.io.rvc, false.B, candidateFault1)

  when(!io.kill) {
    when(count === 0.U) {
      io.fetch.ready := true.B
    }.elsewhen(count === 2.U || firstIsCompressed) {
      io.instruction.valid := true.B
      // Replace a packet in the same cycle that its final instruction drains
      // the buffer. A leading compressed instruction still leaves half1
      // resident, so that case intentionally keeps fetch backpressured.
      when(!firstIsCompressed || count === 1.U) {
        io.fetch.ready := io.instruction.ready
      }
    }.otherwise {
      // A 32-bit instruction began in the upper half of the previous word.
      // The next aligned packet supplies its second half and one new halfword.
      io.fetch.ready       := io.instruction.ready
      io.instruction.valid := io.fetch.valid
    }
  }

  def loadFetchPacket(): Unit = {
    assert(io.fetch.bits.pc(0) === 0.U)
    when(io.fetch.bits.pc(1)) {
      basePc     := io.fetch.bits.pc
      half0      := io.fetch.bits.data(31, 16)
      fault0     := io.fetch.bits.accessFault
      pageFault0 := io.fetch.bits.pageFault
      count      := 1.U
    }.otherwise {
      basePc     := io.fetch.bits.pc
      half0      := io.fetch.bits.data(15, 0)
      half1      := io.fetch.bits.data(31, 16)
      fault0     := io.fetch.bits.accessFault
      fault1     := io.fetch.bits.accessFault
      pageFault0 := io.fetch.bits.pageFault
      pageFault1 := io.fetch.bits.pageFault
      count      := 2.U
    }
  }

  when(io.kill) {
    count := 0.U
  }.otherwise {
    when(count === 0.U && io.fetch.fire) {
      loadFetchPacket()
    }.elsewhen(count === 2.U && io.instruction.fire) {
      when(firstIsCompressed) {
        basePc     := basePc + 2.U
        half0      := half1
        fault0     := fault1
        pageFault0 := pageFault1
        count      := 1.U
      }.elsewhen(io.fetch.fire) {
        loadFetchPacket()
      }.otherwise {
        count := 0.U
      }
    }.elsewhen(
      count === 1.U && firstIsCompressed &&
        io.instruction.fire
    ) {
      when(io.fetch.fire) {
        loadFetchPacket()
      }.otherwise {
        count := 0.U
      }
    }.elsewhen(
      count === 1.U && !firstIsCompressed &&
        io.instruction.fire
    ) {
      assert(io.fetch.fire)
      assert(io.fetch.bits.pc === basePc + 2.U)
      assert(io.fetch.bits.pc(1) === 0.U)
      basePc     := io.fetch.bits.pc + 2.U
      half0      := io.fetch.bits.data(31, 16)
      fault0     := io.fetch.bits.accessFault
      pageFault0 := io.fetch.bits.pageFault
      count      := 1.U
    }
  }
}
