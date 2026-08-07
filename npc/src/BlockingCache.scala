// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
//
// Modified from rocket-chip ICache.scala and DCache.scala at the locked source
// revision. Arrays use independent 32-bit SyncReadMem banks, while each fixed
// 64-byte line refills or writes back as sixteen 32-bit beats.
package npc.rocketmed

import chisel3._
import chisel3.util._

object AtomicOperation {
  val None = 0.U(4.W)
  val Lr   = 1.U(4.W)
  val Sc   = 2.U(4.W)
  val Swap = 3.U(4.W)
  val Add  = 4.U(4.W)
  val Xor  = 5.U(4.W)
  val And  = 6.U(4.W)
  val Or   = 7.U(4.W)
  val Min  = 8.U(4.W)
  val Max  = 9.U(4.W)
  val Minu = 10.U(4.W)
  val Maxu = 11.U(4.W)
}

class CacheRequest extends Bundle {
  val addr     = UInt(32.W)
  val write    = Bool()
  val data     = UInt(32.W)
  val mask     = UInt(4.W)
  val size     = UInt(2.W)
  val uncached = Bool()
  val atomic   = UInt(4.W)
}

class CacheResponse extends Bundle {
  val data  = UInt(32.W)
  val error = Bool()
  val miss  = Bool()
}

class CacheReadAddress extends Bundle {
  val addr   = UInt(32.W)
  val len    = UInt(8.W)
  val size   = UInt(3.W)
  val atomic = UInt(4.W)
}

class CacheReadData extends Bundle {
  val data  = UInt(32.W)
  val last  = Bool()
  val error = Bool()
}

class CacheWriteAddress extends Bundle {
  val addr   = UInt(32.W)
  val len    = UInt(8.W)
  val size   = UInt(3.W)
  val atomic = UInt(4.W)
}

class CacheWriteData extends Bundle {
  val data = UInt(32.W)
  val mask = UInt(4.W)
  val last = Bool()
}

class CacheWriteResponse extends Bundle {
  val error = Bool()
}

class ProbeRequest extends Bundle {
  val lineAddress = UInt(32.W)
  val invalidate  = Bool()
}

class ProbeResponse extends Bundle {
  val hit   = Bool()
  val dirty = Bool()
  val data  = UInt(32.W)
  val last  = Bool()
}

class ProbeAck extends Bundle {
  val error = Bool()
}

class BlockingCacheIO(val instruction: Boolean) extends Bundle {
  val request       = Flipped(Decoupled(new CacheRequest))
  val response      = Decoupled(new CacheResponse)
  val invalidate    = Input(Bool())
  val readAddress   = Decoupled(new CacheReadAddress)
  val readData      = Flipped(Decoupled(new CacheReadData))
  val writeAddress  = if (!instruction) Some(Decoupled(new CacheWriteAddress)) else None
  val writeData     = if (!instruction) Some(Decoupled(new CacheWriteData)) else None
  val writeResponse = if (!instruction) Some(Flipped(Decoupled(new CacheWriteResponse))) else None
  val probeRequest  = if (!instruction) Some(Flipped(Decoupled(new ProbeRequest))) else None
  val probeResponse = if (!instruction) Some(Decoupled(new ProbeResponse)) else None
  val probeAck      = if (!instruction) Some(Flipped(Decoupled(new ProbeAck))) else None
  val flush         = if (!instruction) Some(Input(Bool())) else None
  val flushDone     = if (!instruction) Some(Output(Bool())) else None
  val flushError    = if (!instruction) Some(Output(Bool())) else None
}

class BlockingCache(val instruction: Boolean) extends Module {
  override def desiredName: String = if (instruction) "InstructionCache"
  else "DataCache"

  val io                     = IO(new BlockingCacheIO(instruction))
  private val SetBits        = 6
  private val LineOffsetBits = 6
  private val TagBits        = 32 - SetBits - LineOffsetBits

  def cacheSet(address: UInt): UInt = address(11, 6)

