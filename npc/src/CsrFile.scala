// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
//
// Modified from rocket-chip CSR.scala at the locked source revision. This
// version retains only the fixed RV32IMAC U/S/M, Sv32, counter, and local
// interrupt state used by the NPC core.
package npc.rocketmed

import chisel3._
import chisel3.util._

object Privilege {
  val U = 0.U(2.W)
  val S = 1.U(2.W)
  val M = 3.U(2.W)
}

object CsrCommand {
  val None  = 0.U(2.W)
  val Write = 1.U(2.W)
  val Set   = 2.U(2.W)
  val Clear = 3.U(2.W)
}

class CsrAccess extends Bundle {
  val valid     = Bool()
  val addr      = UInt(12.W)
  val command   = UInt(2.W)
  val writeData = UInt(32.W)
}

class TrapRequest extends Bundle {
  val valid = Bool()
  val cause = UInt(32.W)
  val epc   = UInt(32.W)
  val tval  = UInt(32.W)
}

class LocalInterrupts extends Bundle {
  val msip = Bool()
  val mtip = Bool()
  val stip = Bool()
  val seip = Bool()
}

class StimecmpWrite extends Bundle {
  val upper = Bool()
  val data  = UInt(32.W)
}

class CsrState extends Bundle {
  val priv          = UInt(2.W)
  val mstatus       = UInt(32.W)
  val mtvec         = UInt(32.W)
  val mepc          = UInt(32.W)
  val mcause        = UInt(32.W)
  val mtval         = UInt(32.W)
  val medeleg       = UInt(32.W)
  val mideleg       = UInt(32.W)
  val mie           = UInt(32.W)
  val stvec         = UInt(32.W)
  val sepc          = UInt(32.W)
  val scause        = UInt(32.W)
  val stval         = UInt(32.W)
  val sscratch      = UInt(32.W)
  val satp          = UInt(32.W)
  val mscratch      = UInt(32.W)
  val menvcfgh      = UInt(32.W)
  val mcounteren    = UInt(32.W)
  val scounteren    = UInt(32.W)
  val mcountinhibit = UInt(32.W)
  val mcycle        = UInt(64.W)
  val minstret      = UInt(64.W)
}

object CsrAddress {
  val Sstatus       = 0x100
  val Sie           = 0x104
  val Stvec         = 0x105
  val Scounteren    = 0x106
  val Sscratch      = 0x140
  val Sepc          = 0x141
  val Scause        = 0x142
  val Stval         = 0x143
  val Sip           = 0x144
  val Stimecmp      = 0x14d
  val Stimecmph     = 0x15d
  val Satp          = 0x180
  val Mstatus       = 0x300
  val Misa          = 0x301
  val Medeleg       = 0x302
  val Mideleg       = 0x303
  val Mie           = 0x304
  val Mtvec         = 0x305
  val Mcounteren    = 0x306
  val Menvcfg       = 0x30a
  val Mstatush      = 0x310
  val Menvcfgh      = 0x31a
  val Mcountinhibit = 0x320
  val Mscratch      = 0x340
  val Mepc          = 0x341
  val Mcause        = 0x342
  val Mtval         = 0x343
  val Mip           = 0x344
  val Mcycle        = 0xb00
  val Minstret      = 0xb02
  val Mcycleh       = 0xb80
  val Minstreth     = 0xb82
  val Cycle         = 0xc00
  val Time          = 0xc01
  val Instret       = 0xc02
  val Cycleh        = 0xc80
  val Timeh         = 0xc81
  val Instreth      = 0xc82
  val Mvendorid     = 0xf11
  val Marchid       = 0xf12
  val Mimpid        = 0xf13
  val Mhartid       = 0xf14
  val Mconfigptr    = 0xf15
}

class CsrFile extends Module {
  import CsrAddress._
  import Privilege._

  val io = IO(new Bundle {
    val access         = Input(new CsrAccess)
    val readData       = Output(UInt(32.W))
    val accessIllegal  = Output(Bool())
    val trap           = Input(new TrapRequest)
    val trapTarget     = Output(UInt(32.W))
    // 0: none, 1: mret, 2: sret
    val ret            = Input(UInt(2.W))
    val retTarget      = Output(UInt(32.W))
    val retIllegal     = Output(Bool())
    val retired        = Input(Bool())
    val time           = Input(UInt(64.W))
    val stimecmp       = Input(UInt(64.W))
    val stimecmpWrite  = Output(Valid(new StimecmpWrite))
    val interrupts     = Input(new LocalInterrupts)
    val interruptValid = Output(Bool())
    val interruptCause = Output(UInt(32.W))
    val state          = Output(new CsrState)
  })

