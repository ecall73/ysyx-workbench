// See ../LICENSE.SiFive for license details.
//
// Two-ingress to one-master AXI4Full32 memory system. D$ wins read
// arbitration while idle; ownership is then held through RLAST. The caches
// themselves own refill/writeback state, while this module owns AXI identity,
// response routing, backpressure, and reset cleanup.
package npc.rocketmed

import chisel3._
import chisel3.util._

class AxiAddress extends Bundle {
  val id    = UInt(4.W)
  val addr  = UInt(32.W)
  val len   = UInt(8.W)
  val size  = UInt(3.W)
  val burst = UInt(2.W)
}

class AxiReadData extends Bundle {
  val id   = UInt(4.W)
  val data = UInt(32.W)
  val resp = UInt(2.W)
  val last = Bool()
}

class AxiWriteData extends Bundle {
  val data = UInt(32.W)
  val strb = UInt(4.W)
  val last = Bool()
}

class AxiWriteResponse extends Bundle {
  val id   = UInt(4.W)
  val resp = UInt(2.W)
}

class AxiMasterIO extends Bundle {
  val aw = Decoupled(new AxiAddress)
  val w  = Decoupled(new AxiWriteData)
  val b  = Flipped(Decoupled(new AxiWriteResponse))
  val ar = Decoupled(new AxiAddress)
  val r  = Flipped(Decoupled(new AxiReadData))
}

class MemSys extends Module {
  val io = IO(new Bundle {
    val instructionReadAddress = Flipped(Decoupled(new CacheReadAddress))
    val instructionReadData    = Decoupled(new CacheReadData)
    val dataReadAddress        = Flipped(Decoupled(new CacheReadAddress))
    val dataReadData           = Decoupled(new CacheReadData)
    val dataWriteAddress       = Flipped(Decoupled(new CacheWriteAddress))
    val dataWriteData          = Flipped(Decoupled(new CacheWriteData))
    val dataWriteResponse      = Decoupled(new CacheWriteResponse)
    val probeRequest           = Flipped(Decoupled(new ProbeRequest))
    val probeAck               = Decoupled(new ProbeAck)
    val dataProbeRequest       = Decoupled(new ProbeRequest)
    val dataProbeResponse      = Flipped(Decoupled(new ProbeResponse))
    val dataProbeAck           = Decoupled(new ProbeAck)
    val axi                    = new AxiMasterIO
  })

  private val InstructionId = 0.U(4.W)
  private val DataId        = 1.U(4.W)

  val readIdle :: readResponse :: Nil = Enum(2)
  val readState                       = RegInit(readIdle)
  val readOwnerData                   = RegInit(false.B)
  val readAddressLocked               = RegInit(false.B)
  val readBeatsLeft                   = RegInit(0.U(9.W))

  val chooseData        = Mux(readAddressLocked, readOwnerData, io.dataReadAddress.valid)
  val selectedRead      = Mux(chooseData, io.dataReadAddress.bits, io.instructionReadAddress.bits)
  val selectedReadValid = Mux(
    chooseData,
    io.dataReadAddress.valid,
    io.instructionReadAddress.valid
  )
  io.axi.ar.valid                 := readState === readIdle && selectedReadValid
  io.axi.ar.bits.id               := Mux(chooseData, DataId, InstructionId)
  io.axi.ar.bits.addr             := selectedRead.addr
  io.axi.ar.bits.len              := selectedRead.len
  io.axi.ar.bits.size             := selectedRead.size
  io.axi.ar.bits.burst            := Mux(selectedRead.len.orR, 1.U, 0.U)
  io.dataReadAddress.ready        := readState === readIdle && chooseData &&
    io.axi.ar.ready
  io.instructionReadAddress.ready := readState === readIdle && !chooseData &&
    io.instructionReadAddress.valid && io.axi.ar.ready

  when(io.axi.ar.valid && !io.axi.ar.ready) {
    readOwnerData     := chooseData
    readAddressLocked := true.B
  }
  when(io.axi.ar.fire) {
    readOwnerData     := chooseData
    readAddressLocked := false.B
    readBeatsLeft     := selectedRead.len +& 1.U
    readState         := readResponse
  }

  val expectedReadId = Mux(readOwnerData, DataId, InstructionId)
  val readIdError    = io.axi.r.bits.id =/= expectedReadId
  val readLastError  = io.axi.r.bits.last =/= (readBeatsLeft === 1.U)
  io.dataReadData.valid        := readState === readResponse && readOwnerData &&
    io.axi.r.valid
  io.dataReadData.bits.data    := io.axi.r.bits.data
  io.dataReadData.bits.last    := io.axi.r.bits.last
  io.dataReadData.bits.error   := io.axi.r.bits.resp.orR || readIdError ||
    readLastError
  io.instructionReadData.valid := readState === readResponse &&
    !readOwnerData && io.axi.r.valid
  io.instructionReadData.bits  := io.dataReadData.bits
  io.axi.r.ready               := readState === readResponse && Mux(
    readOwnerData,
    io.dataReadData.ready,
    io.instructionReadData.ready
  )