  val idle :: captureLookup :: decideLookup :: sendWriteAddress :: sendWriteData :: waitWriteResponse :: sendReadAddress :: receiveReadData :: restartLookup :: respond :: probeCaptureLookup :: probeDecideLookup :: probeRespond :: probeWaitAck :: flushLookup :: flushCaptureLookup :: flushDecideLookup :: flushWriteAddress :: flushWriteData :: flushWaitResponse :: flushComplete :: Nil =
    Enum(21)
  val state                                                                                                                                                                                                                                                                                                                                                                                      = RegInit(idle)
  val saved                                                                                                                                                                                                                                                                                                                                                                                      = Reg(new CacheRequest)
  val responseData                                                                                                                                                                                                                                                                                                                                                                               = Reg(UInt(32.W))
  val responseError                                                                                                                                                                                                                                                                                                                                                                              = RegInit(false.B)
  val requestMiss                                                                                                                                                                                                                                                                                                                                                                                = RegInit(false.B)
  val refillBeat                                                                                                                                                                                                                                                                                                                                                                                 = RegInit(0.U(4.W))
  val refillError                                                                                                                                                                                                                                                                                                                                                                                = RegInit(false.B)
  val writebackBeat                                                                                                                                                                                                                                                                                                                                                                              = RegInit(0.U(4.W))
  val lookupTag                                                                                                                                                                                                                                                                                                                                                                                  = Reg(UInt(TagBits.W))
  val lookupLine                                                                                                                                                                                                                                                                                                                                                                                 = Reg(Vec(RocketMed.RefillBeats, UInt(32.W)))
  val probeSaved                                                                                                                                                                                                                                                                                                                                                                                 = if (!instruction) Some(Reg(new ProbeRequest)) else None
  val probeHit                                                                                                                                                                                                                                                                                                                                                                                   = if (!instruction) Some(RegInit(false.B)) else None
  val probeDirty                                                                                                                                                                                                                                                                                                                                                                                 = if (!instruction) Some(RegInit(false.B)) else None
  val probeBeat                                                                                                                                                                                                                                                                                                                                                                                  = if (!instruction) Some(RegInit(0.U(4.W))) else None
  val flushSet                                                                                                                                                                                                                                                                                                                                                                                   = if (!instruction) Some(RegInit(0.U(SetBits.W))) else None
  val flushBeat                                                                                                                                                                                                                                                                                                                                                                                  = if (!instruction) Some(RegInit(0.U(4.W))) else None
  val flushFailed                                                                                                                                                                                                                                                                                                                                                                                = if (!instruction) Some(RegInit(false.B)) else None

  val valid      = RegInit(VecInit(Seq.fill(RocketMed.CacheSets)(false.B)))
  val dirty      = RegInit(VecInit(Seq.fill(RocketMed.CacheSets)(false.B)))
  val tagMemory  = SyncReadMem(RocketMed.CacheSets, UInt(TagBits.W))
  val dataMemory = Seq.fill(RocketMed.RefillBeats)(SyncReadMem(RocketMed.CacheSets, UInt(RocketMed.RowBits.W)))

  val probeLookup    = if (instruction) false.B else io.probeRequest.get.fire
  val probeLookupSet =
    if (instruction) 0.U(SetBits.W)
    else cacheSet(io.probeRequest.get.bits.lineAddress)
  val requestSet     = cacheSet(io.request.bits.addr)
  val lookupEnable   = (io.request.fire && !io.request.bits.uncached) ||
    state === restartLookup || probeLookup || state === flushLookup
  val lookupSet      = Mux(
    state === flushLookup,
    (if (instruction) 0.U else flushSet.get),
    Mux(probeLookup, probeLookupSet, Mux(state === restartLookup, cacheSet(saved.addr), requestSet))
  )
  val tagRead        = tagMemory.read(lookupSet, lookupEnable)
  val lineRead       = VecInit(dataMemory.map(_.read(lookupSet, lookupEnable)))

