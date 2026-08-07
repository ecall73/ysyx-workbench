// See ../LICENSE.SiFive for license details.
//
// RV32IMAC/Zicsr/Zifencei decode distilled from rocket-chip's
// Instructions.scala and IDecode.scala at the locked source revision.
package npc.rocketmed

import chisel3._
import chisel3.util._

object AluOperation {
  val Add   = 0.U(4.W)
  val Sub   = 1.U(4.W)
  val Sll   = 2.U(4.W)
  val Slt   = 3.U(4.W)
  val Sltu  = 4.U(4.W)
  val Xor   = 5.U(4.W)
  val Srl   = 6.U(4.W)
  val Sra   = 7.U(4.W)
  val Or    = 8.U(4.W)
  val And   = 9.U(4.W)
  val Copy2 = 10.U(4.W)
}

object BranchOperation {
  val None = 0.U(3.W)
  val Eq   = 1.U(3.W)
  val Ne   = 2.U(3.W)
  val Lt   = 3.U(3.W)
  val Ge   = 4.U(3.W)
  val Ltu  = 5.U(3.W)
  val Geu  = 6.U(3.W)
}

object SystemOperation {
  val None   = 0.U(4.W)
  val Ecall  = 1.U(4.W)
  val Ebreak = 2.U(4.W)
  val Mret   = 3.U(4.W)
  val Sret   = 4.U(4.W)
  val Wfi    = 5.U(4.W)
  val Sfence = 6.U(4.W)
  val FenceI = 7.U(4.W)
  val Fence  = 8.U(4.W)
}

class DecodedInstruction extends Bundle {
  val illegal           = Bool()
  val rs1               = UInt(5.W)
  val rs2               = UInt(5.W)
  val rd                = UInt(5.W)
  val immediate         = UInt(32.W)
  val alu               = UInt(4.W)
  val operand1Pc        = Bool()
  val operand2Immediate = Bool()
  val writeRd           = Bool()
  val branch            = UInt(3.W)
  val jal               = Bool()
  val jalr              = Bool()
  val memory            = Bool()
  val memoryWrite       = Bool()
  val memorySize        = UInt(2.W)
  val memoryUnsigned    = Bool()
  val atomic            = UInt(4.W)
  val mulDiv            = Bool()
  val mulDivFunction    = UInt(3.W)
  val csr               = Bool()
  val csrCommand        = UInt(2.W)
  val csrImmediate      = Bool()
  val system            = UInt(4.W)
}

class InstructionDecoder extends Module {
  val io = IO(new Bundle {
    val instruction = Input(UInt(32.W))
    val decoded     = Output(new DecodedInstruction)
  })

  val inst    = io.instruction
  val opcode  = inst(6, 0)
  val funct3  = inst(14, 12)
  val funct7  = inst(31, 25)
  val decoded = WireDefault(0.U.asTypeOf(new DecodedInstruction))
  decoded.illegal    := true.B
  decoded.rs1        := inst(19, 15)
  decoded.rs2        := inst(24, 20)
  decoded.rd         := inst(11, 7)
  decoded.alu        := AluOperation.Add
  decoded.atomic     := AtomicOperation.None
  decoded.system     := SystemOperation.None
  decoded.csrCommand := CsrCommand.None

  val immI = Cat(Fill(20, inst(31)), inst(31, 20))
  val immS = Cat(Fill(20, inst(31)), inst(31, 25), inst(11, 7))
  val immB = Cat(Fill(19, inst(31)), inst(31), inst(7), inst(30, 25), inst(11, 8), 0.U(1.W))
  val immU = Cat(inst(31, 12), 0.U(12.W))
  val immJ = Cat(Fill(11, inst(31)), inst(31), inst(19, 12), inst(20), inst(30, 21), 0.U(1.W))