  when(io.axi.r.fire) {
    when(io.axi.r.bits.last) {
      readBeatsLeft := 0.U
      readState     := readIdle
    }.otherwise {
      readBeatsLeft := readBeatsLeft - 1.U
    }
  }

  val writeIdle :: writeIssue :: writeData :: writeResponse :: probeWaitResponse :: probeWriteIssue :: probeWriteData :: probeWriteResponse :: probeAck :: Nil =
    Enum(9)
  val writeState                                                                                                                                               = RegInit(writeIdle)
  val savedWriteAddress                                                                                                                                        = Reg(new CacheWriteAddress)
  val writeBeatsLeft                                                                                                                                           = RegInit(0.U(9.W))
  val probeLineAddress                                                                                                                                         = Reg(UInt(32.W))
  val probeBeatsLeft                                                                                                                                           = RegInit(0.U(5.W))
  val probeError                                                                                                                                               = RegInit(false.B)
  val writeAddressSent                                                                                                                                         = RegInit(false.B)
  val writeFirstDataSent                                                                                                                                       = RegInit(false.B)
  val writeFirstLast                                                                                                                                           = RegInit(false.B)

  io.dataWriteAddress.ready := writeState === writeIdle &&
    !io.probeRequest.valid
  when(io.dataWriteAddress.fire) {
    savedWriteAddress  := io.dataWriteAddress.bits
    writeBeatsLeft     := io.dataWriteAddress.bits.len +& 1.U
    writeAddressSent   := false.B
    writeFirstDataSent := false.B
    writeFirstLast     := false.B
    writeState         := writeIssue
  }

  val normalWriteIssue      = writeState === writeIssue
  val probeWriteIssueActive = writeState === probeWriteIssue
  val issuingWrite          = normalWriteIssue || probeWriteIssueActive
  io.axi.aw.valid      := issuingWrite && !writeAddressSent
  io.axi.aw.bits.id    := DataId
  io.axi.aw.bits.addr  := Mux(probeWriteIssueActive, probeLineAddress, savedWriteAddress.addr)
  io.axi.aw.bits.len   := Mux(probeWriteIssueActive, 15.U, savedWriteAddress.len)
  io.axi.aw.bits.size  := Mux(probeWriteIssueActive, 2.U, savedWriteAddress.size)
  io.axi.aw.bits.burst := Mux(
    probeWriteIssueActive ||
      savedWriteAddress.len.orR,
    1.U,
    0.U
  )

  val normalWriteBeat = (normalWriteIssue && !writeFirstDataSent) ||
    writeState === writeData
  val probeWriteBeat  = (probeWriteIssueActive && !writeFirstDataSent) ||
    writeState === probeWriteData
  io.axi.w.valid         := Mux(probeWriteBeat, io.dataProbeResponse.valid, normalWriteBeat && io.dataWriteData.valid)
  io.axi.w.bits.data     := Mux(probeWriteBeat, io.dataProbeResponse.bits.data, io.dataWriteData.bits.data)
  io.axi.w.bits.strb     := Mux(probeWriteBeat, "hf".U, io.dataWriteData.bits.mask)
  io.axi.w.bits.last     := Mux(probeWriteBeat, io.dataProbeResponse.bits.last, io.dataWriteData.bits.last)
  io.dataWriteData.ready := normalWriteBeat && io.axi.w.ready

  val issueAddressFire    = io.axi.aw.fire
  val normalFirstDataFire = normalWriteIssue && !writeFirstDataSent &&
    io.axi.w.fire
  val probeFirstDataFire  = probeWriteIssueActive && !writeFirstDataSent &&
    io.axi.w.fire

  when(issuingWrite && issueAddressFire) {
    writeAddressSent := true.B
  }
  when(normalWriteIssue && normalFirstDataFire) {
    assert(io.dataWriteData.bits.last === (writeBeatsLeft === 1.U))
    writeFirstDataSent := true.B
    writeFirstLast     := io.dataWriteData.bits.last
    writeBeatsLeft     := writeBeatsLeft - 1.U
  }
  when(probeWriteIssueActive && probeFirstDataFire) {
    assert(io.dataProbeResponse.bits.hit && io.dataProbeResponse.bits.dirty)
    assert(io.dataProbeResponse.bits.last === (probeBeatsLeft === 1.U))
    writeFirstDataSent := true.B
    writeFirstLast     := io.dataProbeResponse.bits.last
    probeBeatsLeft     := probeBeatsLeft - 1.U
  }

