// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
//
// Single-issue integration of the selected Rocket Med architectural
// components. The implementation deliberately keeps only one architectural
// instruction in flight, which makes the commit observation a pure post-state
// projection while retaining independent I$/D$, TLBs, and a shared PTW.
package npc.rocketmed

import chisel3._
import chisel3.util._

class CoreInterruptEvent extends Bundle {
  val cause  = UInt(32.W)
  val epc    = UInt(32.W)
  val target = UInt(32.W)
}

class CoreCommit extends Bundle {
  val valid             = Bool()
  val pc                = UInt(32.W)
  val instruction       = UInt(32.W)
  val instructionLength = UInt(3.W)
  val instructionValid  = Bool()
  val nextPc            = UInt(32.W)
  val gpr               = Vec(32, UInt(32.W))
  val csr               = new CsrState
}

class RocketCore extends Module {
  val io = IO(new Bundle {
    val resetVector = Input(UInt(32.W))
    val interrupts  = Input(new LocalInterrupts)

    val instructionReadAddress = Decoupled(new CacheReadAddress)
    val instructionReadData    = Flipped(Decoupled(new CacheReadData))
    val dataReadAddress        = Decoupled(new CacheReadAddress)
    val dataReadData           = Flipped(Decoupled(new CacheReadData))
    val dataWriteAddress       = Decoupled(new CacheWriteAddress)
    val dataWriteData          = Decoupled(new CacheWriteData)
    val dataWriteResponse      = Flipped(Decoupled(new CacheWriteResponse))

    val dataProbeRequest  = Flipped(Decoupled(new ProbeRequest))
    val dataProbeResponse = Decoupled(new ProbeResponse)
    val dataProbeAck      = Flipped(Decoupled(new ProbeAck))
    val commit            = Output(new CoreCommit)
    val asyncInterrupt    = Output(Valid(new CoreInterruptEvent))
    val halted            = Output(Bool())
  })

  val ibuf    = Module(new InstructionBuffer)
  val decoder = Module(new InstructionDecoder)
  val csr     = Module(new CsrFile)
  val mulDiv  = Module(new IterativeMulDiv)
  val itlb    = Module(new Tlb(instruction = true))
  val dtlb    = Module(new Tlb(instruction = false))
  val ptw     = Module(new PageTableWalker)
  val clint   = Module(new Clint)
  val icache  = Module(new BlockingCache(instruction = true))
  val dcache  = Module(new BlockingCache(instruction = false))

  val gpr             = RegInit(VecInit(Seq.fill(32)(0.U(32.W))))
  val fetchPc         = Reg(UInt(32.W))
  val architecturalPc = Reg(UInt(32.W))
  val halted          = RegInit(false.B)

  val eIdle :: eExecute :: eMulDivWait :: eDataTlbRequest :: eDataTlbWait :: eDataAccess :: eDataCacheWait :: eFenceWait :: Nil =
    Enum(8)
  val executeState                                                                                                              = RegInit(eIdle)

  val savedPc                 = Reg(UInt(32.W))
  val savedRaw                = Reg(UInt(32.W))
  val savedRvc                = Reg(Bool())
  val savedIbufIllegal        = Reg(Bool())
  val savedPageFault          = Reg(Bool())
  val savedAccessFault        = Reg(Bool())
  val savedDecoded            = Reg(new DecodedInstruction)
  val savedRs1                = Reg(UInt(32.W))
  val savedRs2                = Reg(UInt(32.W))
  val savedVirtualAddress     = Reg(UInt(32.W))
  val savedPhysicalAddress    = Reg(UInt(32.W))
  val savedMemoryAccess       = Reg(UInt(2.W))
  val savedEffectivePrivilege = Reg(UInt(2.W))

  val fIdle :: fTlbRequest :: fTlbWait :: fCacheRequest :: fCacheWait :: fPush :: Nil = Enum(6)
  val fetchState                                                                      = RegInit(fIdle)
  val savedFetchPc                                                                    = Reg(UInt(32.W))
  val savedFetchPhysical                                                              = Reg(UInt(32.W))
  val fetchPageFault                                                                  = RegInit(false.B)
  val fetchAccessFault                                                                = RegInit(false.B)
  val fetchDiscard                                                                    = RegInit(false.B)

  val commitValid             = RegInit(false.B)
  val commitPc                = Reg(UInt(32.W))
  val commitInstruction       = Reg(UInt(32.W))
  val commitInstructionLength = Reg(UInt(3.W))
  val commitInstructionValid  = Reg(Bool())
  val commitNextPc            = Reg(UInt(32.W))
  val interruptValid          = RegInit(false.B)
  val interruptCause          = Reg(UInt(32.W))
  val interruptEpc            = Reg(UInt(32.W))
  val interruptTarget         = Reg(UInt(32.W))

