// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
//
// Modified from rocket-chip TLB.scala at the locked source revision. This is
// the fixed one-set/four-way Sv32 form used independently by I$ and D$.
package npc.rocketmed

import chisel3._
import chisel3.util._

object MemoryAccess {
  val Fetch = 0.U(2.W)
  val Load  = 1.U(2.W)
  val Store = 2.U(2.W)
}

class TlbRequest extends Bundle {
  val vaddr  = UInt(32.W)
  val size   = UInt(2.W)
  val access = UInt(2.W)
  val priv   = UInt(2.W)
  val sum    = Bool()
  val mxr    = Bool()
  val satp   = UInt(32.W)
  val adue   = Bool()
}

class TlbResponse extends Bundle {
  val paddr       = UInt(32.W)
  val pageFault   = Bool()
  val accessFault = Bool()
  val tlbMiss     = Bool()
}

class PtwRequest extends Bundle {
  val vaddr  = UInt(32.W)
  val access = UInt(2.W)
  val priv   = UInt(2.W)
  val sum    = Bool()
  val mxr    = Bool()
  val satp   = UInt(32.W)
  val adue   = Bool()
}

class PtwResponse extends Bundle {
  val ppn         = UInt(22.W)
  // Sv32 level 1 is a 4 MiB superpage; level 0 is a 4 KiB page.
  val level       = UInt(1.W)
  val r           = Bool()
  val w           = Bool()
  val x           = Bool()
  val u           = Bool()
  val g           = Bool()
  val a           = Bool()
  val d           = Bool()
  val pageFault   = Bool()
  val accessFault = Bool()
}

class Sfence extends Bundle {
  val useAddress = Bool()
  val useAsid    = Bool()
  val vaddr      = UInt(32.W)
  val asid       = UInt(9.W)
}

class TlbEntry extends Bundle {
  val valid = Bool()
  val vpn   = UInt(20.W)
  val asid  = UInt(9.W)
  val ppn   = UInt(22.W)
  val level = UInt(1.W)
  val r     = Bool()
  val w     = Bool()
  val x     = Bool()
  val u     = Bool()
  val g     = Bool()
  val a     = Bool()
  val d     = Bool()
}

class Tlb(val instruction: Boolean) extends Module {
  override def desiredName: String = if (instruction) "InstructionTlb"
  else "DataTlb"

  val io = IO(new Bundle {
    val request     = Flipped(Decoupled(new TlbRequest))
    val response    = Decoupled(new TlbResponse)
    val ptwRequest  = Decoupled(new PtwRequest)
    val ptwResponse = Flipped(Decoupled(new PtwResponse))
    val sfence      = Input(Valid(new Sfence))
    val kill        = Input(Bool())
  })

  val idle :: lookup :: sendPtw :: waitPtw :: respond :: Nil = Enum(5)
  val state                                                  = RegInit(idle)
  val saved                                                  = Reg(new TlbRequest)
  val savedResponse                                          = Reg(new TlbResponse)
  val entries                                                = RegInit(VecInit(Seq.fill(RocketMed.TlbWays)(0.U.asTypeOf(new TlbEntry))))
  val replacement                                            = RegInit(0.U(2.W))
  val killedWalk                                             = RegInit(false.B)
  val flushedWalk                                            = RegInit(false.B)

  def permissionFault(
    request: TlbRequest,
    r:       Bool,
    w:       Bool,
    x:       Bool,
    u:       Bool,
    a:       Bool,
    d:       Bool
  ): Bool = {
    val isFetch       = request.access === MemoryAccess.Fetch
    val isLoad        = request.access === MemoryAccess.Load
    val privilegeOkay = Mux(
      request.priv === Privilege.U,
      u,
      Mux(request.priv === Privilege.S, Mux(isFetch, !u, !u || request.sum), true.B)
    )
    val operationOkay = Mux(isFetch, x, Mux(isLoad, r || (request.mxr && x), r && w))
    val adOkay        = a && (request.access =/= MemoryAccess.Store || d)
    !privilegeOkay || !operationOkay || !adOkay
  }

  def makeResponse(
    request:           TlbRequest,
    ppn:               UInt,
    level:             UInt,
    r:                 Bool,
    w:                 Bool,
    x:                 Bool,
    u:                 Bool,
    a:                 Bool,
    d:                 Bool,
    sourcePageFault:   Bool,
    sourceAccessFault: Bool,
    miss:              Bool
  ): TlbResponse = {
    val result        = Wire(new TlbResponse)
    val translatedPpn = Mux(level === 1.U, Cat(ppn(21, 10), request.vaddr(21, 12)), ppn)
    val physical      = Cat(translatedPpn, request.vaddr(11, 0))
    val bytesMinusOne = (1.U(4.W) << request.size) - 1.U
    val crossesPage   = (request.vaddr(11, 0) +& bytesMinusOne)(12)
    val permission    = permissionFault(request, r, w, x, u, a, d)
    result.paddr       := physical(31, 0)
    result.pageFault   := sourcePageFault || crossesPage || permission
    result.accessFault := sourceAccessFault || physical(33, 32).orR
    result.tlbMiss     := miss
    result
  }

