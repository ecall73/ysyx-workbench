// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
package npc.rocketmed

import chisel3._
import chisel3.util.Valid

// Chisel-owned semantic top. GenerateTop adds only the parameterized external
// contract and simulation DPI observer around this module.
class RocketChip(
  multiplierGenerator: () => Rv32Multiplier = () => new IterativeMultiplier,
  dividerGenerator:    () => Rv32Divider = () => new IterativeDivider)
    extends Module {
  override def desiredName: String = "ysyx_26030082_chisel"

  val io = IO(new Bundle {
    val resetVector = Input(UInt(32.W))
    val interrupt   = Input(Bool())

    val master_awready = Input(Bool())
    val master_awvalid = Output(Bool())
    val master_awid    = Output(UInt(4.W))
    val master_awaddr  = Output(UInt(32.W))
    val master_awlen   = Output(UInt(8.W))
    val master_awsize  = Output(UInt(3.W))
    val master_awburst = Output(UInt(2.W))
    val master_wready  = Input(Bool())
    val master_wvalid  = Output(Bool())
    val master_wdata   = Output(UInt(32.W))
    val master_wstrb   = Output(UInt(4.W))
    val master_wlast   = Output(Bool())
    val master_bready  = Output(Bool())
    val master_bvalid  = Input(Bool())
    val master_bid     = Input(UInt(4.W))
    val master_bresp   = Input(UInt(2.W))
    val master_arready = Input(Bool())
    val master_arvalid = Output(Bool())
    val master_arid    = Output(UInt(4.W))
    val master_araddr  = Output(UInt(32.W))
    val master_arlen   = Output(UInt(8.W))
    val master_arsize  = Output(UInt(3.W))
    val master_arburst = Output(UInt(2.W))
    val master_rready  = Output(Bool())
    val master_rvalid  = Input(Bool())
    val master_rid     = Input(UInt(4.W))
    val master_rdata   = Input(UInt(32.W))
    val master_rresp   = Input(UInt(2.W))
    val master_rlast   = Input(Bool())

    val slave_awready = Output(Bool())
    val slave_awvalid = Input(Bool())
    val slave_awid    = Input(UInt(4.W))
    val slave_awaddr  = Input(UInt(32.W))
    val slave_awlen   = Input(UInt(8.W))
    val slave_awsize  = Input(UInt(3.W))
    val slave_awburst = Input(UInt(2.W))
    val slave_wready  = Output(Bool())
    val slave_wvalid  = Input(Bool())
    val slave_wdata   = Input(UInt(32.W))
    val slave_wstrb   = Input(UInt(4.W))
    val slave_wlast   = Input(Bool())
    val slave_bready  = Input(Bool())
    val slave_bvalid  = Output(Bool())
    val slave_bid     = Output(UInt(4.W))
    val slave_bresp   = Output(UInt(2.W))
    val slave_arready = Output(Bool())
    val slave_arvalid = Input(Bool())
    val slave_arid    = Input(UInt(4.W))
    val slave_araddr  = Input(UInt(32.W))
    val slave_arlen   = Input(UInt(8.W))
    val slave_arsize  = Input(UInt(3.W))
    val slave_arburst = Input(UInt(2.W))
    val slave_rready  = Input(Bool())
    val slave_rvalid  = Output(Bool())
    val slave_rid     = Output(UInt(4.W))
    val slave_rdata   = Output(UInt(32.W))
    val slave_rresp   = Output(UInt(2.W))
    val slave_rlast   = Output(Bool())

    val commit         = Output(new CoreCommit)
    val asyncInterrupt = Output(Valid(new CoreInterruptEvent))
    val halted         = Output(Bool())
  })

  val core   = Module(new RocketCore(multiplierGenerator, dividerGenerator))
  val memSys = Module(new MemSys)

  core.io.resetVector := io.resetVector
  core.io.interrupts  := 0.U.asTypeOf(new LocalInterrupts)

  memSys.io.instructionReadAddress <> core.io.instructionReadAddress
  core.io.instructionReadData <> memSys.io.instructionReadData
  memSys.io.dataReadAddress <> core.io.dataReadAddress
  core.io.dataReadData <> memSys.io.dataReadData
  memSys.io.dataWriteAddress <> core.io.dataWriteAddress
  memSys.io.dataWriteData <> core.io.dataWriteData
  core.io.dataWriteResponse <> memSys.io.dataWriteResponse
  core.io.dataProbeRequest <> memSys.io.dataProbeRequest
  memSys.io.dataProbeResponse <> core.io.dataProbeResponse
  core.io.dataProbeAck <> memSys.io.dataProbeAck

  memSys.io.probeRequest.valid := false.B
  memSys.io.probeRequest.bits  := 0.U.asTypeOf(new ProbeRequest)
  memSys.io.probeAck.ready     := true.B

  memSys.io.axi.aw.ready    := io.master_awready
  io.master_awvalid         := memSys.io.axi.aw.valid
  io.master_awid            := memSys.io.axi.aw.bits.id
  io.master_awaddr          := memSys.io.axi.aw.bits.addr
  io.master_awlen           := memSys.io.axi.aw.bits.len
  io.master_awsize          := memSys.io.axi.aw.bits.size
  io.master_awburst         := memSys.io.axi.aw.bits.burst
  memSys.io.axi.w.ready     := io.master_wready
  io.master_wvalid          := memSys.io.axi.w.valid
  io.master_wdata           := memSys.io.axi.w.bits.data
  io.master_wstrb           := memSys.io.axi.w.bits.strb
  io.master_wlast           := memSys.io.axi.w.bits.last
  io.master_bready          := memSys.io.axi.b.ready
  memSys.io.axi.b.valid     := io.master_bvalid
  memSys.io.axi.b.bits.id   := io.master_bid
  memSys.io.axi.b.bits.resp := io.master_bresp
  memSys.io.axi.ar.ready    := io.master_arready
  io.master_arvalid         := memSys.io.axi.ar.valid
  io.master_arid            := memSys.io.axi.ar.bits.id
  io.master_araddr          := memSys.io.axi.ar.bits.addr
  io.master_arlen           := memSys.io.axi.ar.bits.len
  io.master_arsize          := memSys.io.axi.ar.bits.size
  io.master_arburst         := memSys.io.axi.ar.bits.burst
  io.master_rready          := memSys.io.axi.r.ready
  memSys.io.axi.r.valid     := io.master_rvalid
  memSys.io.axi.r.bits.id   := io.master_rid
  memSys.io.axi.r.bits.data := io.master_rdata
  memSys.io.axi.r.bits.resp := io.master_rresp
  memSys.io.axi.r.bits.last := io.master_rlast

  io.slave_awready := false.B
  io.slave_wready  := false.B
  io.slave_bvalid  := false.B
  io.slave_bid     := 0.U
  io.slave_bresp   := 0.U
  io.slave_arready := false.B
  io.slave_rvalid  := false.B
  io.slave_rid     := 0.U
  io.slave_rdata   := 0.U
  io.slave_rresp   := 0.U
  io.slave_rlast   := false.B

  io.commit         := core.io.commit
  io.asyncInterrupt := core.io.asyncInterrupt
  io.halted         := core.io.halted

  // Preserve the external ports even though this fixed profile owns no external
  // interrupt source and accepts no inbound AXI slave transactions.
  dontTouch(io.interrupt)
  dontTouch(io.slave_awvalid)
  dontTouch(io.slave_awid)
  dontTouch(io.slave_awaddr)
  dontTouch(io.slave_awlen)
  dontTouch(io.slave_awsize)
  dontTouch(io.slave_awburst)
  dontTouch(io.slave_wvalid)
  dontTouch(io.slave_wdata)
  dontTouch(io.slave_wstrb)
  dontTouch(io.slave_wlast)
  dontTouch(io.slave_bready)
  dontTouch(io.slave_arvalid)
  dontTouch(io.slave_arid)
  dontTouch(io.slave_araddr)
  dontTouch(io.slave_arlen)
  dontTouch(io.slave_arsize)
  dontTouch(io.slave_arburst)
  dontTouch(io.slave_rready)
}