  val savedSet     = cacheSet(saved.addr)
  val savedTag     = saved.addr(31, 12)
  val savedWord    = saved.addr(5, 2)
  val lineHit      = valid(savedSet) && lookupTag === savedTag
  val oldWord      = lookupLine(savedWord)
  val byteMask     = FillInterleaved(8, saved.mask)
  val maskedStore  = (oldWord & ~byteMask) | (saved.data & byteMask)
  val atomicResult = MuxLookup(saved.atomic, saved.data)(
    Seq(
      AtomicOperation.Swap -> saved.data,
      AtomicOperation.Add  -> (oldWord + saved.data),
      AtomicOperation.Xor  -> (oldWord ^ saved.data),
      AtomicOperation.And  -> (oldWord & saved.data),
      AtomicOperation.Or   -> (oldWord | saved.data),
      AtomicOperation.Min  -> Mux(oldWord.asSInt < saved.data.asSInt, oldWord, saved.data),
      AtomicOperation.Max  -> Mux(oldWord.asSInt > saved.data.asSInt, oldWord, saved.data),
      AtomicOperation.Minu -> Mux(oldWord < saved.data, oldWord, saved.data),
      AtomicOperation.Maxu -> Mux(oldWord > saved.data, oldWord, saved.data)
    )
  )

  val reservationValid   = RegInit(false.B)
  val reservationAddress = Reg(UInt(30.W))
  val reservationMatches = reservationValid &&
    reservationAddress === saved.addr(31, 2)
  val isLr               = saved.atomic === AtomicOperation.Lr
  val isSc               = saved.atomic === AtomicOperation.Sc
  val isAmo              = saved.atomic >= AtomicOperation.Swap
  val hitWrites          = saved.write && saved.atomic === AtomicOperation.None ||
    (isSc && reservationMatches) || isAmo
  val hitWriteData       = Mux(isAmo, atomicResult, maskedStore)
  val hitResponse        = state === decideLookup && lineHit
  val hitResponseData    = Mux(
    isSc,
    Mux(reservationMatches, 0.U, 1.U),
    Mux(saved.write && !isAmo, 0.U, oldWord)
  )

  val instructionHitTurnaround = if (instruction) {
    hitResponse && io.response.ready && !io.request.bits.uncached
  } else {
    false.B
  }
  io.request.ready       := (state === idle || instructionHitTurnaround) &&
    (if (instruction) true.B
     else !io.probeRequest.get.valid && !io.flush.get)
  io.response.valid      := state === respond || hitResponse
  io.response.bits.data  := Mux(hitResponse, hitResponseData, responseData)
  io.response.bits.error := Mux(hitResponse, false.B, responseError)
  io.response.bits.miss  := requestMiss

  io.readAddress.valid       := state === sendReadAddress
  io.readAddress.bits.addr   := Mux(saved.uncached, saved.addr, Cat(saved.addr(31, 6), 0.U(6.W)))
  io.readAddress.bits.len    := Mux(saved.uncached, 0.U, 15.U)
  io.readAddress.bits.size   := Mux(saved.uncached, saved.size, 2.U)
  io.readAddress.bits.atomic := Mux(saved.uncached, saved.atomic, AtomicOperation.None)
  io.readData.ready          := state === receiveReadData