  private val SstatusMask      = "h000c0122".U(32.W)
  private val MstatusWritable  = "h007e19aa".U(32.W)
  private val MieMask          = "h000002aa".U(32.W)
  private val MidelegMask      = "h00000222".U(32.W)
  private val MedelegMask      = "h0000b3ff".U(32.W)
  private val CounterenMask    = 7.U(32.W)
  private val CountInhibitMask = 5.U(32.W)
  private val MenvcfghMask     = "h80000000".U(32.W)
  private val MisaValue        = "h40001105".U(32.W)

  val priv          = RegInit(M)
  val mstatus       = RegInit("h00001800".U(32.W))
  val medeleg       = RegInit(0.U(32.W))
  val mideleg       = RegInit(0.U(32.W))
  val mie           = RegInit(0.U(32.W))
  val mtvec         = RegInit(0.U(32.W))
  val mcounteren    = RegInit(0.U(32.W))
  val menvcfgh      = RegInit(0.U(32.W))
  val mcountinhibit = RegInit(0.U(32.W))
  val mscratch      = RegInit(0.U(32.W))
  val mepc          = RegInit(0.U(32.W))
  val mcause        = RegInit(0.U(32.W))
  val mtval         = RegInit(0.U(32.W))
  val stvec         = RegInit(0.U(32.W))
  val scounteren    = RegInit(0.U(32.W))
  val sscratch      = RegInit(0.U(32.W))
  val sepc          = RegInit(0.U(32.W))
  val scause        = RegInit(0.U(32.W))
  val stval         = RegInit(0.U(32.W))
  val satp          = RegInit(0.U(32.W))
  val softwareSsip  = RegInit(false.B)
  val mcycle        = RegInit(0.U(64.W))
  val minstret      = RegInit(0.U(64.W))

  val mip = (softwareSsip.asUInt << 1) |
    (io.interrupts.msip.asUInt << 3) |
    (io.interrupts.stip.asUInt << 5) |
    (io.interrupts.mtip.asUInt << 7) |
    (io.interrupts.seip.asUInt << 9)

  val readData          = WireDefault(0.U(32.W))
  val exists            = WireDefault(false.B)
  switch(io.access.addr) {
    is(Sstatus.U) { exists := true.B; readData := mstatus & SstatusMask }
    is(Sie.U) { exists := true.B; readData := mie & mideleg }
    is(Stvec.U) { exists := true.B; readData := stvec }
    is(Scounteren.U) { exists := true.B; readData := scounteren }
    is(Sscratch.U) { exists := true.B; readData := sscratch }
    is(Sepc.U) { exists := true.B; readData := sepc }
    is(Scause.U) { exists := true.B; readData := scause }
    is(Stval.U) { exists := true.B; readData := stval }
    is(Sip.U) { exists := true.B; readData := mip & mideleg }
    is(Stimecmp.U) { exists := true.B; readData := io.stimecmp(31, 0) }
    is(Stimecmph.U) { exists := true.B; readData := io.stimecmp(63, 32) }
    is(Satp.U) { exists := true.B; readData := satp }
    is(Mstatus.U) { exists := true.B; readData := mstatus }
    is(Misa.U) { exists := true.B; readData := MisaValue }
    is(Medeleg.U) { exists := true.B; readData := medeleg }
    is(Mideleg.U) { exists := true.B; readData := mideleg }
    is(Mie.U) { exists := true.B; readData := mie }
    is(Mtvec.U) { exists := true.B; readData := mtvec }
    is(Mcounteren.U) { exists := true.B; readData := mcounteren }
    is(Menvcfg.U) { exists := true.B; readData := 0.U }
    is(Mstatush.U) { exists := true.B; readData := 0.U }
    is(Menvcfgh.U) { exists := true.B; readData := menvcfgh }
    is(Mcountinhibit.U) { exists := true.B; readData := mcountinhibit }
    is(Mscratch.U) { exists := true.B; readData := mscratch }
    is(Mepc.U) { exists := true.B; readData := mepc }
    is(Mcause.U) { exists := true.B; readData := mcause }
    is(Mtval.U) { exists := true.B; readData := mtval }
    is(Mip.U) { exists := true.B; readData := mip }
    is(Mcycle.U) { exists := true.B; readData := mcycle(31, 0) }
    is(Minstret.U) { exists := true.B; readData := minstret(31, 0) }
    is(Mcycleh.U) { exists := true.B; readData := mcycle(63, 32) }
    is(Minstreth.U) { exists := true.B; readData := minstret(63, 32) }
    is(Cycle.U) { exists := true.B; readData := mcycle(31, 0) }
    is(Time.U) { exists := true.B; readData := io.time(31, 0) }
    is(Instret.U) { exists := true.B; readData := minstret(31, 0) }
    is(Cycleh.U) { exists := true.B; readData := mcycle(63, 32) }
    is(Timeh.U) { exists := true.B; readData := io.time(63, 32) }
    is(Instreth.U) { exists := true.B; readData := minstret(63, 32) }
    is(Mvendorid.U) { exists := true.B; readData := "h79737978".U(32.W) }
    is(Marchid.U) { exists := true.B; readData := 26030082.U }
    is(Mimpid.U) { exists := true.B; readData := 0.U }
    is(Mhartid.U) { exists := true.B; readData := 0.U }
    is(Mconfigptr.U) { exists := true.B; readData := 0.U }
  }
  val writing           = io.access.command =/= CsrCommand.None
  val requiredPrivilege = io.access.addr(9, 8)
  val privilegeIllegal  = priv < requiredPrivilege
  val readOnlyIllegal   = writing && io.access.addr(11, 10) === 3.U
  val satpIllegal       = io.access.addr === Satp.U && priv === S && mstatus(20)
  val counterIndex      = WireDefault(31.U(5.W))
  when(io.access.addr === Cycle.U || io.access.addr === Cycleh.U) {
    counterIndex := 0.U
  }.elsewhen(io.access.addr === Time.U || io.access.addr === Timeh.U) {
    counterIndex := 1.U
  }.elsewhen(io.access.addr === Instret.U || io.access.addr === Instreth.U) {
    counterIndex := 2.U
  }
  val isUserCounter     = counterIndex < 3.U
  val counterIllegal    = isUserCounter && !(priv === M ||
    (priv === S && mcounteren(counterIndex)) ||
    (priv === U && mcounteren(counterIndex) && scounteren(counterIndex)))
  val isStimecmp        = io.access.addr === Stimecmp.U ||
    io.access.addr === Stimecmph.U
  val stimecmpIllegal   = isStimecmp && priv =/= M &&
    (!menvcfgh(31) || !mcounteren(1))
  io.accessIllegal := io.access.valid && (!exists || privilegeIllegal ||
    readOnlyIllegal || satpIllegal || counterIllegal || stimecmpIllegal)
  io.readData      := readData

