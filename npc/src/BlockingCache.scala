// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
//
// Modified from rocket-chip ICache.scala and DCache.scala at the locked source
// revision. Each cache uses one 1024 x 32-bit 1RW data array; a 64-byte line
// refills or writes back as sixteen sequential 32-bit beats.
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

  val io = IO(new BlockingCacheIO(instruction))

  private val AddressBits     = io.request.bits.addr.getWidth
  private val SetCount        = 64
  private val LineBytes       = 64
  private val RowBits         = io.readData.bits.data.getWidth
  private val RowBytes        = RowBits / 8
  private val RowsPerLine     = LineBytes / RowBytes
  private val SetBits         = log2Ceil(SetCount)
  private val RowOffsetBits   = log2Ceil(RowBytes)
  private val RowIndexBits    = log2Ceil(RowsPerLine)
  private val LineOffsetBits  = log2Ceil(LineBytes)
  private val TagBits         = AddressBits - SetBits - LineOffsetBits
  private val DataDepth       = SetCount * RowsPerLine
  private val DataAddressBits = log2Ceil(DataDepth)
  private val LastRow         = RowsPerLine - 1

  require(RowBits   % 8 == 0)
  require(LineBytes % RowBytes == 0)

  def cacheSet(address: UInt): UInt =
    address(LineOffsetBits + SetBits - 1, LineOffsetBits)
  def cacheWordAddress(set: UInt, word: UInt): UInt = Cat(set, word)

  val idle :: captureLookup :: decideLookup :: sendWriteAddress :: sendWriteData :: waitWriteResponse :: sendReadAddress :: receiveReadData :: restartLookup :: respond :: probeCaptureLookup :: probeDecideLookup :: probeRespond :: probeWaitAck :: flushLookup :: flushCaptureLookup :: flushDecideLookup :: flushWriteAddress :: flushWriteData :: flushWaitResponse :: flushComplete :: Nil =
    Enum(21)
  val state                                                                                                                                                                                                                                                                                                                                                                                      = RegInit(idle)
  val saved                                                                                                                                                                                                                                                                                                                                                                                      = Reg(new CacheRequest)
  val responseData                                                                                                                                                                                                                                                                                                                                                                               = Reg(UInt(32.W))
  val responseError                                                                                                                                                                                                                                                                                                                                                                              = RegInit(false.B)
  val requestMiss                                                                                                                                                                                                                                                                                                                                                                                = RegInit(false.B)
  val refillBeat                                                                                                                                                                                                                                                                                                                                                                                 = RegInit(0.U(RowIndexBits.W))
  val refillError                                                                                                                                                                                                                                                                                                                                                                                = RegInit(false.B)
  val writebackBeat                                                                                                                                                                                                                                                                                                                                                                              = RegInit(0.U(RowIndexBits.W))
  val lookupTag                                                                                                                                                                                                                                                                                                                                                                                  = Reg(UInt(TagBits.W))
  val lookupWord                                                                                                                                                                                                                                                                                                                                                                                 = Reg(UInt(32.W))
  val streamData                                                                                                                                                                                                                                                                                                                                                                                 = Reg(UInt(32.W))
  val streamDataValid                                                                                                                                                                                                                                                                                                                                                                            = RegInit(false.B)
  val probeSaved                                                                                                                                                                                                                                                                                                                                                                                 = if (!instruction) Some(Reg(new ProbeRequest)) else None
  val probeHit                                                                                                                                                                                                                                                                                                                                                                                   = if (!instruction) Some(RegInit(false.B)) else None
  val probeDirty                                                                                                                                                                                                                                                                                                                                                                                 = if (!instruction) Some(RegInit(false.B)) else None
  val probeBeat                                                                                                                                                                                                                                                                                                                                                                                  = if (!instruction) Some(RegInit(0.U(RowIndexBits.W))) else None
  val flushSet                                                                                                                                                                                                                                                                                                                                                                                   = if (!instruction) Some(RegInit(0.U(SetBits.W))) else None
  val flushBeat                                                                                                                                                                                                                                                                                                                                                                                  = if (!instruction) Some(RegInit(0.U(RowIndexBits.W))) else None
  val flushFailed                                                                                                                                                                                                                                                                                                                                                                                = if (!instruction) Some(RegInit(false.B)) else None

  val valid = RegInit(0.U(SetCount.W))
  val dirty = RegInit(0.U(SetCount.W))

  val validAfterInvalidate = Mux(io.invalidate, 0.U(SetCount.W), valid)
  val dirtyAfterInvalidate = Mux(io.invalidate, 0.U(SetCount.W), dirty)

  val tagMemory  = Module(
    new SinglePortSram(
      SetCount,
      TagBits,
      masked = false,
      moduleName = if (instruction) "ICacheTagSram" else "DCacheTagSram"
    )
  )
  val dataMemory = Module(
    new SinglePortSram(
      DataDepth,
      RowBits,
      masked = !instruction,
      moduleName = if (instruction) "ICacheDataSram" else "DCacheDataSram"
    )
  )

  val probeLookup       = if (instruction) false.B else io.probeRequest.get.fire
  val probeLookupSet    =
    if (instruction) 0.U(SetBits.W)
    else cacheSet(io.probeRequest.get.bits.lineAddress)
  val requestSet        = cacheSet(io.request.bits.addr)
  val lookupEnable      = (io.request.fire && !io.request.bits.uncached) ||
    state === restartLookup || probeLookup || state === flushLookup
  val lookupSet         = Mux(
    state === flushLookup,
    (if (instruction) 0.U else flushSet.get),
    Mux(probeLookup, probeLookupSet, Mux(state === restartLookup, cacheSet(saved.addr), requestSet))
  )
  val lookupWordIndex   = Mux(
    state === flushLookup || probeLookup,
    0.U(RowIndexBits.W),
    Mux(
      state === restartLookup,
      saved.addr(LineOffsetBits - 1, RowOffsetBits),
      io.request.bits.addr(LineOffsetBits - 1, RowOffsetBits)
    )
  )
  val lookupDataAddress = cacheWordAddress(lookupSet, lookupWordIndex)

  val savedSet     = cacheSet(saved.addr)
  val savedTag     = saved.addr(AddressBits - 1, LineOffsetBits + SetBits)
  val savedWord    = saved.addr(LineOffsetBits - 1, RowOffsetBits)
  val lineHit      = valid(savedSet) && lookupTag === savedTag
  val oldWord      = lookupWord
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
  val reservationAddress = Reg(UInt((AddressBits - RowOffsetBits).W))
  val reservationMatches = reservationValid &&
    reservationAddress === saved.addr(AddressBits - 1, RowOffsetBits)
  val isLr               = saved.atomic === AtomicOperation.Lr
  val isSc               = saved.atomic === AtomicOperation.Sc
  val isAmo              = saved.atomic >= AtomicOperation.Swap
  val hitWrites          = saved.write && saved.atomic === AtomicOperation.None ||
    (isSc && reservationMatches) || isAmo
  val hitWriteData       = Mux(isAmo, atomicResult, saved.data)
  val hitWriteMask       = Mux(isAmo || isSc, "hf".U, saved.mask)
  val hitResponse        = state === decideLookup && lineHit
  val hitResponseData    = Mux(
    isSc,
    Mux(reservationMatches, 0.U, 1.U),
    Mux(saved.write && !isAmo, 0.U, oldWord)
  )

  val refillTransfer   = state === receiveReadData && io.readData.fire && !saved.uncached
  val refillAnyError   = refillError || io.readData.bits.error
  val hitWriteTransfer = state === decideLookup && lineHit && io.response.fire && hitWrites
  val tagWriteEnable   = refillTransfer && io.readData.bits.last && !refillAnyError
  val dataWriteEnable  = if (instruction) refillTransfer else refillTransfer || hitWriteTransfer
  val dataWriteAddress = Mux(
    refillTransfer,
    cacheWordAddress(savedSet, refillBeat),
    cacheWordAddress(savedSet, savedWord)
  )
  val dataWriteData    =
    if (instruction) io.readData.bits.data
    else Mux(refillTransfer, io.readData.bits.data, hitWriteData)
  val dataWriteMask    =
    if (instruction) "hf".U(4.W)
    else Mux(refillTransfer, "hf".U, hitWriteMask)

  val streamReadEnable  = WireDefault(false.B)
  val streamReadAddress = WireDefault(0.U(DataAddressBits.W))
  val streamFire        = WireDefault(false.B)
  val streamReadValid   = RegNext(streamReadEnable, false.B)

  tagMemory.io.enable    := lookupEnable || tagWriteEnable
  tagMemory.io.write     := tagWriteEnable
  tagMemory.io.address   := Mux(tagWriteEnable, savedSet, lookupSet)
  tagMemory.io.writeData := savedTag
  tagMemory.io.writeMask := 0.U

  val dataReadEnable = lookupEnable || streamReadEnable
  dataMemory.io.enable    := dataReadEnable || dataWriteEnable
  dataMemory.io.write     := dataWriteEnable
  dataMemory.io.address   := Mux(
    dataWriteEnable,
    dataWriteAddress,
    Mux(streamReadEnable, streamReadAddress, lookupDataAddress)
  )
  dataMemory.io.writeData := dataWriteData
  dataMemory.io.writeMask := dataWriteMask

  assert(!(lookupEnable && tagWriteEnable))
  assert(!(lookupEnable && streamReadEnable))
  assert(!(dataReadEnable && dataWriteEnable))
  if (!instruction) {
    assert(!(refillTransfer && hitWriteTransfer))
  }

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
  io.readAddress.bits.addr   := Mux(
    saved.uncached,
    saved.addr,
    Cat(saved.addr(AddressBits - 1, LineOffsetBits), 0.U(LineOffsetBits.W))
  )
  io.readAddress.bits.len    := Mux(saved.uncached, 0.U, LastRow.U)
  io.readAddress.bits.size   := Mux(saved.uncached, saved.size, RowOffsetBits.U)
  io.readAddress.bits.atomic := Mux(saved.uncached, saved.atomic, AtomicOperation.None)
  io.readData.ready          := state === receiveReadData

  if (!instruction) {
    val flushingAddress     = state === flushWriteAddress
    val flushingData        = state === flushWriteData
    val cachedWritebackData = state === sendWriteData && !saved.uncached
    val uncachedWriteData   = state === sendWriteData && saved.uncached
    val streamedWriteData   = cachedWritebackData || flushingData
    val streamSourceValid   = streamDataValid || streamReadValid
    val streamSourceData    = Mux(streamDataValid, streamData, dataMemory.io.readData)
    val streamedWriteLast   = Mux(
      flushingData,
      flushBeat.get === LastRow.U,
      writebackBeat === LastRow.U
    )

    io.writeAddress.get.valid       := state === sendWriteAddress || flushingAddress
    io.writeAddress.get.bits.addr   := Mux(
      flushingAddress,
      Cat(lookupTag, flushSet.get, 0.U(LineOffsetBits.W)),
      Mux(saved.uncached, saved.addr, Cat(lookupTag, savedSet, 0.U(LineOffsetBits.W)))
    )
    io.writeAddress.get.bits.len    := Mux(
      flushingAddress,
      LastRow.U,
      Mux(saved.uncached, 0.U, LastRow.U)
    )
    io.writeAddress.get.bits.size   := Mux(
      flushingAddress,
      RowOffsetBits.U,
      Mux(saved.uncached, saved.size, RowOffsetBits.U)
    )
    io.writeAddress.get.bits.atomic := Mux(
      flushingAddress,
      AtomicOperation.None,
      Mux(saved.uncached, saved.atomic, AtomicOperation.None)
    )
    io.writeData.get.valid          := uncachedWriteData || streamedWriteData && streamSourceValid
    io.writeData.get.bits.data      := Mux(uncachedWriteData, saved.data, streamSourceData)
    io.writeData.get.bits.mask      := Mux(uncachedWriteData, saved.mask, "hf".U)
    io.writeData.get.bits.last      := uncachedWriteData || streamedWriteLast
    io.writeResponse.get.ready      := state === waitWriteResponse ||
      state === flushWaitResponse

    io.probeRequest.get.ready       := state === idle
    io.probeResponse.get.valid      := state === probeRespond && streamSourceValid
    io.probeResponse.get.bits.hit   := probeHit.get
    io.probeResponse.get.bits.dirty := probeDirty.get
    io.probeResponse.get.bits.data  := streamSourceData
    io.probeResponse.get.bits.last  := !probeHit.get || !probeDirty.get ||
      probeBeat.get === LastRow.U
    io.probeAck.get.ready           := state === probeWaitAck
    io.flushDone.get                := state === flushComplete
    io.flushError.get               := flushFailed.get

    val writeStreamFire    = streamedWriteData && io.writeData.get.fire
    val probeStreamFire    = state === probeRespond && io.probeResponse.get.fire
    val writeNextRead      = writeStreamFire && !streamedWriteLast
    val probeNextRead      = probeStreamFire && probeHit.get && probeDirty.get && probeBeat.get =/= LastRow.U
    val startWritebackRead = state === decideLookup && !lineHit && valid(savedSet) && dirty(savedSet)

    streamFire        := writeStreamFire || probeStreamFire
    streamReadEnable  := startWritebackRead || writeNextRead || probeNextRead
    streamReadAddress := MuxCase(
      0.U,
      Seq(
        startWritebackRead                     -> cacheWordAddress(savedSet, 0.U(RowIndexBits.W)),
        (writeNextRead && flushingData)        -> cacheWordAddress(flushSet.get, flushBeat.get + 1.U),
        (writeNextRead && cachedWritebackData) -> cacheWordAddress(savedSet, writebackBeat + 1.U),
        probeNextRead                          -> cacheWordAddress(cacheSet(probeSaved.get.lineAddress), probeBeat.get + 1.U)
      )
    )

    assert(!(streamDataValid && streamReadValid))
  }

  when(io.invalidate) {
    valid            := 0.U
    dirty            := 0.U
    reservationValid := false.B
    streamDataValid  := false.B
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
      assert(io.probeRequest.get.bits.lineAddress(LineOffsetBits - 1, 0) === 0.U)
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
    lookupTag  := tagMemory.io.readData
    lookupWord := dataMemory.io.readData
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
          reservationAddress := saved.addr(AddressBits - 1, RowOffsetBits)
        }.elsewhen(saved.write || isAmo || isSc) {
          reservationValid := false.B
        }
        when(hitWrites) {
          dirty := dirtyAfterInvalidate.bitSet(savedSet, true.B)
        }
        state := Mux(io.request.fire, captureLookup, idle)
      }
    }.otherwise {
      requestMiss := true.B
      if (instruction) {
        state := sendReadAddress
      } else {
        when(valid(savedSet) && dirty(savedSet)) {
          streamDataValid := false.B
        }
        state := Mux(valid(savedSet) && dirty(savedSet), sendWriteAddress, sendReadAddress)
      }
    }
  }

  if (!instruction) {
    def advanceFlush(): Unit = {
      valid := validAfterInvalidate.bitSet(flushSet.get, false.B)
      dirty := dirtyAfterInvalidate.bitSet(flushSet.get, false.B)
      when(flushSet.get === (SetCount - 1).U) {
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
        dirty := dirtyAfterInvalidate.bitSet(savedSet, false.B)
        state := sendReadAddress
      }
    }

    when(state === probeDecideLookup) {
      val set = cacheSet(probeSaved.get.lineAddress)
      val hit = valid(set) &&
        lookupTag === probeSaved.get.lineAddress(AddressBits - 1, LineOffsetBits + SetBits)
      probeHit.get    := hit
      probeDirty.get  := hit && dirty(set)
      probeBeat.get   := 0.U
      streamData      := lookupWord
      streamDataValid := true.B
      state           := probeRespond
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
        valid := validAfterInvalidate.bitSet(set, false.B)
        dirty := dirtyAfterInvalidate.bitSet(set, false.B)
      }
      state := idle
    }
    when(state === flushDecideLookup) {
      when(valid(flushSet.get) && dirty(flushSet.get)) {
        streamData      := lookupWord
        streamDataValid := true.B
        state           := flushWriteAddress
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
        valid := validAfterInvalidate.bitSet(flushSet.get, true.B)
        dirty := dirtyAfterInvalidate.bitSet(flushSet.get, true.B)
        when(flushSet.get === (SetCount - 1).U) {
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

  when(streamReadValid && !streamFire) {
    streamData      := dataMemory.io.readData
    streamDataValid := true.B
  }
  when(streamFire || io.invalidate) {
    streamDataValid := false.B
  }

  when(state === sendReadAddress && io.readAddress.fire) {
    refillBeat  := 0.U
    refillError := false.B
    state       := receiveReadData
  }

  when(state === receiveReadData && io.readData.fire) {
    val anyError = refillAnyError
    refillError := anyError
    when(saved.uncached) {
      assert(io.readData.bits.last)
      responseData  := io.readData.bits.data
      responseError := anyError
      state         := respond
    }.otherwise {
      assert(io.readData.bits.last === (refillBeat === LastRow.U))
      when(io.readData.bits.last) {
        when(anyError) {
          valid         := validAfterInvalidate.bitSet(savedSet, false.B)
          responseData  := 0.U
          responseError := true.B
          state         := respond
        }.otherwise {
          valid := validAfterInvalidate.bitSet(savedSet, true.B)
          dirty := dirtyAfterInvalidate.bitSet(savedSet, false.B)
          state := restartLookup
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
