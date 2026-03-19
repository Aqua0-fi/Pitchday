"use client"

import { useState, useRef, useEffect } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { Activity, X, Info, ShieldCheck, Flame, TrendingDown, TrendingUp, Minus, Loader2, CheckCircle2, Radio } from 'lucide-react'
import { TRANCHES_HOOK, TRANCHES_POOL_KEY } from '@/lib/contracts'

// IL formula matching contract: IL = (a-b)² / (a² + b²) * 10000 (bips)
function calculateILBips(priceInitial: number, priceCurrent: number): number {
  const a = Math.sqrt(priceInitial)
  const b = Math.sqrt(priceCurrent)
  if (a === 0 || b === 0) return 0
  const diff = a - b
  const numerator = diff * diff * 10000
  const denominator = a * a + b * b
  return Math.round(numerator / denominator)
}

type Scenario = {
  label: string
  tag: string
  priceChange: number
  apyBips: bigint
  color: string
  bgColor: string
  borderColor: string
  icon: typeof TrendingUp
}

const SCENARIOS: Scenario[] = [
  {
    label: 'Low Volatility',
    tag: '~2%',
    priceChange: 1.02,
    apyBips: 300n, // 3%
    color: 'text-emerald-400',
    bgColor: 'bg-emerald-500/5',
    borderColor: 'border-emerald-500/20',
    icon: Minus,
  },
  {
    label: 'Medium Volatility',
    tag: '~10%',
    priceChange: 1.10,
    apyBips: 500n, // 5%
    color: 'text-amber-400',
    bgColor: 'bg-amber-500/5',
    borderColor: 'border-amber-500/20',
    icon: TrendingUp,
  },
  {
    label: 'High Volatility',
    tag: '~25%',
    priceChange: 1.25,
    apyBips: 1000n, // 10%
    color: 'text-red-400',
    bgColor: 'bg-red-500/5',
    borderColor: 'border-red-500/20',
    icon: TrendingDown,
  },
]

const ADJUST_RISK_ABI = [{
  name: 'adjustRiskParameter',
  type: 'function',
  stateMutability: 'nonpayable',
  inputs: [
    { name: 'key', type: 'tuple', components: [
      { name: 'currency0', type: 'address' },
      { name: 'currency1', type: 'address' },
      { name: 'fee', type: 'uint24' },
      { name: 'tickSpacing', type: 'int24' },
      { name: 'hooks', type: 'address' },
    ]},
    { name: 'newSeniorTargetAPY', type: 'uint256' },
  ],
  outputs: [],
}] as const

const SIM = {
  liquidity: 1000,
  dailyVolume: 500,
  feeBips: 30,
  hookFeeBips: 500,
  seniorAPYBips: 500,
  ilReserveBips: 1000,
  maxILBips: 2000,
  days: 30,
}

function simulateScenario(scenario: Scenario, currentPrice: number) {
  const { liquidity, dailyVolume, feeBips, hookFeeBips, days, seniorAPYBips, ilReserveBips } = SIM

  const totalSwapFees = dailyVolume * days * (feeBips / 10000)
  const hookFees = totalSwapFees * (hookFeeBips / 10000)

  const seniorShare = liquidity * 0.5
  const juniorShare = liquidity * 0.5
  const seniorTarget = seniorShare * (seniorAPYBips / 10000) * (days / 365)
  const seniorFees = Math.min(hookFees * 0.6, seniorTarget)
  const juniorFeesGross = hookFees - seniorFees

  const ilBips = calculateILBips(1.0, scenario.priceChange)
  const ilAmount = (ilBips / 10000) * liquidity * 0.5

  const ilReserve = juniorFeesGross * (ilReserveBips / 10000)
  const juniorFees = juniorFeesGross - ilReserve

  const seniorILComp = Math.min(ilAmount * 0.5, ilReserve)

  const seniorNet = seniorFees + seniorILComp
  const seniorAPY = (seniorNet / seniorShare) * (365 / days) * 100
  const juniorNet = juniorFees - ilAmount
  const juniorAPY = (juniorNet / juniorShare) * (365 / days) * 100

  return {
    ilBips,
    ilAmount: ilAmount.toFixed(2),
    seniorFees: seniorFees.toFixed(2),
    seniorILComp: seniorILComp.toFixed(2),
    seniorNet: seniorNet.toFixed(2),
    seniorAPY: seniorAPY.toFixed(1),
    juniorFees: juniorFees.toFixed(2),
    juniorIL: ilAmount.toFixed(2),
    juniorNet: juniorNet.toFixed(2),
    juniorAPY: juniorAPY.toFixed(1),
    ilReserve: ilReserve.toFixed(2),
    newPrice: (currentPrice * scenario.priceChange).toFixed(currentPrice >= 100 ? 0 : 4),
  }
}