  val csrWriteData = MuxLookup(io.access.command, io.access.writeData)(
    Seq(
      CsrCommand.Write -> io.access.writeData,
      CsrCommand.Set   -> (readData | io.access.writeData),
      CsrCommand.Clear -> (readData & ~io.access.writeData)
    )
  )
  val csrWrite     = io.access.valid && writing && !io.accessIllegal

  io.stimecmpWrite.valid      := csrWrite && isStimecmp
  io.stimecmpWrite.bits.upper := io.access.addr === Stimecmph.U
  io.stimecmpWrite.bits.data  := csrWriteData

  def selectedBit(value: UInt, index: UInt): Bool =
    Mux(index < 32.U, (value >> index)(0), false.B)

  def trapVector(tvec: UInt, cause: UInt): UInt = {
    val base = tvec & "hfffffffc".U(32.W)
    Mux(cause(31) && tvec(1, 0) === 1.U, base + (cause(30, 0) << 2), base)
  }

  val trapCode       = io.trap.cause(4, 0)
  val trapDelegation = Mux(io.trap.cause(31), mideleg, medeleg)
  val trapDelegated  = priv =/= M && selectedBit(trapDelegation, trapCode)
  io.trapTarget := trapVector(Mux(trapDelegated, stvec, mtvec), io.trap.cause)

  val mret        = io.ret === 1.U
  val sret        = io.ret === 2.U
  val mretIllegal = mret && priv =/= M
  val sretIllegal = sret && (priv < S || (priv === S && mstatus(22)))
  io.retIllegal := (mretIllegal || sretIllegal) && io.ret =/= 0.U
  io.retTarget  := Mux(sret, sepc, mepc)

  val enabledPending    = mip & mie
  val interruptCodes    = Seq(3, 7, 9, 1, 5)
  val interruptEligible = interruptCodes.map { code =>
    val delegated       = mideleg(code)
    val globallyEnabled = Mux(delegated, priv < S || (priv === S && mstatus(1)), priv < M || (priv === M && mstatus(3)))
    enabledPending(code) && globallyEnabled
  }
  io.interruptValid := interruptEligible.reduce(_ || _)
  val selectedInterrupt = PriorityMux(interruptEligible.zip(interruptCodes.map(_.U(5.W))))
  io.interruptCause := "h80000000".U(32.W) | selectedInterrupt

  when(!mcountinhibit(0)) {
    mcycle := mcycle + 1.U
  }
  when(io.retired && !mcountinhibit(2)) {
    minstret := minstret + 1.U
  }