  val completePulse         = WireDefault(false.B)
  val completeRetired       = WireDefault(false.B)
  val completeNextPc        = WireDefault(architecturalPc)
  val redirectPulse         = WireDefault(false.B)
  val redirectTarget        = WireDefault(architecturalPc)
  val sfencePulse           = WireDefault(false.B)
  val sfence                = WireDefault(0.U.asTypeOf(new Sfence))
  val instructionInvalidate = WireDefault(false.B)

  val trap      = WireDefault(0.U.asTypeOf(new TrapRequest))
  val ret       = WireDefault(0.U(2.W))
  val csrAccess = WireDefault(0.U.asTypeOf(new CsrAccess))

  def cacheable(address: UInt): Bool = {
    val highNibble = address(31, 28)
    highNibble === 8.U || highNibble === 9.U ||
    highNibble === 10.U || highNibble === 11.U ||
    address(31, 24) === "h0f".U ||
    address(31, 12) === "h20000".U ||
    highNibble === 3.U
  }

  def alu(operation: UInt, lhs: UInt, rhs: UInt): UInt =
    MuxLookup(operation, lhs + rhs)(
      Seq(
        AluOperation.Add   -> (lhs + rhs),
        AluOperation.Sub   -> (lhs - rhs),
        AluOperation.Sll   -> (lhs << rhs(4, 0)),
        AluOperation.Slt   -> (lhs.asSInt < rhs.asSInt),
        AluOperation.Sltu  -> (lhs < rhs),
        AluOperation.Xor   -> (lhs ^ rhs),
        AluOperation.Srl   -> (lhs >> rhs(4, 0)),
        AluOperation.Sra   -> (lhs.asSInt >> rhs(4, 0)).asUInt,
        AluOperation.Or    -> (lhs | rhs),
        AluOperation.And   -> (lhs & rhs),
        AluOperation.Copy2 -> rhs
      )
    )

  def complete(nextPc: UInt, retired: Bool): Unit = {
    completePulse   := true.B
    completeRetired := retired
    completeNextPc  := nextPc
  }

  def redirect(nextPc: UInt): Unit = {
    redirectPulse  := true.B
    redirectTarget := nextPc
  }

  def raiseTrap(cause: UInt, tval: UInt): Unit = {
    trap.valid := true.B
    trap.cause := cause
    trap.epc   := savedPc
    trap.tval  := tval
    complete(csr.io.trapTarget, false.B)
    redirect(csr.io.trapTarget)
  }

  decoder.io.instruction := ibuf.io.instruction.bits.expanded.bits

  csr.io.access          := csrAccess
  csr.io.trap            := trap
  csr.io.ret             := ret
  csr.io.retired         := completePulse && completeRetired
  csr.io.time            := clint.io.time
  csr.io.stimecmp        := clint.io.stimecmp
  csr.io.interrupts.msip := io.interrupts.msip || clint.io.msip
  csr.io.interrupts.mtip := io.interrupts.mtip || clint.io.mtip
  csr.io.interrupts.stip := io.interrupts.stip || clint.io.stip
  csr.io.interrupts.seip := io.interrupts.seip
  clint.io.stimecmpWrite := csr.io.stimecmpWrite
  clint.io.stce          := csr.io.state.menvcfgh(31)

  val mstatus                       = csr.io.state.mstatus
  val currentPrivilege              = csr.io.state.priv
  val dataPrivilege                 = Mux(currentPrivilege === Privilege.M && mstatus(17), mstatus(12, 11), currentPrivilege)
  val instructionTranslationEnabled = csr.io.state.satp(31) && currentPrivilege =/= Privilege.M
  val dataTranslationEnabled        = csr.io.state.satp(31) && dataPrivilege =/= Privilege.M
  val sum                           = mstatus(18)
  val mxr                           = mstatus(19)

  // Shared PTW arbitration gives an outstanding walk a stable owner.
  val ptwBusy        = RegInit(false.B)
  val ptwOwnerData   = RegInit(false.B)
  val selectDataWalk = dtlb.io.ptwRequest.valid
  ptw.io.request.valid     := !ptwBusy &&
    (dtlb.io.ptwRequest.valid || itlb.io.ptwRequest.valid)
  ptw.io.request.bits      := Mux(selectDataWalk, dtlb.io.ptwRequest.bits, itlb.io.ptwRequest.bits)
  dtlb.io.ptwRequest.ready := !ptwBusy && selectDataWalk &&
    ptw.io.request.ready
  itlb.io.ptwRequest.ready := !ptwBusy && !selectDataWalk &&
    itlb.io.ptwRequest.valid && ptw.io.request.ready
  when(ptw.io.request.fire) {
    ptwBusy      := true.B
    ptwOwnerData := selectDataWalk
  }