  if (!instruction) {
    val flushingAddress = state === flushWriteAddress
    val flushingData    = state === flushWriteData
    io.writeAddress.get.valid       := state === sendWriteAddress || flushingAddress
    io.writeAddress.get.bits.addr   := Mux(
      flushingAddress,
      Cat(lookupTag, flushSet.get, 0.U(6.W)),
      Mux(saved.uncached, saved.addr, Cat(lookupTag, savedSet, 0.U(6.W)))
    )
    io.writeAddress.get.bits.len    := Mux(flushingAddress, 15.U, Mux(saved.uncached, 0.U, 15.U))
    io.writeAddress.get.bits.size   := Mux(flushingAddress, 2.U, Mux(saved.uncached, saved.size, 2.U))
    io.writeAddress.get.bits.atomic := Mux(
      flushingAddress,
      AtomicOperation.None,
      Mux(saved.uncached, saved.atomic, AtomicOperation.None)
    )
    io.writeData.get.valid          := state === sendWriteData || flushingData
    io.writeData.get.bits.data      := Mux(
      flushingData,
      lookupLine(flushBeat.get),
      Mux(saved.uncached, saved.data, lookupLine(writebackBeat))
    )
    io.writeData.get.bits.mask      := Mux(flushingData, "hf".U, Mux(saved.uncached, saved.mask, "hf".U))
    io.writeData.get.bits.last      := Mux(flushingData, flushBeat.get === 15.U, saved.uncached || writebackBeat === 15.U)
    io.writeResponse.get.ready      := state === waitWriteResponse ||
      state === flushWaitResponse

    io.probeRequest.get.ready       := state === idle
    io.probeResponse.get.valid      := state === probeRespond
    io.probeResponse.get.bits.hit   := probeHit.get
    io.probeResponse.get.bits.dirty := probeDirty.get
    io.probeResponse.get.bits.data  := lookupLine(probeBeat.get)
    io.probeResponse.get.bits.last  := !probeHit.get || !probeDirty.get ||
      probeBeat.get === 15.U
    io.probeAck.get.ready           := state === probeWaitAck
    io.flushDone.get                := state === flushComplete
    io.flushError.get               := flushFailed.get
  }

  when(io.invalidate) {
    for (set <- 0 until RocketMed.CacheSets) {
      valid(set) := false.B
      dirty(set) := false.B
    }
    reservationValid := false.B
  }
  when(io.request.fire) {
    if (instruction) {
      assert(!io.request.bits.write)
      assert(io.request.bits.atomic === AtomicOperation.None)
    }
    saved         := io.request.bits
    requestMiss   := false.B
    responseError := false.B
    when(io.request.bits.uncached) {
      if (instruction) {
        state := sendReadAddress
      } else {
        state := Mux(io.request.bits.write, sendWriteAddress, sendReadAddress)
      }
    }.otherwise {
      state := captureLookup
    }
  }

  if (!instruction) {
    when(io.probeRequest.get.fire) {
      assert(io.probeRequest.get.bits.lineAddress(5, 0) === 0.U)
      probeSaved.get   := io.probeRequest.get.bits
      reservationValid := false.B
      state            := probeCaptureLookup
    }
    when(state === idle && io.flush.get && !io.probeRequest.get.valid) {
      flushSet.get     := 0.U
      flushFailed.get  := false.B
      reservationValid := false.B
      state            := flushLookup
    }
  }

  when(state === flushLookup) {
    state := flushCaptureLookup
  }
  when(
    state === captureLookup || state === probeCaptureLookup ||
      state === flushCaptureLookup
  ) {
    lookupTag  := tagRead
    lookupLine := lineRead
    state      := Mux(
      state === probeCaptureLookup,
      probeDecideLookup,
      Mux(state === flushCaptureLookup, flushDecideLookup, decideLookup)
    )
  }

  when(state === decideLookup) {
    when(lineHit) {
      when(io.response.fire) {
        when(isLr) {
          reservationValid   := true.B
          reservationAddress := saved.addr(31, 2)
        }.elsewhen(saved.write || isAmo || isSc) {
          reservationValid := false.B
        }
        when(hitWrites) {
          for (i <- 0 until RocketMed.RefillBeats) {
            when(savedWord === i.U) {
              dataMemory(i).write(savedSet, hitWriteData)
            }
          }
          dirty(savedSet) := true.B
        }
        state := Mux(io.request.fire, captureLookup, idle)
      }
    }.otherwise {
      requestMiss := true.B
      if (instruction) {
        state := sendReadAddress
      } else {
        state := Mux(valid(savedSet) && dirty(savedSet), sendWriteAddress, sendReadAddress)
      }
    }
  }

