// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
//
// Modified from rocket-chip PTW.scala at the locked source revision. This
// fixed Sv32 walker keeps the selected eight-entry non-leaf PTE cache and one
// blocking 32-bit memory transaction at a time.
package npc.rocketmed

import chisel3._
import chisel3.util._

class PtwMemoryRequest extends Bundle {
  val addr = UInt(32.W)
}

class PtwMemoryResponse extends Bundle {
  val data  = UInt(32.W)
  val error = Bool()
}

class PteCacheEntry extends Bundle {
  val valid = Bool()
  val tag   = UInt(32.W)
  val ppn   = UInt(22.W)
}

class PageTableWalker extends Module {
  val io = IO(new Bundle {
    val request        = Flipped(Decoupled(new PtwRequest))
    val response       = Decoupled(new PtwResponse)
    val memoryRequest  = Decoupled(new PtwMemoryRequest)
    val memoryResponse = Flipped(Decoupled(new PtwMemoryResponse))
    val sfence         = Input(Bool())
  })

  val idle :: checkCache :: sendRead :: waitRead :: examine :: respond :: Nil = Enum(6)
  val state                                                                   = RegInit(idle)
  val saved                                                                   = Reg(new PtwRequest)
  val level                                                                   = RegInit(1.U(1.W))
  val tableBase                                                               = Reg(UInt(34.W))
  val pteAddressReg                                                           = Reg(UInt(32.W))
  val pteData                                                                 = Reg(UInt(32.W))
  val savedResponse                                                           = Reg(new PtwResponse)
  val cache                                                                   = RegInit(VecInit(Seq.fill(8)(0.U.asTypeOf(new PteCacheEntry))))
  val replacement                                                             = RegInit(0.U(3.W))

  val vpnIndex          = Mux(level === 1.U, saved.vaddr(31, 22), saved.vaddr(21, 12))
  val pteAddressFull    = tableBase + (vpnIndex << 2)
  val pteAddressInvalid = pteAddressFull(33, 32).orR
  val pteAddress        = pteAddressFull(31, 0)
  val cacheHits         = cache.map(entry => entry.valid && level === 1.U && entry.tag === pteAddress)
  val cacheHit          = cacheHits.reduce(_ || _)
  val cachedPpn         = Mux1H(cacheHits, cache.map(_.ppn))

  io.request.ready           := state === idle
  io.response.valid          := state === respond
  io.response.bits           := savedResponse
  io.memoryRequest.valid     := state === sendRead
  io.memoryRequest.bits.addr := pteAddressReg
  io.memoryResponse.ready    := state === waitRead

  def fillResponse(pte: UInt, pageFault: Bool, accessFault: Bool): Unit = {
    savedResponse.ppn         := pte(31, 10)
    savedResponse.level       := level
    savedResponse.r           := pte(1)
    savedResponse.w           := pte(2)
    savedResponse.x           := pte(3)
    savedResponse.u           := pte(4)
    savedResponse.g           := pte(5)
    savedResponse.a           := pte(6)
    savedResponse.d           := pte(7)
    savedResponse.pageFault   := pageFault
    savedResponse.accessFault := accessFault
    state                     := respond
  }

  def permissionFault(pte: UInt): Bool = {
    val isFetch       = saved.access === MemoryAccess.Fetch
    val isLoad        = saved.access === MemoryAccess.Load
    val privilegeOkay = Mux(
      saved.priv === Privilege.U,
      pte(4),
      Mux(saved.priv === Privilege.S, Mux(isFetch, !pte(4), !pte(4) || saved.sum), true.B)
    )
    val operationOkay = Mux(isFetch, pte(3), Mux(isLoad, pte(1) || (saved.mxr && pte(3)), pte(1) && pte(2)))
    !privilegeOkay || !operationOkay
  }

  when(io.sfence) {
    for (entry <- cache) { entry.valid := false.B }
  }

  when(io.request.fire) {
    saved     := io.request.bits
    level     := 1.U
    tableBase := Cat(io.request.bits.satp(21, 0), 0.U(12.W))
    state     := checkCache
  }

  when(state === checkCache) {
    when(pteAddressInvalid) {
      fillResponse(0.U, false.B, true.B)
    }.elsewhen(cacheHit) {
      tableBase := Cat(cachedPpn, 0.U(12.W))
      level     := 0.U
    }.otherwise {
      pteAddressReg := pteAddress
      state         := sendRead
    }
  }

  when(state === sendRead && io.memoryRequest.fire) {
    state := waitRead
  }

  when(state === waitRead && io.memoryResponse.fire) {
    when(io.memoryResponse.bits.error) {
      fillResponse(0.U, false.B, true.B)
    }.otherwise {
      pteData := io.memoryResponse.bits.data
      state   := examine
    }
  }

  when(state === examine) {
    val valid               = pteData(0)
    val readable            = pteData(1)
    val writable            = pteData(2)
    val executable          = pteData(3)
    val leaf                = readable || executable
    val invalid             = !valid || (!readable && writable)
    val ppn                 = pteData(31, 10)
    val misalignedSuperpage = level === 1.U && ppn(9, 0).orR
    val nonLeafReserved     = pteData(4) || pteData(6) || pteData(7)
    val missingAd           = !pteData(6) ||
      (saved.access === MemoryAccess.Store && !pteData(7))

    when(invalid) {
      fillResponse(pteData, true.B, false.B)
    }.elsewhen(leaf) {
      when(misalignedSuperpage || permissionFault(pteData) || missingAd) {
        fillResponse(pteData, true.B, false.B)
      }.otherwise {
        fillResponse(pteData, false.B, false.B)
      }
    }.elsewhen(level === 0.U || nonLeafReserved) {
      fillResponse(pteData, true.B, false.B)
    }.elsewhen(ppn(21, 20).orR) {
      fillResponse(pteData, false.B, true.B)
    }.otherwise {
      when(!io.sfence) {
        cache(replacement).valid := true.B
        cache(replacement).tag   := pteAddressReg
        cache(replacement).ppn   := ppn
        replacement              := replacement + 1.U
      }
      tableBase := Cat(ppn, 0.U(12.W))
      level     := 0.U
      state     := checkCache
    }
  }

  when(state === respond && io.response.fire) {
    state := idle
  }
}