  dtlb.io.ptwResponse.valid := ptwBusy && ptwOwnerData &&
    ptw.io.response.valid
  dtlb.io.ptwResponse.bits  := ptw.io.response.bits
  itlb.io.ptwResponse.valid := ptwBusy && !ptwOwnerData &&
    ptw.io.response.valid
  itlb.io.ptwResponse.bits  := ptw.io.response.bits
  ptw.io.response.ready     := ptwBusy && Mux(ptwOwnerData, dtlb.io.ptwResponse.ready, itlb.io.ptwResponse.ready)
  when(ptw.io.response.fire) { ptwBusy := false.B }

  itlb.io.sfence.valid := sfencePulse
  itlb.io.sfence.bits  := sfence
  dtlb.io.sfence.valid := sfencePulse
  dtlb.io.sfence.bits  := sfence
  ptw.io.sfence        := sfencePulse

  val canStartFetch            = !halted && !csr.io.interruptValid &&
    executeState =/= eFenceWait
  val sequentialFetchPc        = (savedFetchPc & "hfffffffc".U) + 4.U
  val sequentialFetchPhysical  = (savedFetchPhysical & "hfffffffc".U) + 4.U
  val canReuseFetchTranslation = !fetchPageFault && !fetchAccessFault &&
    sequentialFetchPc(31, 12) === savedFetchPc(31, 12)
  val cacheFetchResponse       = fetchState === fCacheWait && !fetchDiscard &&
    icache.io.response.valid
  val cacheFetchCanAdvance     = cacheFetchResponse && ibuf.io.fetch.ready &&
    canStartFetch && canReuseFetchTranslation && !icache.io.response.bits.error

  // Frontend: translate one aligned fetch word, then feed the IBuf.
  itlb.io.request.valid       := fetchState === fTlbRequest
  itlb.io.request.bits.vaddr  := savedFetchPc & "hfffffffc".U
  itlb.io.request.bits.size   := 2.U
  itlb.io.request.bits.access := MemoryAccess.Fetch
  itlb.io.request.bits.priv   := currentPrivilege
  itlb.io.request.bits.sum    := false.B
  itlb.io.request.bits.mxr    := mxr
  itlb.io.request.bits.satp   := csr.io.state.satp
  itlb.io.response.ready      := fetchState === fTlbWait
  itlb.io.kill                := redirectPulse

  val chainedFetchRequest  = cacheFetchCanAdvance
  val fetchRequestPhysical = Mux(
    chainedFetchRequest,
    sequentialFetchPhysical,
    savedFetchPhysical
  )
  icache.io.request.valid         := fetchState === fCacheRequest || chainedFetchRequest
  icache.io.request.bits.addr     := fetchRequestPhysical & "hfffffffc".U
  icache.io.request.bits.write    := false.B
  icache.io.request.bits.data     := 0.U
  icache.io.request.bits.mask     := 0.U
  icache.io.request.bits.size     := 2.U
  icache.io.request.bits.uncached := !cacheable(fetchRequestPhysical)
  icache.io.request.bits.atomic   := AtomicOperation.None
  icache.io.response.ready        := fetchState === fCacheWait &&
    (fetchDiscard || ibuf.io.fetch.ready)
  icache.io.invalidate            := instructionInvalidate

  ibuf.io.fetch.valid            := fetchState === fPush || cacheFetchResponse
  ibuf.io.fetch.bits.pc          := savedFetchPc
  ibuf.io.fetch.bits.data        := Mux(cacheFetchResponse, icache.io.response.bits.data, 0.U)
  ibuf.io.fetch.bits.pageFault   := fetchPageFault
  ibuf.io.fetch.bits.accessFault := Mux(
    cacheFetchResponse,
    icache.io.response.bits.error,
    fetchAccessFault
  )
  ibuf.io.kill                   := redirectPulse

