// Derived from the fixed Rocket Med parameter set resolved from rocket-chip
// revision 55bcad0f59436de98ea510334121de8546b9e9d7.
package npc.rocketmed

object RocketMed {
  final val XLen              = 32
  final val HartCount         = 1
  final val ResetPcStandalone = BigInt("80000000", 16)
  final val ResetPcYsyxSoc    = BigInt("30000000", 16)

  final val CacheSets      = 64
  final val CacheWays      = 1
  final val CacheLineBytes = 64
  final val RowBits        = 32
  final val RefillBeats    = 16
  final val ICacheLatency  = 2
  final val FetchBytes     = 4
  final val TlbSets        = 1
  final val TlbWays        = 4
  final val PmpRegions     = 8

  final val MulUnroll = 8
  final val DivUnroll = 1

  require(XLen == 32)
  require(CacheWays == 1)
  require(CacheLineBytes * 8 / RowBits == RefillBeats)
  require(TlbSets == 1 && TlbWays == 4)
  require(MulUnroll == 8 && 32 % MulUnroll == 0)
  require(DivUnroll == 1)
}