  if (!instruction) {
    def advanceFlush(): Unit = {
      valid(flushSet.get) := false.B
      dirty(flushSet.get) := false.B
      when(flushSet.get === (RocketMed.CacheSets - 1).U) {
        state := flushComplete
      }.otherwise {
        flushSet.get := flushSet.get + 1.U
        state        := flushLookup
      }
    }

    when(state === sendWriteAddress && io.writeAddress.get.fire) {
      writebackBeat := 0.U
      state         := sendWriteData
    }
    when(state === sendWriteData && io.writeData.get.fire) {
      when(io.writeData.get.bits.last) {
        state := waitWriteResponse
      }.otherwise {
        writebackBeat := writebackBeat + 1.U
      }
    }
    when(state === waitWriteResponse && io.writeResponse.get.fire) {
      when(io.writeResponse.get.bits.error) {
        responseData  := 0.U
        responseError := true.B
        state         := respond
      }.elsewhen(saved.uncached) {
        responseData  := Mux(isSc, 0.U, 0.U)
        responseError := false.B
        state         := respond
      }.otherwise {
        dirty(savedSet) := false.B
        state           := sendReadAddress
      }
    }

    when(state === probeDecideLookup) {
      val set = cacheSet(probeSaved.get.lineAddress)
      val hit = valid(set) &&
        lookupTag === probeSaved.get.lineAddress(31, 12)
      probeHit.get   := hit
      probeDirty.get := hit && dirty(set)
      probeBeat.get  := 0.U
      state          := probeRespond
    }
    when(state === probeRespond && io.probeResponse.get.fire) {
      when(io.probeResponse.get.bits.last) {
        state := probeWaitAck
      }.otherwise {
        probeBeat.get := probeBeat.get + 1.U
      }
    }
    when(state === probeWaitAck && io.probeAck.get.fire) {
      val set = cacheSet(probeSaved.get.lineAddress)
      when(
        !io.probeAck.get.bits.error && probeHit.get &&
          probeSaved.get.invalidate
      ) {
        valid(set) := false.B
        dirty(set) := false.B
      }
      state := idle
    }
    when(state === flushDecideLookup) {
      when(valid(flushSet.get) && dirty(flushSet.get)) {
        state := flushWriteAddress
      }.otherwise {
        advanceFlush()
      }
    }
    when(state === flushWriteAddress && io.writeAddress.get.fire) {
      flushBeat.get := 0.U
      state         := flushWriteData
    }
    when(state === flushWriteData && io.writeData.get.fire) {
      when(io.writeData.get.bits.last) {
        state := flushWaitResponse
      }.otherwise {
        flushBeat.get := flushBeat.get + 1.U
      }
    }
    when(state === flushWaitResponse && io.writeResponse.get.fire) {
      flushFailed.get := flushFailed.get || io.writeResponse.get.bits.error
      when(io.writeResponse.get.bits.error) {
        valid(flushSet.get) := true.B
        dirty(flushSet.get) := true.B
        when(flushSet.get === (RocketMed.CacheSets - 1).U) {
          state := flushComplete
        }.otherwise {
          flushSet.get := flushSet.get + 1.U
          state        := flushLookup
        }
      }.otherwise {
        advanceFlush()
      }
    }
    when(state === flushComplete) {
      state := idle
    }
  }

  when(state === sendReadAddress && io.readAddress.fire) {
    refillBeat  := 0.U
    refillError := false.B
    state       := receiveReadData
  }

  when(state === receiveReadData && io.readData.fire) {
    val anyError = refillError || io.readData.bits.error
    refillError := anyError
    when(saved.uncached) {
      assert(io.readData.bits.last)
      responseData  := io.readData.bits.data
      responseError := anyError
      state         := respond
    }.otherwise {
      for (i <- 0 until RocketMed.RefillBeats) {
        when(refillBeat === i.U) {
          dataMemory(i).write(savedSet, io.readData.bits.data)
        }
      }
      assert(io.readData.bits.last === (refillBeat === 15.U))
      when(io.readData.bits.last) {
        when(anyError) {
          valid(savedSet) := false.B
          responseData    := 0.U
          responseError   := true.B
          state           := respond
        }.otherwise {
          tagMemory.write(savedSet, savedTag)
          valid(savedSet) := true.B
          dirty(savedSet) := false.B
          state           := restartLookup
        }
      }.otherwise {
        refillBeat := refillBeat + 1.U
      }
    }
  }

  when(state === restartLookup) {
    state := captureLookup
  }

  when(state === respond && io.response.fire) {
    state := idle
  }
}