  // The frontend is independent of the single in-order execute slot. Keeping
  // it idle while an instruction executes serializes every I-TLB/I$ hit
  // behind execution and defeats the existing instruction buffer.
  when(fetchState === fIdle && canStartFetch && ibuf.io.fetch.ready) {
    savedFetchPc := fetchPc
    when(instructionTranslationEnabled) {
      fetchState := fTlbRequest
    }.otherwise {
      savedFetchPhysical := fetchPc
      fetchPageFault     := false.B
      fetchAccessFault   := false.B
      fetchState         := fCacheRequest
    }
  }
  when(fetchState === fTlbRequest && itlb.io.request.fire) {
    fetchState := fTlbWait
  }
  when(fetchState === fTlbWait && itlb.io.response.fire) {
    savedFetchPhysical := itlb.io.response.bits.paddr
    fetchPageFault     := itlb.io.response.bits.pageFault
    fetchAccessFault   := itlb.io.response.bits.accessFault
    fetchState         := Mux(
      itlb.io.response.bits.pageFault ||
        itlb.io.response.bits.accessFault,
      fPush,
      fCacheRequest
    )
  }
  when(fetchState === fCacheRequest && icache.io.request.fire) {
    fetchState := fCacheWait
  }
  when(fetchState === fCacheWait && icache.io.response.fire) {
    when(fetchDiscard) {
      fetchDiscard := false.B
      fetchState   := fIdle
    }.otherwise {
      assert(ibuf.io.fetch.fire)
      fetchPc := sequentialFetchPc
      when(canStartFetch && canReuseFetchTranslation && !icache.io.response.bits.error) {
        savedFetchPc       := sequentialFetchPc
        savedFetchPhysical := sequentialFetchPhysical
        fetchPageFault     := false.B
        fetchAccessFault   := false.B
        fetchState         := Mux(icache.io.request.fire, fCacheWait, fCacheRequest)
      }.otherwise {
        fetchState := fIdle
      }
    }
  }
  when(fetchState === fPush && ibuf.io.fetch.fire) {
    fetchPc    := sequentialFetchPc
    fetchState := fIdle
  }

  val sequentialPc = savedPc + Mux(savedRvc, 2.U, 4.U)
  val lhs          = Mux(savedDecoded.operand1Pc, savedPc, savedRs1)
  val rhs          = Mux(savedDecoded.operand2Immediate, savedDecoded.immediate, savedRs2)
  val aluResult    = alu(savedDecoded.alu, lhs, rhs)
  val branchTaken  = MuxLookup(savedDecoded.branch, false.B)(
    Seq(
      BranchOperation.Eq  -> (savedRs1 === savedRs2),
      BranchOperation.Ne  -> (savedRs1 =/= savedRs2),
      BranchOperation.Lt  -> (savedRs1.asSInt < savedRs2.asSInt),
      BranchOperation.Ge  -> (savedRs1.asSInt >= savedRs2.asSInt),
      BranchOperation.Ltu -> (savedRs1 < savedRs2),
      BranchOperation.Geu -> (savedRs1 >= savedRs2)
    )
  )

  // Ordinary ALU instructions complete in the execute stage. Let decode
  // capture the following instruction in that same cycle and forward the
  // result into its source operands, eliminating the otherwise empty eIdle
  // bubble without changing stage latency or issue width.
  val ordinaryExecuteCompletion   = executeState === eExecute &&
    !(savedPageFault || savedAccessFault || savedIbufIllegal || savedDecoded.illegal) &&
    savedDecoded.system === SystemOperation.None && !savedDecoded.csr &&
    !savedDecoded.mulDiv && !savedDecoded.memory &&
    !savedDecoded.jal && !savedDecoded.jalr
  val simpleAluCompletion         = ordinaryExecuteCompletion &&
    savedDecoded.branch === BranchOperation.None
  val untakenBranchCompletion     = ordinaryExecuteCompletion &&
    savedDecoded.branch =/= BranchOperation.None && !branchTaken
  val sequentialExecuteCompletion = simpleAluCompletion || untakenBranchCompletion
  val simpleAluWrites             = simpleAluCompletion && savedDecoded.writeRd && savedDecoded.rd.orR
  val mulDivCompletion            = executeState === eMulDivWait && mulDiv.io.response.valid

  val responseByteOffset     = savedVirtualAddress(1, 0)
  val responseShifted        = dcache.io.response.bits.data >> (responseByteOffset << 3)
  val responseByte           = responseShifted(7, 0)
  val responseHalf           = responseShifted(15, 0)
  val responseLoadData       = MuxLookup(savedDecoded.memorySize, dcache.io.response.bits.data)(
    Seq(
      0.U -> Mux(
        savedDecoded.memoryUnsigned,
        Cat(0.U(24.W), responseByte),
        Cat(Fill(24, responseByte(7)), responseByte)
      ),
      1.U -> Mux(
        savedDecoded.memoryUnsigned,
        Cat(0.U(16.W), responseHalf),
        Cat(Fill(16, responseHalf(15)), responseHalf)
      )
    )
  )
  val dataResponseResult     = Mux(
    savedDecoded.atomic =/= AtomicOperation.None,
    dcache.io.response.bits.data,
    responseLoadData
  )
  val dataCompletion         = executeState === eDataCacheWait && dcache.io.response.valid &&
    !dcache.io.response.bits.error
  val dataCompletionWrites   = dataCompletion && savedDecoded.writeRd && savedDecoded.rd.orR
  val mulDivCompletionWrites = mulDivCompletion && savedDecoded.rd.orR