  switch(opcode) {
    is("b0110111".U) { // LUI
      decoded.illegal           := false.B
      decoded.immediate         := immU
      decoded.operand2Immediate := true.B
      decoded.alu               := AluOperation.Copy2
      decoded.writeRd           := true.B
    }
    is("b0010111".U) { // AUIPC
      decoded.illegal           := false.B
      decoded.immediate         := immU
      decoded.operand1Pc        := true.B
      decoded.operand2Immediate := true.B
      decoded.writeRd           := true.B
    }
    is("b1101111".U) { // JAL
      decoded.illegal   := false.B
      decoded.immediate := immJ
      decoded.writeRd   := true.B
      decoded.jal       := true.B
    }
    is("b1100111".U) { // JALR
      when(funct3 === 0.U) {
        decoded.illegal   := false.B
        decoded.immediate := immI
        decoded.writeRd   := true.B
        decoded.jalr      := true.B
      }
    }
    is("b1100011".U) { // conditional branches
      decoded.immediate := immB
      switch(funct3) {
        is(0.U) { decoded.illegal := false.B; decoded.branch := BranchOperation.Eq }
        is(1.U) { decoded.illegal := false.B; decoded.branch := BranchOperation.Ne }
        is(4.U) { decoded.illegal := false.B; decoded.branch := BranchOperation.Lt }
        is(5.U) { decoded.illegal := false.B; decoded.branch := BranchOperation.Ge }
        is(6.U) { decoded.illegal := false.B; decoded.branch := BranchOperation.Ltu }
        is(7.U) { decoded.illegal := false.B; decoded.branch := BranchOperation.Geu }
      }
    }
    is("b0000011".U) { // loads
      decoded.immediate := immI
      decoded.memory    := true.B
      decoded.writeRd   := true.B
      switch(funct3) {
        is(0.U) { decoded.illegal := false.B; decoded.memorySize := 0.U }
        is(1.U) { decoded.illegal := false.B; decoded.memorySize := 1.U }
        is(2.U) { decoded.illegal := false.B; decoded.memorySize := 2.U }
        is(4.U) { decoded.illegal := false.B; decoded.memorySize := 0.U; decoded.memoryUnsigned := true.B }
        is(5.U) { decoded.illegal := false.B; decoded.memorySize := 1.U; decoded.memoryUnsigned := true.B }
      }
    }
    is("b0100011".U) { // stores
      decoded.immediate   := immS
      decoded.memory      := true.B
      decoded.memoryWrite := true.B
      switch(funct3) {
        is(0.U) { decoded.illegal := false.B; decoded.memorySize := 0.U }
        is(1.U) { decoded.illegal := false.B; decoded.memorySize := 1.U }
        is(2.U) { decoded.illegal := false.B; decoded.memorySize := 2.U }
      }
    }
    is("b0010011".U) { // immediate ALU
      decoded.immediate         := immI
      decoded.operand2Immediate := true.B
      decoded.writeRd           := true.B
      switch(funct3) {
        is(0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Add }
        is(2.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Slt }
        is(3.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Sltu }
        is(4.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Xor }
        is(6.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Or }
        is(7.U) { decoded.illegal := false.B; decoded.alu := AluOperation.And }
        is(1.U) {
          when(funct7 === 0.U) {
            decoded.illegal := false.B
            decoded.alu     := AluOperation.Sll
          }
        }
        is(5.U) {
          when(funct7 === 0.U || funct7 === "b0100000".U) {
            decoded.illegal := false.B
            decoded.alu     := Mux(funct7(5), AluOperation.Sra, AluOperation.Srl)
          }
        }
      }
    }
    is("b0110011".U) { // register ALU and M extension
      decoded.writeRd := true.B
      when(funct7 === 1.U) {
        decoded.illegal        := false.B
        decoded.mulDiv         := true.B
        decoded.mulDivFunction := funct3
      }.otherwise {
        switch(funct3) {
          is(0.U) {
            when(funct7 === 0.U || funct7 === "b0100000".U) {
              decoded.illegal := false.B
              decoded.alu     := Mux(funct7(5), AluOperation.Sub, AluOperation.Add)
            }
          }
          is(1.U) { when(funct7 === 0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Sll } }
          is(2.U) { when(funct7 === 0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Slt } }
          is(3.U) { when(funct7 === 0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Sltu } }
          is(4.U) { when(funct7 === 0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Xor } }
          is(5.U) {
            when(funct7 === 0.U || funct7 === "b0100000".U) {
              decoded.illegal := false.B
              decoded.alu     := Mux(funct7(5), AluOperation.Sra, AluOperation.Srl)
            }
          }
          is(6.U) { when(funct7 === 0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.Or } }
          is(7.U) { when(funct7 === 0.U) { decoded.illegal := false.B; decoded.alu := AluOperation.And } }
        }
      }
    }
    is("b0001111".U) {
      when(funct3 === 0.U) {
        decoded.illegal := false.B
        decoded.system  := SystemOperation.Fence
      }.elsewhen(funct3 === 1.U) {
        decoded.illegal := false.B
        decoded.system  := SystemOperation.FenceI
      }
    }
    is("b1110011".U) {
      when(funct3 === 0.U) {
        when(inst === "h00000073".U) {
          decoded.illegal := false.B
          decoded.system  := SystemOperation.Ecall
        }.elsewhen(inst === "h00100073".U) {
          decoded.illegal := false.B
          decoded.system  := SystemOperation.Ebreak
        }.elsewhen(inst === "h30200073".U) {
          decoded.illegal := false.B
          decoded.system  := SystemOperation.Mret
        }.elsewhen(inst === "h10200073".U) {
          decoded.illegal := false.B
          decoded.system  := SystemOperation.Sret
        }.elsewhen(inst === "h10500073".U) {
          decoded.illegal := false.B
          decoded.system  := SystemOperation.Wfi
        }.elsewhen(funct7 === "b0001001".U && decoded.rd === 0.U) {
          decoded.illegal := false.B
          decoded.system  := SystemOperation.Sfence
        }
      }.otherwise {
        decoded.csr          := true.B
        decoded.writeRd      := true.B
        decoded.csrImmediate := funct3(2)
        switch(funct3(1, 0)) {
          is(1.U) {
            decoded.illegal    := false.B
            decoded.csrCommand := CsrCommand.Write
          }
          is(2.U) {
            decoded.illegal    := false.B
            decoded.csrCommand := Mux(decoded.rs1.orR, CsrCommand.Set, CsrCommand.None)
          }
          is(3.U) {
            decoded.illegal    := false.B
            decoded.csrCommand := Mux(decoded.rs1.orR, CsrCommand.Clear, CsrCommand.None)
          }
        }
      }
    }
    is("b0101111".U) { // RV32A word operations
      when(funct3 === 2.U) {
        decoded.memory      := true.B
        decoded.memorySize  := 2.U
        decoded.writeRd     := true.B
        decoded.memoryWrite := true.B
        switch(inst(31, 27)) {
          is("b00010".U) {
            when(decoded.rs2 === 0.U) {
              decoded.illegal     := false.B
              decoded.memoryWrite := false.B
              decoded.atomic      := AtomicOperation.Lr
            }
          }
          is("b00011".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Sc }
          is("b00001".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Swap }
          is("b00000".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Add }
          is("b00100".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Xor }
          is("b01100".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.And }
          is("b01000".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Or }
          is("b10000".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Min }
          is("b10100".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Max }
          is("b11000".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Minu }
          is("b11100".U) { decoded.illegal := false.B; decoded.atomic := AtomicOperation.Maxu }
        }
      }
    }
  }

  io.decoded := decoded
}