export function RSCOracleSimulator({ currentPrice }: { currentPrice: number }) {
  const [isOpen, setIsOpen] = useState(false)
  const [showTooltip, setShowTooltip] = useState(false)
  const [appliedRegime, setAppliedRegime] = useState<string | null>(null)
  const modalRef = useRef<HTMLDivElement>(null)

  const { writeContract, data: txHash, isPending: isSending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  const applyRegime = (scenario: Scenario) => {
    setAppliedRegime(scenario.label)
    writeContract({
      address: TRANCHES_HOOK as `0x${string}`,
      abi: ADJUST_RISK_ABI,
      functionName: 'adjustRiskParameter',
      args: [
        {
          currency0: TRANCHES_POOL_KEY.currency0,
          currency1: TRANCHES_POOL_KEY.currency1,
          fee: TRANCHES_POOL_KEY.fee,
          tickSpacing: TRANCHES_POOL_KEY.tickSpacing,
          hooks: TRANCHES_POOL_KEY.hooks,
        },
        scenario.apyBips,
      ],
    })
  }

  useEffect(() => {
    if (isSuccess) {
      setTimeout(() => setAppliedRegime(null), 3000)
    }
  }, [isSuccess])

  // Close modal on Escape
  useEffect(() => {
    if (!isOpen) return
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false)
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [isOpen])

  // Close modal on backdrop click
  const handleBackdropClick = (e: React.MouseEvent) => {
    if (modalRef.current && !modalRef.current.contains(e.target as Node)) {
      setIsOpen(false)
    }
  }

  return (
    <>
      {/* Small button with info icon inside */}
      <div className="relative inline-flex items-center">
        <button
          onClick={() => setIsOpen(true)}
          className="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg border border-violet-500/30 bg-violet-500/10 hover:bg-violet-500/20 hover:border-violet-500/50 transition-all text-sm"
        >
          <Activity className="h-3.5 w-3.5 text-violet-400" />
          <span className="text-violet-300 font-medium">Reactive Oracle</span>
          <span className="text-white font-semibold tabular-nums">{currentPrice.toPrecision(5)}</span>
          <div
            className="relative"
            onMouseEnter={(e) => { e.stopPropagation(); setShowTooltip(true) }}
            onMouseLeave={() => setShowTooltip(false)}
            onClick={(e) => e.stopPropagation()}
          >
            <Info className="h-3.5 w-3.5 text-violet-400/60 hover:text-violet-400 transition-colors cursor-help" />
            {showTooltip && (
              <div className="absolute left-1/2 -translate-x-1/2 bottom-full mb-2 w-64 p-3 rounded-lg bg-zinc-900 border border-violet-500/30 shadow-xl shadow-black/40 z-50 animate-in fade-in duration-150">
                <p className="text-xs text-zinc-300 leading-relaxed">
                  <span className="text-violet-400 font-medium">Reactive Smart Contract (RSC)</span> — Deployed on Reactive Network, it listens to Uniswap V4 Swap events across Ethereum, Base, and Unichain. Computes an equal-weighted average price across all chains and tracks realized volatility via EMA. When volatility shifts regime (Low/Med/High), it sends a cross-chain callback to adjust the Senior tranche target APY automatically.
                </p>
                <div className="absolute left-1/2 -translate-x-1/2 top-full w-2 h-2 bg-zinc-900 border-r border-b border-violet-500/30 rotate-45 -mt-1" />
              </div>
            )}
          </div>
        </button>
      </div>

      {/* Modal overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm animate-in fade-in duration-150"
          onClick={handleBackdropClick}
        >
          <div
            ref={modalRef}
            className="relative w-full max-w-4xl mx-4 rounded-2xl border border-violet-500/30 bg-zinc-950 shadow-2xl shadow-violet-500/5 animate-in zoom-in-95 duration-200"
          >
            {/* Modal header */}
            <div className="flex items-center justify-between p-5 border-b border-border/20">
              <div className="flex items-center gap-3">
                <div className="flex items-center justify-center w-8 h-8 rounded-full bg-violet-500/20">
                  <Activity className="h-4 w-4 text-violet-400" />
                </div>
                <div>
                  <h2 className="text-base font-bold">Reactive Oracle</h2>
                  <p className="text-xs text-muted-foreground">
                    Cross-chain volatility monitor &middot; Click a scenario to adjust Senior APY on-chain
                  </p>
                </div>
              </div>
              <button
                onClick={() => setIsOpen(false)}
                className="p-1.5 rounded-lg hover:bg-zinc-800 transition-colors"
              >
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>

            {/* Scenarios grid */}
            <div className="p-5 grid grid-cols-1 md:grid-cols-3 gap-4">
              {SCENARIOS.map((scenario) => {
                const sim = simulateScenario(scenario, currentPrice)
                const ScenarioIcon = scenario.icon

                return (
                  <div
                    key={scenario.label}
                    className={`rounded-xl border ${scenario.borderColor} ${scenario.bgColor} p-5 space-y-4`}
                  >
                    {/* Scenario Header */}
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <ScenarioIcon className={`h-4 w-4 ${scenario.color}`} />
                        <span className={`font-bold text-sm ${scenario.color}`}>{scenario.label}</span>
                      </div>
                      <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full ${scenario.bgColor} ${scenario.color}`}>
                        {scenario.tag}
                      </span>
                    </div>

                    {/* Price + IL */}
                    <div className="space-y-1">
                      <div className="flex justify-between text-xs">
                        <span className="text-muted-foreground">Price</span>
                        <span className="tabular-nums">{currentPrice >= 100 ? currentPrice.toFixed(0) : currentPrice.toFixed(4)} &rarr; {sim.newPrice}</span>
                      </div>
                      <div className="flex justify-between text-xs">
                        <span className="text-muted-foreground">Impermanent Loss</span>
                        <span className={`tabular-nums ${sim.ilBips > 0 ? 'text-red-400' : ''}`}>
                          {(sim.ilBips / 100).toFixed(2)}%
                        </span>
                      </div>
                    </div>

                    <div className="border-t border-border/20 pt-3 space-y-3">
                      {/* Senior outcome */}
                      <div className="space-y-1.5">
                        <div className="flex items-center gap-1.5">
                          <ShieldCheck className="h-3.5 w-3.5 text-blue-400" />
                          <span className="text-xs font-semibold text-blue-400">Senior</span>
                        </div>
                        <div className="space-y-0.5 pl-5">
                          <div className="flex justify-between text-[11px]">
                            <span className="text-muted-foreground">Fees earned</span>
                            <span className="tabular-nums text-blue-300">+{sim.seniorFees}</span>
                          </div>
                          {parseFloat(sim.seniorILComp) > 0 && (
                            <div className="flex justify-between text-[11px]">
                              <span className="text-muted-foreground">IL compensation</span>
                              <span className="tabular-nums text-emerald-400">+{sim.seniorILComp}</span>
                            </div>
                          )}
                          <div className="flex justify-between text-xs font-bold pt-0.5">
                            <span>Net</span>
                            <span className="text-blue-300">{sim.seniorNet} ({sim.seniorAPY}% APY)</span>
                          </div>
                        </div>
                      </div>

                      {/* Junior outcome */}
                      <div className="space-y-1.5">
                        <div className="flex items-center gap-1.5">
                          <Flame className="h-3.5 w-3.5 text-orange-400" />
                          <span className="text-xs font-semibold text-orange-400">Junior</span>
                        </div>
                        <div className="space-y-0.5 pl-5">
                          <div className="flex justify-between text-[11px]">
                            <span className="text-muted-foreground">Fees earned</span>
                            <span className="tabular-nums text-orange-300">+{sim.juniorFees}</span>
                          </div>
                          {parseFloat(sim.juniorIL) > 0 && (
                            <div className="flex justify-between text-[11px]">
                              <span className="text-muted-foreground">IL absorbed</span>
                              <span className="tabular-nums text-red-400">-{sim.juniorIL}</span>
                            </div>
                          )}
                          <div className="flex justify-between text-xs font-bold pt-0.5">
                            <span>Net</span>
                            <span className={parseFloat(sim.juniorNet) >= 0 ? 'text-orange-300' : 'text-red-400'}>
                              {sim.juniorNet} ({sim.juniorAPY}% APY)
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* IL Reserve info */}
                    <div className="border-t border-border/20 pt-2">
                      <div className="flex justify-between text-[10px] text-muted-foreground/60">
                        <span>IL Reserve funded</span>
                        <span className="tabular-nums">{sim.ilReserve}</span>
                      </div>
                    </div>

                    {/* Apply Regime button — calls adjustRiskParameter on-chain */}
                    <button
                      onClick={() => applyRegime(scenario)}
                      disabled={isSending || isConfirming}
                      className={`w-full flex items-center justify-center gap-2 rounded-lg border ${scenario.borderColor} px-3 py-2 text-xs font-semibold transition-all hover:bg-white/5 disabled:opacity-50 ${scenario.color}`}
                    >
                      {appliedRegime === scenario.label && (isSending || isConfirming) ? (
                        <>
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          {isSending ? 'Signing...' : 'Confirming...'}
                        </>
                      ) : appliedRegime === scenario.label && isSuccess ? (
                        <>
                          <CheckCircle2 className="h-3.5 w-3.5" />
                          APY Updated!
                        </>
                      ) : (
                        <>
                          <Radio className="h-3.5 w-3.5" />
                          Apply {(Number(scenario.apyBips) / 100).toFixed(0)}% APY On-Chain
                        </>
                      )}
                    </button>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