  def captureOperand(index: UInt): UInt =
    Mux(
      !index.orR,
      0.U,
      Mux(
        simpleAluWrites && savedDecoded.rd === index,
        aluResult,
        Mux(
          dataCompletionWrites && savedDecoded.rd === index,
          dataResponseResult,
          Mux(
            mulDivCompletionWrites && savedDecoded.rd === index,
            mulDiv.io.response.bits,
            gpr(index)
          )
        )
      )
    )

  // Architectural instruction capture. Faults are carried independently for
  // both halfwords and take priority over decode legality.
  ibuf.io.instruction.ready := (
    executeState === eIdle || sequentialExecuteCompletion ||
      dataCompletion || mulDivCompletion
  ) && !halted && !csr.io.interruptValid
  when(ibuf.io.instruction.fire) {
    savedPc          := ibuf.io.instruction.bits.pc
    savedRaw         := ibuf.io.instruction.bits.raw
    savedRvc         := ibuf.io.instruction.bits.rvc
    savedIbufIllegal := ibuf.io.instruction.bits.illegal
    savedPageFault   := ibuf.io.instruction.bits.pageFault0 ||
      ibuf.io.instruction.bits.pageFault1
    savedAccessFault := ibuf.io.instruction.bits.accessFault0 ||
      ibuf.io.instruction.bits.accessFault1
    savedDecoded     := decoder.io.decoded
    savedRs1         := captureOperand(decoder.io.decoded.rs1)
    savedRs2         := captureOperand(decoder.io.decoded.rs2)
    executeState     := eExecute
  }

  csrAccess.valid     := executeState === eExecute && savedDecoded.csr
  csrAccess.addr      := savedRaw(31, 20)
  csrAccess.command   := savedDecoded.csrCommand
  csrAccess.writeData := Mux(savedDecoded.csrImmediate, savedDecoded.rs1, savedRs1)
  val csrChangesFetchEnvironment = savedDecoded.csrCommand =/= CsrCommand.None &&
    csrAccess.addr === CsrAddress.Satp.U
  ret := Mux(
    executeState === eExecute &&
      savedDecoded.system === SystemOperation.Mret,
    1.U,
    Mux(
      executeState === eExecute &&
        savedDecoded.system === SystemOperation.Sret,
      2.U,
      0.U
    )
  )

  mulDiv.io.request.valid    := executeState === eExecute &&
    savedDecoded.mulDiv
  mulDiv.io.request.bits.fn  := savedDecoded.mulDivFunction
  mulDiv.io.request.bits.lhs := savedRs1
  mulDiv.io.request.bits.rhs := savedRs2
  mulDiv.io.response.ready   := executeState === eMulDivWait

  val memoryAddress         = savedRs1 + savedDecoded.immediate
  val memoryMisaligned      =
    MuxLookup(savedDecoded.memorySize, false.B)(Seq(1.U -> memoryAddress(0), 2.U -> memoryAddress(1, 0).orR))
  val isStoreLike           = savedDecoded.memoryWrite &&
    savedDecoded.atomic =/= AtomicOperation.Lr
  val requestedMemoryAccess = Mux(isStoreLike, MemoryAccess.Store, MemoryAccess.Load)

  dtlb.io.request.valid       := executeState === eDataTlbRequest
  dtlb.io.request.bits.vaddr  := savedVirtualAddress
  dtlb.io.request.bits.size   := savedDecoded.memorySize
  dtlb.io.request.bits.access := savedMemoryAccess
  dtlb.io.request.bits.priv   := savedEffectivePrivilege
  dtlb.io.request.bits.sum    := sum
  dtlb.io.request.bits.mxr    := mxr
  dtlb.io.request.bits.satp   := csr.io.state.satp
  dtlb.io.response.ready      := executeState === eDataTlbWait
  dtlb.io.kill                := false.B

  val byteOffset = savedVirtualAddress(1, 0)
  val baseMask   = MuxLookup(savedDecoded.memorySize, 1.U(4.W))(Seq(1.U -> 3.U(4.W), 2.U -> 15.U(4.W)))
  val storeMask  = (baseMask << byteOffset)(3, 0)
  val storeData  = (savedRs2 << (byteOffset << 3))(31, 0)

  clint.io.access.valid := executeState === eDataAccess && clint.io.hit
  clint.io.access.addr  := savedPhysicalAddress
  clint.io.access.size  := savedDecoded.memorySize
  clint.io.access.write := savedDecoded.memoryWrite
  clint.io.access.data  := storeData
  clint.io.access.mask  := storeMask

  // D$ request ownership is shared by the architectural LSU and PTW.
  val dataOwnerNone = 0.U(2.W)
  val dataOwnerCore = 1.U(2.W)
  val dataOwnerPtw  = 2.U(2.W)
  val dataOwner     = RegInit(dataOwnerNone)
  val ptwWantsData  = ptw.io.memoryRequest.valid && dataOwner === dataOwnerNone
  val coreWantsData = executeState === eDataAccess &&
    !clint.io.hit &&
    !(savedDecoded.atomic =/= AtomicOperation.None &&
      !cacheable(savedPhysicalAddress))

