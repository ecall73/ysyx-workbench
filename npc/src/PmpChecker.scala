// See ../LICENSE.SiFive for license details.
//
// Modified from rocket-chip PMP.scala at the locked source revision. This
// version fixes eight entries, four-byte granularity, and a 32-bit physical
// address space.
package npc.rocketmed

import chisel3._
import chisel3.util._

class PmpChecker extends Module {
  val io = IO(new Bundle {
    val cfg           = Input(Vec(RocketMed.PmpRegions, UInt(8.W)))
    val addr          = Input(Vec(RocketMed.PmpRegions, UInt(30.W)))
    val requestAddr   = Input(UInt(32.W))
    val requestSize   = Input(UInt(2.W))
    val requestAccess = Input(UInt(2.W))
    val privilege     = Input(UInt(2.W))
    val allow         = Output(Bool())
    val matched       = Output(Bool())
  })

  val requestBytesMinusOne = (1.U(4.W) << io.requestSize) - 1.U
  val requestStart         = Cat(0.U(1.W), io.requestAddr)
  val requestEnd           = requestStart + requestBytesMinusOne

  val overlaps = Wire(Vec(RocketMed.PmpRegions, Bool()))
  val permits  = Wire(Vec(RocketMed.PmpRegions, Bool()))

  for (i <- 0 until RocketMed.PmpRegions) {
    val mode            = io.cfg(i)(4, 3)
    val previousAddress = if (i == 0) 0.U(30.W) else io.addr(i - 1)
    val torLower        = Cat(0.U(1.W), previousAddress, 0.U(2.W))
    val torUpper        = Cat(0.U(1.W), io.addr(i), 0.U(2.W))

    val invertedAddress = ~io.addr(i)
    val trailingOnes    = Mux(invertedAddress.orR, PriorityEncoder(invertedAddress), 30.U)
    val napotMaskWide   = (1.U(33.W) << (trailingOnes +& 3.U)) - 1.U
    val napotMask       = napotMaskWide(31, 0)
    val napotBase       = (io.addr(i) << 2) & ~napotMask
    val napotLower      = Cat(0.U(1.W), napotBase)
    val napotUpper      = Cat(0.U(1.W), napotBase | napotMask) + 1.U

    val na4Lower      = Cat(0.U(1.W), io.addr(i), 0.U(2.W))
    val na4Upper      = na4Lower + 4.U
    val lower         = Mux(mode === 1.U, torLower, Mux(mode === 2.U, na4Lower, napotLower))
    val upper         = Mux(mode === 1.U, torUpper, Mux(mode === 2.U, na4Upper, napotUpper))
    val active        = mode =/= 0.U
    val overlap       = active && requestEnd >= lower && requestStart < upper
    val contained     = requestStart >= lower && requestEnd < upper
    val permission    = MuxLookup(io.requestAccess, io.cfg(i)(0))(
      Seq(MemoryAccess.Fetch -> io.cfg(i)(2), MemoryAccess.Load -> io.cfg(i)(0), MemoryAccess.Store -> io.cfg(i)(1))
    )
    val machineBypass = io.privilege === Privilege.M && !io.cfg(i)(7)

    overlaps(i) := overlap
    permits(i)  := contained && (machineBypass || permission)
  }

  var anyMatch:      Bool = false.B
  var selectedAllow: Bool = io.privilege === Privilege.M
  for (i <- (0 until RocketMed.PmpRegions).reverse) {
    selectedAllow = Mux(overlaps(i), permits(i), selectedAllow)
    anyMatch = overlaps(i) || anyMatch
  }
  io.matched := anyMatch
  io.allow   := selectedAllow
}