  val vpn       = saved.vaddr(31, 12)
  val asid      = saved.satp(30, 22)
  val hits      = entries.map { entry =>
    val vpnMatch = Mux(entry.level === 1.U, entry.vpn(19, 10) === vpn(19, 10), entry.vpn === vpn)
    entry.valid && vpnMatch && (entry.g || entry.asid === asid)
  }
  val hit       = hits.reduce(_ || _)
  val hitEntry  = Mux1H(hits, entries)
  val vmEnabled = saved.satp(31) && saved.priv =/= Privilege.M

  io.request.ready          := state === idle && !io.kill
  io.response.valid         := state === respond && !io.kill
  io.response.bits          := savedResponse
  io.ptwRequest.valid       := state === sendPtw && !io.kill
  io.ptwRequest.bits.vaddr  := saved.vaddr
  io.ptwRequest.bits.access := saved.access
  io.ptwRequest.bits.priv   := saved.priv
  io.ptwRequest.bits.sum    := saved.sum
  io.ptwRequest.bits.mxr    := saved.mxr
  io.ptwRequest.bits.satp   := saved.satp
  io.ptwRequest.bits.adue   := saved.adue
  io.ptwResponse.ready      := state === waitPtw

  when(io.sfence.valid) {
    for (entry <- entries) {
      val addressMatch = !io.sfence.bits.useAddress ||
        Mux(
          entry.level === 1.U,
          entry.vpn(19, 10) === io.sfence.bits.vaddr(31, 22),
          entry.vpn === io.sfence.bits.vaddr(31, 12)
        )
      val asidMatch    = !io.sfence.bits.useAsid ||
        (!entry.g && entry.asid === io.sfence.bits.asid)
      when(addressMatch && asidMatch) { entry.valid := false.B }
    }
    when(state =/= idle) { flushedWalk := true.B }
  }

  when(io.request.fire) {
    saved       := io.request.bits
    killedWalk  := false.B
    flushedWalk := false.B
    state       := lookup
  }

  when(state === lookup) {
    if (instruction) {
      assert(saved.access === MemoryAccess.Fetch)
    }
    when(!vmEnabled) {
      savedResponse := makeResponse(
        saved,
        Cat(0.U(2.W), saved.vaddr(31, 12)),
        0.U,
        true.B,
        true.B,
        true.B,
        false.B,
        true.B,
        true.B,
        false.B,
        false.B,
        false.B
      )
      state         := respond
    }.elsewhen(hit) {
      savedResponse := makeResponse(
        saved,
        hitEntry.ppn,
        hitEntry.level,
        hitEntry.r,
        hitEntry.w,
        hitEntry.x,
        hitEntry.u,
        hitEntry.a,
        hitEntry.d,
        false.B,
        false.B,
        false.B
      )
      state         := respond
    }.otherwise {
      state := sendPtw
    }
  }

  when(state === sendPtw && io.ptwRequest.fire) {
    state := waitPtw
  }

  when(state === waitPtw && io.ptwResponse.fire) {
    when(killedWalk) {
      state := idle
    }.otherwise {
      val refill = io.ptwResponse.bits
      savedResponse := makeResponse(
        saved,
        refill.ppn,
        refill.level,
        refill.r,
        refill.w,
        refill.x,
        refill.u,
        refill.a,
        refill.d,
        refill.pageFault,
        refill.accessFault,
        true.B
      )
      when(!refill.pageFault && !refill.accessFault && !flushedWalk) {
        val entry = Wire(new TlbEntry)
        entry.valid          := true.B
        entry.vpn            := vpn
        entry.asid           := asid
        entry.ppn            := refill.ppn
        entry.level          := refill.level
        entry.r              := refill.r
        entry.w              := refill.w
        entry.x              := refill.x
        entry.u              := refill.u
        entry.g              := refill.g
        entry.a              := refill.a
        entry.d              := refill.d
        entries(replacement) := entry
        replacement          := replacement + 1.U
      }
      state         := respond
    }
  }

  when(state === respond && io.response.fire) {
    state := idle
  }

  when(io.kill) {
    when(state === waitPtw) {
      killedWalk := true.B
    }.otherwise {
      state := idle
    }
  }
}