  val issueAddressComplete    = writeAddressSent || issueAddressFire
  val normalFirstDataComplete = writeFirstDataSent || normalFirstDataFire
  val probeFirstDataComplete  = writeFirstDataSent || probeFirstDataFire
  val issueFirstLast          = Mux(writeFirstDataSent, writeFirstLast, io.axi.w.bits.last)
  when(
    normalWriteIssue && issueAddressComplete &&
      normalFirstDataComplete
  ) {
    writeAddressSent   := false.B
    writeFirstDataSent := false.B
    when(issueFirstLast) {
      writeBeatsLeft := 0.U
      writeState     := writeResponse
    }.otherwise {
      writeState := writeData
    }
  }
  when(
    probeWriteIssueActive && issueAddressComplete &&
      probeFirstDataComplete
  ) {
    writeAddressSent   := false.B
    writeFirstDataSent := false.B
    when(issueFirstLast) {
      probeBeatsLeft := 0.U
      writeState     := probeWriteResponse
    }.otherwise {
      writeState := probeWriteData
    }
  }

  when(io.axi.w.fire && writeState === writeData) {
    val expectedLast = writeBeatsLeft === 1.U
    assert(io.axi.w.bits.last === expectedLast)
    when(io.axi.w.bits.last) {
      writeBeatsLeft := 0.U
      writeState     := writeResponse
    }.otherwise {
      writeBeatsLeft := writeBeatsLeft - 1.U
    }
  }
  when(io.axi.w.fire && writeState === probeWriteData) {
    assert(
      io.dataProbeResponse.bits.hit &&
        io.dataProbeResponse.bits.dirty
    )
    assert(io.dataProbeResponse.bits.last === (probeBeatsLeft === 1.U))
    when(io.dataProbeResponse.bits.last) {
      probeBeatsLeft := 0.U
      writeState     := probeWriteResponse
    }.otherwise {
      probeBeatsLeft := probeBeatsLeft - 1.U
    }
  }

  val writeIdError = io.axi.b.bits.id =/= DataId
  io.dataWriteResponse.valid      := writeState === writeResponse && io.axi.b.valid
  io.dataWriteResponse.bits.error := io.axi.b.bits.resp.orR || writeIdError
  io.axi.b.ready                  := writeState === writeResponse &&
    io.dataWriteResponse.ready || writeState === probeWriteResponse
  when(io.axi.b.fire && writeState === writeResponse) {
    writeState := writeIdle
  }

  io.dataProbeRequest.valid := writeState === writeIdle &&
    io.probeRequest.valid
  io.dataProbeRequest.bits  := io.probeRequest.bits
  io.probeRequest.ready     := writeState === writeIdle &&
    io.dataProbeRequest.ready
  when(io.dataProbeRequest.fire) {
    assert(io.probeRequest.bits.lineAddress(5, 0) === 0.U)
    probeLineAddress := io.probeRequest.bits.lineAddress
    probeError       := false.B
    writeState       := probeWaitResponse
  }

  io.dataProbeResponse.ready := Mux(
    probeWriteBeat,
    io.axi.w.ready,
    writeState === probeWaitResponse && io.dataProbeResponse.valid &&
      (!io.dataProbeResponse.bits.hit || !io.dataProbeResponse.bits.dirty)
  )
  when(
    writeState === probeWaitResponse && io.dataProbeResponse.valid &&
      io.dataProbeResponse.bits.hit && io.dataProbeResponse.bits.dirty
  ) {
    probeBeatsLeft     := 16.U
    writeAddressSent   := false.B
    writeFirstDataSent := false.B
    writeFirstLast     := false.B
    writeState         := probeWriteIssue
  }
  when(writeState === probeWaitResponse && io.dataProbeResponse.fire) {
    assert(io.dataProbeResponse.bits.last)
    writeState := probeAck
  }

  when(io.axi.b.fire && writeState === probeWriteResponse) {
    probeError := io.axi.b.bits.resp.orR || writeIdError
    writeState := probeAck
  }

  io.dataProbeAck.valid      := writeState === probeAck && io.probeAck.ready
  io.dataProbeAck.bits.error := probeError
  io.probeAck.valid          := writeState === probeAck && io.dataProbeAck.ready
  io.probeAck.bits.error     := probeError
  when(
    writeState === probeAck && io.dataProbeAck.ready &&
      io.probeAck.ready
  ) {
    writeState := writeIdle
  }

  when(readState === readResponse && io.axi.r.valid) {
    assert(io.axi.r.bits.id === expectedReadId)
    assert(io.axi.r.bits.last === (readBeatsLeft === 1.U))
  }
  when(
    (writeState === writeResponse ||
      writeState === probeWriteResponse) && io.axi.b.valid
  ) {
    assert(io.axi.b.bits.id === DataId)
  }
}