  dcache.io.request.valid         := dataOwner === dataOwnerNone &&
    (ptwWantsData || (!ptwWantsData && coreWantsData))
  dcache.io.request.bits.addr     := Mux(ptwWantsData, ptw.io.memoryRequest.bits.addr, savedPhysicalAddress)
  dcache.io.request.bits.write    := Mux(ptwWantsData, false.B, savedDecoded.memoryWrite)
  dcache.io.request.bits.data     := Mux(ptwWantsData, 0.U, storeData)
  dcache.io.request.bits.mask     := Mux(ptwWantsData, 0.U, storeMask)
  dcache.io.request.bits.size     := Mux(ptwWantsData, 2.U, savedDecoded.memorySize)
  dcache.io.request.bits.uncached := !cacheable(Mux(ptwWantsData, ptw.io.memoryRequest.bits.addr, savedPhysicalAddress))
  dcache.io.request.bits.atomic   := Mux(ptwWantsData, AtomicOperation.None, savedDecoded.atomic)
  dcache.io.invalidate            := false.B
  dcache.io.flush.get             := executeState === eFenceWait
  dcache.io.probeRequest.get <> io.dataProbeRequest
  io.dataProbeResponse <> dcache.io.probeResponse.get
  dcache.io.probeAck.get <> io.dataProbeAck

  ptw.io.memoryRequest.ready := dataOwner === dataOwnerNone && dcache.io.request.ready
  when(ptw.io.memoryRequest.fire) {
    dataOwner := dataOwnerPtw
  }
  when(dcache.io.request.fire && !ptwWantsData) {
    dataOwner    := dataOwnerCore
    executeState := eDataCacheWait
  }

  ptw.io.memoryResponse.valid      := dataOwner === dataOwnerPtw && dcache.io.response.valid
  ptw.io.memoryResponse.bits.data  := dcache.io.response.bits.data
  ptw.io.memoryResponse.bits.error := dcache.io.response.bits.error
  dcache.io.response.ready         := Mux(
    dataOwner === dataOwnerPtw,
    ptw.io.memoryResponse.ready,
    dataOwner === dataOwnerCore && executeState === eDataCacheWait
  )
  when(ptw.io.memoryResponse.fire) {
    dataOwner := dataOwnerNone
  }

