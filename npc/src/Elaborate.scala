import chisel3.RawModule
import npc.rocketmed.{
  BlockingCache,
  Clint,
  CsrFile,
  InstructionBuffer,
  InstructionDecoder,
  IterativeDivider,
  IterativeMultiplier,
  MemSys,
  PageTableWalker,
  RocketChip,
  RocketCore,
  RvcExpander,
  Tlb
}

object Elaborate extends App {
  val firtoolOptions = Array(
    "--lowering-options=" + List(
      // make yosys happy
      // see https://github.com/llvm/circt/blob/main/docs/VerilogGeneration.md
      "disallowLocalVariables",
      "disallowPackedArrays",
      "locationInfoStyle=wrapInAtSquareBracket"
    ).reduce(_ + "," + _)
  )
  val selected: (Function0[RawModule], Array[String]) = args.headOption match {
    case Some("multiplier") => (() => new IterativeMultiplier, args.drop(1))
    case Some("divider")    => (() => new IterativeDivider, args.drop(1))
    case Some("rvc")        => (() => new RvcExpander, args.drop(1))
    case Some("ibuf")       => (() => new InstructionBuffer, args.drop(1))
    case Some("csr")        => (() => new CsrFile, args.drop(1))
    case Some("tlb")        => (() => new Tlb, args.drop(1))
    case Some("ptw")        => (() => new PageTableWalker, args.drop(1))
    case Some("icache")     => (() => new BlockingCache(instruction = true), args.drop(1))
    case Some("dcache")     => (() => new BlockingCache(instruction = false), args.drop(1))
    case Some("decode")     => (() => new InstructionDecoder, args.drop(1))
    case Some("core")       => (() => new RocketCore, args.drop(1))
    case Some("clint")      => (() => new Clint, args.drop(1))
    case Some("memsys")     => (() => new MemSys, args.drop(1))
    case Some("chip")       => (() => new RocketChip, args.drop(1))
    case Some(other)        =>
      throw new IllegalArgumentException(s"unknown elaboration target: $other")
    case None               =>
      throw new IllegalArgumentException("missing elaboration target")
  }
  val (generator, stageArgs) = selected
  circt.stage.ChiselStage.emitSystemVerilogFile(generator(), stageArgs, firtoolOptions)
}
