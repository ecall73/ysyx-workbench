// See ../LICENSE.SiFive for license details.
//
// Minimal single-hart CLINT owned by the NPC core. Its data path is decoded
// before D$/MemSys, so no CLINT transaction reaches the external AXI master.
package npc.rocketmed

import chisel3._
import chisel3.util._

class ClintAccess extends Bundle {
  val valid = Bool()
  val addr  = UInt(32.W)
  val size  = UInt(2.W)
  val write = Bool()
  val data  = UInt(32.W)
  val mask  = UInt(4.W)
}

class Clint extends Module {
  val io = IO(new Bundle {
    val access        = Input(new ClintAccess)
    val hit           = Output(Bool())
    val legal         = Output(Bool())
    val readData      = Output(UInt(32.W))
    val stimecmpWrite = Input(Valid(new StimecmpWrite))
    val stce          = Input(Bool())
    val time          = Output(UInt(64.W))
    val stimecmp      = Output(UInt(64.W))
    val msip          = Output(Bool())
    val mtip          = Output(Bool())
    val stip          = Output(Bool())
  })

  private val Base       = "h02000000".U(32.W)
  private val End        = "h02010000".U(33.W)
  private val Msip       = "h02000000".U(32.W)
  private val MtimecmpLo = "h02004000".U(32.W)
  private val MtimecmpHi = "h02004004".U(32.W)
  private val MtimeLo    = "h0200bff8".U(32.W)
  private val MtimeHi    = "h0200bffc".U(32.W)

  val mtime    = RegInit(0.U(64.W))
  val mtimecmp = RegInit("hffffffffffffffff".U(64.W))
  val stimecmp = RegInit("hffffffffffffffff".U(64.W))
  val msip     = RegInit(false.B)

  val address    = io.access.addr
  val inWindow   = Cat(0.U(1.W), address) >= Cat(0.U(1.W), Base) &&
    Cat(0.U(1.W), address) < End
  val selected   = address === Msip || address === MtimecmpLo ||
    address === MtimecmpHi || address === MtimeLo || address === MtimeHi
  val wordAccess = io.access.size === 2.U && address(1, 0) === 0.U
  val fullMask   = io.access.mask === "hf".U

  io.hit      := inWindow
  io.legal    := selected && wordAccess && (!io.access.write || fullMask)
  io.readData := MuxLookup(address, 0.U)(
    Seq(
      Msip       -> msip,
      MtimecmpLo -> mtimecmp(31, 0),
      MtimecmpHi -> mtimecmp(63, 32),
      MtimeLo    -> mtime(31, 0),
      MtimeHi    -> mtime(63, 32)
    )
  )

  val write       = io.access.valid && io.hit && io.legal && io.access.write
  val writesMtime = write && (address === MtimeLo || address === MtimeHi)
  when(writesMtime) {
    mtime := Mux(address === MtimeHi, Cat(io.access.data, mtime(31, 0)), Cat(mtime(63, 32), io.access.data))
  }.otherwise {
    mtime := mtime + 1.U
  }

  when(write && address === Msip) { msip := io.access.data(0) }
  when(write && address === MtimecmpLo) {
    mtimecmp := Cat(mtimecmp(63, 32), io.access.data)
  }
  when(write && address === MtimecmpHi) {
    mtimecmp := Cat(io.access.data, mtimecmp(31, 0))
  }
  when(io.stimecmpWrite.valid) {
    stimecmp := Mux(
      io.stimecmpWrite.bits.upper,
      Cat(io.stimecmpWrite.bits.data, stimecmp(31, 0)),
      Cat(stimecmp(63, 32), io.stimecmpWrite.bits.data)
    )
  }

  io.time     := mtime
  io.stimecmp := stimecmp
  io.msip     := msip
  io.mtip     := mtime >= mtimecmp
  io.stip     := io.stce && mtime >= stimecmp
}