  when(executeState === eExecute) {
    when(savedPageFault) {
      raiseTrap(12.U, savedPc)
      executeState := eIdle
    }.elsewhen(savedAccessFault) {
      raiseTrap(1.U, savedPc)
      executeState := eIdle
    }.elsewhen(savedIbufIllegal || savedDecoded.illegal) {
      raiseTrap(2.U, Mux(savedRvc, savedRaw & "hffff".U, savedRaw))
      executeState := eIdle
    }.elsewhen(savedDecoded.system === SystemOperation.Ecall) {
      val cause = MuxLookup(currentPrivilege, 11.U)(Seq(Privilege.U -> 8.U, Privilege.S -> 9.U, Privilege.M -> 11.U))
      raiseTrap(cause, 0.U)
      executeState := eIdle
    }.elsewhen(savedDecoded.system === SystemOperation.Ebreak) {
      halted       := true.B
      complete(sequentialPc, true.B)
      executeState := eIdle
    }.elsewhen(
      savedDecoded.system === SystemOperation.Mret ||
        savedDecoded.system === SystemOperation.Sret
    ) {
      when(csr.io.retIllegal) {
        raiseTrap(2.U, Mux(savedRvc, savedRaw & "hffff".U, savedRaw))
      }.otherwise {
        complete(csr.io.retTarget, true.B)
        redirect(csr.io.retTarget)
      }
      executeState := eIdle
    }.elsewhen(savedDecoded.system === SystemOperation.Sfence) {
      when(
        currentPrivilege === Privilege.U ||
          (currentPrivilege === Privilege.S && mstatus(20))
      ) {
        raiseTrap(2.U, savedRaw)
      }.otherwise {
        sfencePulse       := true.B
        sfence.useAddress := savedDecoded.rs1.orR
        sfence.useAsid    := savedDecoded.rs2.orR
        sfence.vaddr      := savedRs1
        sfence.asid       := savedRs2(8, 0)
        complete(sequentialPc, true.B)
        redirect(sequentialPc)
      }
      executeState := eIdle
    }.elsewhen(savedDecoded.system === SystemOperation.FenceI) {
      executeState := eFenceWait
    }.elsewhen(
      savedDecoded.system === SystemOperation.Fence ||
        savedDecoded.system === SystemOperation.Wfi
    ) {
      complete(sequentialPc, true.B)
      executeState := eIdle
    }.elsewhen(savedDecoded.csr) {
      when(csr.io.accessIllegal) {
        raiseTrap(2.U, Mux(savedRvc, savedRaw & "hffff".U, savedRaw))
      }.otherwise {
        when(savedDecoded.writeRd && savedDecoded.rd.orR) {
          gpr(savedDecoded.rd) := csr.io.readData
        }
        complete(sequentialPc, true.B)
        when(csrChangesFetchEnvironment) { redirect(sequentialPc) }
      }
      executeState := eIdle
    }.elsewhen(savedDecoded.mulDiv) {
      when(mulDiv.io.request.fire) { executeState := eMulDivWait }
    }.elsewhen(savedDecoded.memory) {
      when(memoryMisaligned) {
        raiseTrap(Mux(isStoreLike, 6.U, 4.U), memoryAddress)
        executeState := eIdle
      }.otherwise {
        savedVirtualAddress     := memoryAddress
        savedMemoryAccess       := requestedMemoryAccess
        savedEffectivePrivilege := dataPrivilege
        when(dataTranslationEnabled) {
          executeState := eDataTlbRequest
        }.otherwise {
          savedPhysicalAddress := memoryAddress
          executeState         := eDataAccess
        }
      }
    }.otherwise {
      val takenTarget  = savedPc + savedDecoded.immediate
      val jumpTarget   = Mux(savedDecoded.jalr, (savedRs1 + savedDecoded.immediate) & "hfffffffe".U, takenTarget)
      val controlTaken = savedDecoded.jal || savedDecoded.jalr ||
        (savedDecoded.branch =/= BranchOperation.None && branchTaken)
      val nextPc       = Mux(controlTaken, jumpTarget, sequentialPc)
      val writeback    = Mux(savedDecoded.jal || savedDecoded.jalr, sequentialPc, aluResult)
      when(savedDecoded.writeRd && savedDecoded.rd.orR) {
        gpr(savedDecoded.rd) := writeback
      }
      complete(nextPc, true.B)
      when(controlTaken) { redirect(nextPc) }
      executeState := Mux(sequentialExecuteCompletion && ibuf.io.instruction.fire, eExecute, eIdle)
    }
  }

  when(executeState === eFenceWait && dcache.io.flushDone.get) {
    assert(!dcache.io.flushError.get, "D-cache writeback failed while ordering fence.i")
    instructionInvalidate := true.B
    complete(sequentialPc, true.B)
    redirect(sequentialPc)
    executeState          := eIdle
  }

  when(executeState === eMulDivWait && mulDiv.io.response.fire) {
    when(savedDecoded.rd.orR) { gpr(savedDecoded.rd) := mulDiv.io.response.bits }
    complete(sequentialPc, true.B)
    executeState := Mux(ibuf.io.instruction.fire, eExecute, eIdle)
  }

  when(executeState === eDataTlbRequest && dtlb.io.request.fire) {
    executeState := eDataTlbWait
  }
  when(executeState === eDataTlbWait && dtlb.io.response.fire) {
    savedPhysicalAddress := dtlb.io.response.bits.paddr
    when(dtlb.io.response.bits.pageFault) {
      raiseTrap(Mux(savedMemoryAccess === MemoryAccess.Store, 15.U, 13.U), savedVirtualAddress)
      executeState := eIdle
    }.elsewhen(dtlb.io.response.bits.accessFault) {
      raiseTrap(Mux(savedMemoryAccess === MemoryAccess.Store, 7.U, 5.U), savedVirtualAddress)
      executeState := eIdle
    }.otherwise {
      executeState := eDataAccess
    }
  }
  when(executeState === eDataAccess) {
    when(
      savedDecoded.atomic =/= AtomicOperation.None &&
        !cacheable(savedPhysicalAddress)
    ) {
      raiseTrap(Mux(savedMemoryAccess === MemoryAccess.Store, 7.U, 5.U), savedVirtualAddress)
      executeState := eIdle
    }.elsewhen(clint.io.hit) {
      when(
        !clint.io.legal ||
          savedDecoded.atomic =/= AtomicOperation.None
      ) {
        raiseTrap(Mux(savedMemoryAccess === MemoryAccess.Store, 7.U, 5.U), savedVirtualAddress)
      }.otherwise {
        when(!savedDecoded.memoryWrite && savedDecoded.rd.orR) {
          gpr(savedDecoded.rd) := clint.io.readData
        }
        complete(sequentialPc, true.B)
      }
      executeState := eIdle
    }
  }
  when(
    executeState === eDataCacheWait && dataOwner === dataOwnerCore &&
      dcache.io.response.fire
  ) {
    dataOwner := dataOwnerNone
    when(dcache.io.response.bits.error) {
      raiseTrap(Mux(savedMemoryAccess === MemoryAccess.Store, 7.U, 5.U), savedVirtualAddress)
      executeState := eIdle
    }.otherwise {
      when(savedDecoded.writeRd && savedDecoded.rd.orR) {
        gpr(savedDecoded.rd) := dataResponseResult
      }
      complete(sequentialPc, true.B)
      executeState := Mux(ibuf.io.instruction.fire, eExecute, eIdle)
    }
  }