  when(io.trap.valid) {
    when(trapDelegated) {
      mstatus := (mstatus & ~"h00000122".U(32.W)) |
        (mstatus(1) << 5) | (priv(0) << 8)
      sepc    := io.trap.epc & "hfffffffe".U(32.W)
      scause  := io.trap.cause
      stval   := io.trap.tval
      priv    := S
    }.otherwise {
      mstatus := (mstatus & ~"h00001888".U(32.W)) |
        (mstatus(3) << 7) | (priv << 11)
      mepc    := io.trap.epc & "hfffffffe".U(32.W)
      mcause  := io.trap.cause
      mtval   := io.trap.tval
      priv    := M
    }
  }.elsewhen(io.ret =/= 0.U && !io.retIllegal) {
    when(mret) {
      val nextPrivilege = mstatus(12, 11)
      val restored      = (mstatus & ~"h00021888".U(32.W)) |
        (mstatus(7) << 3) | "h00000080".U(32.W)
      // MPRV is cleared only when xRET lowers privilege.
      mstatus := restored | Mux(nextPrivilege === M, mstatus & "h00020000".U(32.W), 0.U)
      priv    := nextPrivilege
    }.otherwise {
      mstatus := (mstatus & ~"h00020122".U(32.W)) |
        (mstatus(5) << 1) | "h00000020".U(32.W)
      priv    := Mux(mstatus(8), S, U)
    }
  }.elsewhen(csrWrite) {
    switch(io.access.addr) {
      is(Sstatus.U) {
        mstatus := (mstatus & ~SstatusMask) | (csrWriteData & SstatusMask)
      }
      is(Sie.U) { mie := (mie & ~mideleg) | (csrWriteData & mideleg & MieMask) }
      is(Stvec.U) { stvec := csrWriteData & "hfffffffd".U(32.W) }
      is(Scounteren.U) { scounteren := csrWriteData & CounterenMask }
      is(Sscratch.U) { sscratch := csrWriteData }
      is(Sepc.U) { sepc := csrWriteData & "hfffffffe".U(32.W) }
      is(Scause.U) { scause := csrWriteData }
      is(Stval.U) { stval := csrWriteData }
      is(Sip.U) {
        when(mideleg(1)) { softwareSsip := csrWriteData(1) }
      }
      is(Satp.U) { satp := csrWriteData }
      is(Mstatus.U) {
        val candidate    = csrWriteData & MstatusWritable
        val candidateMpp = candidate(12, 11)
        val legalMpp     = candidateMpp === U || candidateMpp === S ||
          candidateMpp === M
        mstatus := (candidate & ~"h00001800".U(32.W)) |
          (Mux(legalMpp, candidateMpp, U) << 11)
      }
      is(Medeleg.U) { medeleg := csrWriteData & MedelegMask }
      is(Mideleg.U) { mideleg := csrWriteData & MidelegMask }
      is(Mie.U) { mie := csrWriteData & MieMask }
      is(Mtvec.U) { mtvec := csrWriteData & "hfffffffd".U(32.W) }
      is(Mcounteren.U) { mcounteren := csrWriteData & CounterenMask }
      is(Menvcfgh.U) { menvcfgh := csrWriteData & MenvcfghMask }
      is(Mcountinhibit.U) { mcountinhibit := csrWriteData & CountInhibitMask }
      is(Mscratch.U) { mscratch := csrWriteData }
      is(Mepc.U) { mepc := csrWriteData & "hfffffffe".U(32.W) }
      is(Mcause.U) { mcause := csrWriteData }
      is(Mtval.U) { mtval := csrWriteData }
      is(Mip.U) { softwareSsip := csrWriteData(1) }
      is(Mcycle.U) { mcycle := Cat(mcycle(63, 32), csrWriteData) }
      is(Mcycleh.U) { mcycle := Cat(csrWriteData, mcycle(31, 0)) }
      is(Minstret.U) { minstret := Cat(minstret(63, 32), csrWriteData) }
      is(Minstreth.U) { minstret := Cat(csrWriteData, minstret(31, 0)) }
    }
  }

  io.state.priv          := priv
  io.state.mstatus       := mstatus
  io.state.mtvec         := mtvec
  io.state.mepc          := mepc
  io.state.mcause        := mcause
  io.state.mtval         := mtval
  io.state.medeleg       := medeleg
  io.state.mideleg       := mideleg
  io.state.mie           := mie
  io.state.stvec         := stvec
  io.state.sepc          := sepc
  io.state.scause        := scause
  io.state.stval         := stval
  io.state.sscratch      := sscratch
  io.state.satp          := satp
  io.state.mscratch      := mscratch
  io.state.menvcfgh      := menvcfgh
  io.state.mcounteren    := mcounteren
  io.state.scounteren    := scounteren
  io.state.mcountinhibit := mcountinhibit
  io.state.mcycle        := mcycle
  io.state.minstret      := minstret
}
