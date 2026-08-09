// See ../LICENSE.SiFive and ../LICENSE.Berkeley for license details.
package npc.rocketmed

import chisel3._
import chisel3.util.log2Ceil

class SinglePortSram(depth: Int, width: Int, masked: Boolean, moduleName: String) extends Module {
  require(depth > 1 && (depth & (depth - 1)) == 0, "SRAM depth must be a power of two")
  require(width > 0)
  require(!masked || width % 8 == 0, "masked SRAM width must contain whole bytes")

  override def desiredName: String = moduleName

  private val maskWidth = math.max(1, (width + 7) / 8)
  val io                = IO(new Bundle {
    val enable    = Input(Bool())
    val write     = Input(Bool())
    val address   = Input(UInt(log2Ceil(depth).W))
    val writeData = Input(UInt(width.W))
    val writeMask = Input(UInt(maskWidth.W))
    val readData  = Output(UInt(width.W))
  })

  if (masked) {
    val lanes  = width / 8
    val memory = SyncReadMem(depth, Vec(lanes, UInt(8.W)))
    io.readData := memory
      .readWrite(
        io.address,
        io.writeData.asTypeOf(Vec(lanes, UInt(8.W))),
        io.writeMask(lanes - 1, 0).asBools,
        io.enable,
        io.write
      )
      .asUInt
  } else {
    val memory = SyncReadMem(depth, UInt(width.W))
    io.readData := memory.readWrite(io.address, io.writeData, io.enable, io.write)
  }
}