  // Interrupts are accepted only at an architectural boundary. They are
  // reported separately from instruction commits so DiffTest can preserve
  // ARCH_STEP then ASYNC_INTR ordering.
  interruptValid := false.B
  when(executeState === eIdle && csr.io.interruptValid && !halted) {
    trap.valid      := true.B
    trap.cause      := csr.io.interruptCause
    trap.epc        := architecturalPc
    trap.tval       := 0.U
    redirect(csr.io.trapTarget)
    interruptValid  := true.B
    interruptCause  := csr.io.interruptCause
    interruptEpc    := architecturalPc
    interruptTarget := csr.io.trapTarget
  }

  commitValid := completePulse
  when(completePulse) {
    commitPc                := savedPc
    commitInstruction       := Mux(savedRvc, savedRaw & "hffff".U, savedRaw)
    commitInstructionLength := Mux(savedRvc, 2.U, 4.U)
    commitInstructionValid  := !(savedPageFault || savedAccessFault)
    commitNextPc            := completeNextPc
    architecturalPc         := completeNextPc
  }
  when(redirectPulse) {
    fetchPc         := redirectTarget
    architecturalPc := redirectTarget
    when(
      (fetchState === fCacheWait && !icache.io.response.fire) ||
        (fetchState === fCacheRequest && icache.io.request.fire)
    ) {
      // The blocking I$ has no cancellation input. Drain an accepted request
      // before issuing the redirected fetch so its response cannot leave the
      // cache stuck in the response state.
      fetchDiscard := true.B
      fetchState   := fCacheWait
    }.otherwise {
      fetchDiscard := false.B
      fetchState   := fIdle
    }
  }
  when(reset.asBool) {
    fetchPc         := io.resetVector
    architecturalPc := io.resetVector
    fetchState      := fIdle
    executeState    := eIdle
    ptwBusy         := false.B
    dataOwner       := dataOwnerNone
    fetchDiscard    := false.B
    commitValid     := false.B
    interruptValid  := false.B
    halted          := false.B
  }
  gpr(0)      := 0.U

  io.instructionReadAddress.valid := icache.io.readAddress.valid
  io.instructionReadAddress.bits  := icache.io.readAddress.bits
  icache.io.readAddress.ready     := io.instructionReadAddress.ready
  icache.io.readData.valid        := io.instructionReadData.valid
  icache.io.readData.bits         := io.instructionReadData.bits
  io.instructionReadData.ready    := icache.io.readData.ready

  io.dataReadAddress.valid    := dcache.io.readAddress.valid
  io.dataReadAddress.bits     := dcache.io.readAddress.bits
  dcache.io.readAddress.ready := io.dataReadAddress.ready
  dcache.io.readData.valid    := io.dataReadData.valid
  dcache.io.readData.bits     := io.dataReadData.bits
  io.dataReadData.ready       := dcache.io.readData.ready

  io.dataWriteAddress.valid         := dcache.io.writeAddress.get.valid
  io.dataWriteAddress.bits          := dcache.io.writeAddress.get.bits
  dcache.io.writeAddress.get.ready  := io.dataWriteAddress.ready
  io.dataWriteData.valid            := dcache.io.writeData.get.valid
  io.dataWriteData.bits             := dcache.io.writeData.get.bits
  dcache.io.writeData.get.ready     := io.dataWriteData.ready
  dcache.io.writeResponse.get.valid := io.dataWriteResponse.valid
  dcache.io.writeResponse.get.bits  := io.dataWriteResponse.bits
  io.dataWriteResponse.ready        := dcache.io.writeResponse.get.ready

  io.commit.valid               := commitValid
  io.commit.pc                  := commitPc
  io.commit.instruction         := commitInstruction
  io.commit.instructionLength   := commitInstructionLength
  io.commit.instructionValid    := commitInstructionValid
  io.commit.nextPc              := commitNextPc
  io.commit.gpr                 := gpr
  io.commit.csr                 := csr.io.state
  io.asyncInterrupt.valid       := interruptValid
  io.asyncInterrupt.bits.cause  := interruptCause
  io.asyncInterrupt.bits.epc    := interruptEpc
  io.asyncInterrupt.bits.target := interruptTarget
  io.halted                     := halted
}
