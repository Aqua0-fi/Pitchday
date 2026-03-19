"use client"

import { useState } from 'react'
import { formatUnits, parseUnits } from 'viem'
import { useReadContracts } from 'wagmi'
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useWallet } from '@/contexts/wallet-context'
import { useTranchesStats } from '@/hooks/use-tranches-stats'
import { useTranchesPoolLiquidity } from '@/hooks/use-tranches-pool-liquidity'
import { useTranchesPosition } from '@/hooks/use-tranches-position'
import { useTranchesDeposit } from '@/hooks/use-tranches-deposit'
import { useTranchesClaim } from '@/hooks/use-tranches-claim'
import { useTranchesRemove } from '@/hooks/use-tranches-remove'
import { TRANCHES_POOL_KEY, TRANCHES_SHARED_POOL, ERC20_ABI } from '@/lib/contracts'
import {
  ShieldCheck,
  Flame,
  ArrowDownToLine,
  ArrowUpFromLine,
  Coins,
  Loader2,
  CheckCircle2,
  AlertCircle,
  Shield,
  Zap,
  Wallet,
  Info,
} from 'lucide-react'

function fmt(val: bigint, decimals = 18, dp = 4): string {
  const str = formatUnits(val, decimals)
  const num = parseFloat(str)
  if (num === 0) return '0'
  if (num < 0.0001) return '<0.0001'
  return num.toLocaleString(undefined, { maximumFractionDigits: dp })
}

function bipsToPercent(bips: bigint): string {
  return (Number(bips) / 100).toFixed(2)
}

// ─── Token Balance Hook ────────────────────────────────────────────────────

function useTokenBalances(address: string | undefined) {
  const { data, isLoading } = useReadContracts({
    contracts: address ? [
      {
        address: TRANCHES_POOL_KEY.currency0,
        abi: ERC20_ABI,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
      },
      {
        address: TRANCHES_POOL_KEY.currency1,
        abi: ERC20_ABI,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
      },
    ] : [],
    query: { enabled: !!address, refetchInterval: 10_000 },
  })

  return {
    balance0: (data?.[0]?.result as bigint) ?? 0n,
    balance1: (data?.[1]?.result as bigint) ?? 0n,
    isLoading,
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function liquidityShare(trancheLiquidity: bigint, totalLiquidity: bigint, poolBalance: bigint): bigint {
  if (totalLiquidity === 0n) return 0n
  return trancheLiquidity * poolBalance / totalLiquidity
}

// ─── Stats Section ──────────────────────────────────────────────────────────

export function TrancheStats() {
  const { stats, isLoading } = useTranchesStats()
  // Read real token balances from our SharedLiquidityPool
  const { balance0: poolMUSDC, balance1: poolMWETH, isLoading: balLoading } = useTokenBalances(TRANCHES_SHARED_POOL)

  if (isLoading || balLoading) {
    return (
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
        {[1, 2, 3, 4, 5, 6].map(i => (
          <div key={i} className="h-20 rounded-xl border border-border/50 bg-secondary/20 animate-pulse" />
        ))}
      </div>
    )
  }

  if (!stats) return null

  const totalLiq = stats.totalSenior + stats.totalJunior
  const seniorPct = totalLiq > 0n ? Number(stats.totalSenior * 10000n / totalLiq) / 100 : 0

  // Distribute real pool balances proportionally by tranche liquidity
  const seniorMWETH = liquidityShare(stats.totalSenior, totalLiq, poolMWETH)
  const seniorMUSDC = liquidityShare(stats.totalSenior, totalLiq, poolMUSDC)
  const juniorMWETH = liquidityShare(stats.totalJunior, totalLiq, poolMWETH)
  const juniorMUSDC = liquidityShare(stats.totalJunior, totalLiq, poolMUSDC)

  return (
    <div className="space-y-4">
      {/* Tranche Split — pie chart + legends */}
      <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
        <p className="text-sm font-semibold mb-4">Tranche Split</p>
        <div className="flex flex-col items-center gap-6 md:flex-row md:justify-around">
          <div className="h-52 w-52">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={[
                    { name: 'Senior', value: Number(formatUnits(seniorMWETH, 18)) || 0.001 },
                    { name: 'Junior', value: Number(formatUnits(juniorMWETH, 18)) || 0.001 },
                  ]}
                  cx="50%"
                  cy="50%"
                  innerRadius={50}
                  outerRadius={80}
                  paddingAngle={4}
                  dataKey="value"
                  strokeWidth={0}
                >
                  <Cell fill="#3b82f6" />
                  <Cell fill="#f97316" />
                </Pie>
                <Tooltip
                  contentStyle={{
                    backgroundColor: '#1a1a2e',
                    border: '1px solid rgba(255,255,255,0.1)',
                    borderRadius: '8px',
                    color: '#fff',
                    fontSize: '12px',
                    padding: '8px 12px',
                  }}
                  itemStyle={{ color: '#fff' }}
                  labelStyle={{ color: '#999' }}
                  formatter={(value: number) => [value.toFixed(4) + ' mWETH', '']}
                />
              </PieChart>
            </ResponsiveContainer>
          </div>

          <div className="flex flex-col gap-3">
            <div className="flex items-center gap-3 rounded-xl border border-border/50 bg-secondary/20 px-4 py-3 min-w-[220px]">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-500/10">
                <Shield className="h-4 w-4 text-blue-400" />
              </div>
              <div className="flex-1">
                <p className="text-[10px] text-muted-foreground">Senior Liquidity</p>
                <p className="text-sm font-bold">{fmt(seniorMWETH)} <span className="text-xs font-normal text-muted-foreground">mWETH</span></p>
                <p className="text-[10px] text-muted-foreground">{fmt(seniorMUSDC)} mUSDC</p>
              </div>
              <span className="text-xs font-bold text-blue-400">{seniorPct.toFixed(1)}%</span>
            </div>

            <div className="flex items-center gap-3 rounded-xl border border-border/50 bg-secondary/20 px-4 py-3 min-w-[220px]">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-orange-500/10">
                <Zap className="h-4 w-4 text-orange-400" />
              </div>
              <div className="flex-1">
                <p className="text-[10px] text-muted-foreground">Junior Liquidity</p>
                <p className="text-sm font-bold">{fmt(juniorMWETH)} <span className="text-xs font-normal text-muted-foreground">mWETH</span></p>
                <p className="text-[10px] text-muted-foreground">{fmt(juniorMUSDC)} mUSDC</p>
              </div>
              <span className="text-xs font-bold text-orange-400">{(100 - seniorPct).toFixed(1)}%</span>
            </div>
          </div>
        </div>
      </div>

      {/* Stats grid */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <div className="group relative rounded-xl border border-border/50 bg-secondary/20 p-4">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Senior Target APY</p>
          <p className="mt-1 text-xl font-bold text-emerald-400">{bipsToPercent(stats.seniorAPY)}%</p>
          <div className="pointer-events-none absolute -top-10 left-1/2 -translate-x-1/2 rounded-lg bg-[#1a1a2e] border border-white/10 px-3 py-1.5 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap z-10">
            The guaranteed annual yield for Senior LPs. Fees are distributed to Senior first until this target is met.
          </div>
        </div>
        <div className="group relative rounded-xl border border-border/50 bg-secondary/20 p-4">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Senior Ratio</p>
          <div className="mt-1 flex items-end gap-2">
            <p className="text-xl font-bold">{seniorPct.toFixed(1)}%</p>
            <div className="flex-1 h-2 rounded-full bg-secondary overflow-hidden mb-1">
              <div className="h-full bg-blue-500 rounded-full transition-all" style={{ width: `${seniorPct}%` }} />
            </div>
          </div>
          <div className="pointer-events-none absolute -top-10 left-1/2 -translate-x-1/2 rounded-lg bg-[#1a1a2e] border border-white/10 px-3 py-1.5 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap z-10">
            Percentage of total pool liquidity allocated to the Senior tranche.
          </div>
        </div>
        <div className="group relative rounded-xl border border-border/50 bg-secondary/20 p-4">
          <p className="text-[10px] uppercase tracking-wider text-blue-400/60">Senior Fees</p>
          <p className="mt-1 text-xl font-bold">{fmt(stats.seniorFees)}</p>
          <div className="pointer-events-none absolute -top-10 left-1/2 -translate-x-1/2 rounded-lg bg-[#1a1a2e] border border-white/10 px-3 py-1.5 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap z-10">
            Total swap fees distributed to Senior LPs so far.
          </div>
        </div>
        <div className="group relative rounded-xl border border-border/50 bg-secondary/20 p-4">
          <p className="text-[10px] uppercase tracking-wider text-orange-400/60">Junior Fees</p>
          <p className="mt-1 text-xl font-bold">{fmt(stats.juniorFees)}</p>
          <div className="pointer-events-none absolute -top-10 left-1/2 -translate-x-1/2 rounded-lg bg-[#1a1a2e] border border-white/10 px-3 py-1.5 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap z-10">
            Surplus fees after Senior target is met. Junior gets all remaining swap fees.
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Deposit Section ────────────────────────────────────────────────────────

export function TrancheDeposit({ poolPrice = 2000 }: { poolPrice?: number }) {
  const { address } = useWallet()
  const [selectedTranche, setSelectedTranche] = useState<0 | 1>(0)
  const [amount0, setAmount0] = useState('')
  const [amount1, setAmount1] = useState('')
  const [lastEdited, setLastEdited] = useState<'amount0' | 'amount1' | null>(null)
  const deposit = useTranchesDeposit()
  const { balance0, balance1 } = useTokenBalances(address ?? undefined)

  // currency0 = mUSDC (lower address), currency1 = mWETH (higher address)
  const handleAmount0Change = (val: string) => {
    setAmount0(val)
    setLastEdited('amount0')
    const num = parseFloat(val)
    if (!isNaN(num) && num > 0 && poolPrice > 0) {
      // mUSDC entered → derive mWETH (divide by price)
      setAmount1((num / poolPrice).toFixed(6))
    } else {
      setAmount1('')
    }
  }

  const handleAmount1Change = (val: string) => {
    setAmount1(val)
    setLastEdited('amount1')
    const num = parseFloat(val)
    if (!isNaN(num) && num > 0 && poolPrice > 0) {
      // mWETH entered → derive mUSDC (multiply by price)
      setAmount0((num * poolPrice).toFixed(2))
    } else {
      setAmount0('')
    }
  }

  const handleDeposit = () => {
    if ((!amount0 || parseFloat(amount0) <= 0) && (!amount1 || parseFloat(amount1) <= 0)) return
    deposit.execute({
      tranche: selectedTranche,
      amount0: amount0 || '0',
      amount1: amount1 || '0',
    })
  }

  const isProcessing = deposit.step !== 'idle' && deposit.step !== 'done' && deposit.step !== 'error'

  const stepLabel: Record<string, string> = {
    idle: '',
    approving0: 'Approving mUSDC...',
    approving1: 'Approving mWETH...',
    depositing: 'Depositing into tranche...',
    confirming: 'Confirming transaction...',
    done: 'Deposit successful!',
    error: deposit.error || 'Error',
  }

  return (
    <div className="space-y-4">
      {/* Tranche selector */}
      <div className="grid grid-cols-2 gap-3">
        <button
          onClick={() => setSelectedTranche(0)}
          className={`rounded-xl border-2 p-4 text-left transition-all ${
            selectedTranche === 0
              ? 'border-blue-500 bg-blue-500/10'
              : 'border-border/50 bg-secondary/20 hover:border-blue-500/30'
          }`}
        >
          <div className="flex items-center gap-2 mb-1">
            <ShieldCheck className="h-4 w-4 text-blue-400" />
            <span className="font-bold text-blue-400">Senior</span>
            <div className="relative ml-auto" onClick={(e) => e.stopPropagation()}>
              <Info className="h-3.5 w-3.5 text-blue-400/50 hover:text-blue-400 transition-colors cursor-help peer" />
              <div className="absolute right-0 bottom-full mb-2 w-56 p-3 rounded-lg bg-zinc-900 border border-blue-500/30 shadow-xl z-50 opacity-0 pointer-events-none peer-hover:opacity-100 transition-opacity duration-150">
                <p className="text-[11px] text-zinc-300 leading-relaxed">
                  <span className="text-blue-400 font-medium">Senior tranche</span> gets paid first from swap fees up to a target APY. Any impermanent loss is compensated from the IL reserve funded by Junior. Ideal for conservative LPs who want predictable yield.
                </p>
              </div>
            </div>
          </div>
          <p className="text-xs text-muted-foreground">Priority fees, IL protection, lower risk</p>
        </button>
        <button
          onClick={() => setSelectedTranche(1)}
          className={`rounded-xl border-2 p-4 text-left transition-all ${
            selectedTranche === 1
              ? 'border-orange-500 bg-orange-500/10'
              : 'border-border/50 bg-secondary/20 hover:border-orange-500/30'
          }`}
        >
          <div className="flex items-center gap-2 mb-1">
            <Flame className="h-4 w-4 text-orange-400" />
            <span className="font-bold text-orange-400">Junior</span>
            <div className="relative ml-auto" onClick={(e) => e.stopPropagation()}>
              <Info className="h-3.5 w-3.5 text-orange-400/50 hover:text-orange-400 transition-colors cursor-help peer" />
              <div className="absolute right-0 bottom-full mb-2 w-56 p-3 rounded-lg bg-zinc-900 border border-orange-500/30 shadow-xl z-50 opacity-0 pointer-events-none peer-hover:opacity-100 transition-opacity duration-150">
                <p className="text-[11px] text-zinc-300 leading-relaxed">
                  <span className="text-orange-400 font-medium">Junior tranche</span> earns all remaining fees after Senior is paid, plus absorbs impermanent loss. A portion of Junior fees funds the IL reserve. Higher risk but potentially much higher returns in low-volatility conditions.
                </p>
              </div>
            </div>
          </div>
          <p className="text-xs text-muted-foreground">Higher yield, absorbs IL, higher risk</p>
        </button>
      </div>

      {/* Amount inputs */}
      <div className="space-y-3">
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <label className="text-xs uppercase tracking-wider text-muted-foreground">mUSDC Amount</label>
            <button
              onClick={() => handleAmount0Change(formatUnits(balance0, 18))}
              className="flex items-center gap-1 text-[10px] text-muted-foreground hover:text-foreground transition-colors"
            >
              <Wallet className="h-3 w-3" />
              {fmt(balance0, 18, 2)}
            </button>
          </div>
          <Input
            type="number"
            placeholder="0.0"
            value={amount0}
            onChange={(e) => handleAmount0Change(e.target.value)}
            className="text-lg"
            disabled={isProcessing}
          />
        </div>
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <label className="text-xs uppercase tracking-wider text-muted-foreground">mWETH Amount</label>
            <button
              onClick={() => handleAmount1Change(formatUnits(balance1, 18))}
              className="flex items-center gap-1 text-[10px] text-muted-foreground hover:text-foreground transition-colors"
            >
              <Wallet className="h-3 w-3" />
              {fmt(balance1, 18, 2)}
            </button>
          </div>
          <Input
            type="number"
            placeholder="0.0"
            value={amount1}
            onChange={(e) => handleAmount1Change(e.target.value)}
            className="text-lg"
            disabled={isProcessing}
          />
        </div>
      </div>

      {/* Action button */}
      {deposit.step === 'done' ? (
        <Button onClick={() => { deposit.reset(); setAmount0(''); setAmount1('') }} variant="outline" className="w-full gap-2">
          <CheckCircle2 className="h-4 w-4 text-emerald-400" />
          Deposit Successful — Deposit More
        </Button>
      ) : deposit.step === 'error' ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-sm text-red-400">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span className="truncate">{deposit.error}</span>
          </div>
          <Button onClick={deposit.reset} variant="outline" className="w-full">
            Try Again
          </Button>
        </div>
      ) : (
        <Button
          onClick={handleDeposit}
          disabled={
            ((!amount0 || parseFloat(amount0) <= 0) && (!amount1 || parseFloat(amount1) <= 0))
            || isProcessing
          }
          className="w-full gap-2 bg-red-600 hover:bg-red-700"
        >
          {isProcessing && <Loader2 className="h-4 w-4 animate-spin" />}
          {deposit.step === 'idle'
            ? `Deposit into ${selectedTranche === 0 ? 'Senior' : 'Junior'}`
            : stepLabel[deposit.step]}
        </Button>
      )}
    </div>
  )
}

// ─── Position Section ───────────────────────────────────────────────────────

export function TranchePosition() {
  const { position, hasPosition, isLoading } = useTranchesPosition()
  const { stats } = useTranchesStats()
  const { balance0: poolMUSDC, balance1: poolMWETH } = useTokenBalances(TRANCHES_SHARED_POOL)
  const claim = useTranchesClaim()
  const remove = useTranchesRemove()

  if (isLoading) {
    return <div className="h-32 rounded-xl border border-border/50 bg-secondary/20 animate-pulse" />
  }

  if (!hasPosition || !position) {
    return (
      <div className="rounded-xl border border-dashed border-border/50 p-6 text-center">
        <p className="text-muted-foreground">No active position. Deposit above to get started.</p>
      </div>
    )
  }

  const isSenior = position.tranche === 0
  const trancheLabel = isSenior ? 'Senior' : 'Junior'
  const TrancheIcon = isSenior ? ShieldCheck : Flame

  const hasPending = position.pendingFees.token0 > 0n || position.pendingFees.token1 > 0n
  const hasClaimable = position.claimable.token0 > 0n || position.claimable.token1 > 0n

  const claimStepLabel: Record<string, string> = {
    idle: 'Claim & Withdraw Fees',
    claiming: 'Claiming fees...',
    withdrawing0: 'Withdrawing mUSDC...',
    withdrawing1: 'Withdrawing mWETH...',

    confirming: 'Confirming...',
    done: 'Fees withdrawn!',
    error: claim.error || 'Error',
  }

  const removeStepLabel: Record<string, string> = {
    idle: 'Remove Liquidity',
    removing: 'Removing position...',
    confirming: 'Confirming...',
    done: 'Liquidity removed!',
    error: remove.error || 'Error',
  }

  const handleRemove = () => {
    // Use position amount as both initial amounts (1:1 pool)
    remove.execute({
      amount0Initial: position.amount,
      amount1Initial: position.amount,
    })
  }

  return (
    <div className={`rounded-xl border ${isSenior ? 'border-blue-500/20 bg-blue-500/5' : 'border-orange-500/20 bg-orange-500/5'} p-5 space-y-4`}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <TrancheIcon className={`h-5 w-5 ${isSenior ? 'text-blue-400' : 'text-orange-400'}`} />
          <span className={`font-bold ${isSenior ? 'text-blue-400' : 'text-orange-400'}`}>{trancheLabel} Position</span>
          {isSenior && (
            <span className="flex items-center gap-1 text-[10px] rounded-full bg-emerald-500/10 px-2 py-0.5 text-emerald-400">
              <Shield className="h-3 w-3" />
              IL Protected
            </span>
          )}
        </div>
        <span className="text-xs text-muted-foreground">Block #{position.depositBlock.toString()}</span>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-3">
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Your Liquidity</p>
          {(() => {
            const totalLiq = (stats?.totalSenior ?? 0n) + (stats?.totalJunior ?? 0n)
            const myMWETH = liquidityShare(position.amount, totalLiq, poolMWETH)
            const myMUSDC = liquidityShare(position.amount, totalLiq, poolMUSDC)
            return (
              <div className="text-sm font-medium space-y-0.5">
                <p className="text-lg font-bold">{fmt(myMWETH)} <span className="text-xs font-normal text-muted-foreground">mWETH</span></p>
                <p className="text-xs text-muted-foreground">{fmt(myMUSDC)} mUSDC</p>
              </div>
            )
          })()}
        </div>
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Pending Fees</p>
          <div className="text-sm font-medium space-y-0.5">
            <p>{fmt(position.pendingFees.token0)} mUSDC</p>
            <p>{fmt(position.pendingFees.token1)} mWETH</p>

          </div>
        </div>
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Claimable</p>
          <div className="text-sm font-medium space-y-0.5">
            <p>{fmt(position.claimable.token0)} mUSDC</p>
            <p>{fmt(position.claimable.token1)} mWETH</p>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        {/* Claim button */}
        {(hasPending || hasClaimable) && (
          claim.step === 'done' ? (
            <Button onClick={claim.reset} variant="outline" size="sm" className="flex-1 gap-2">
              <CheckCircle2 className="h-4 w-4 text-emerald-400" />
              Fees Withdrawn!
            </Button>
          ) : claim.step === 'error' ? (
            <Button onClick={claim.reset} variant="outline" size="sm" className="flex-1 gap-2 text-red-400">
              <AlertCircle className="h-4 w-4" />
              Retry Claim
            </Button>
          ) : (
            <Button
              onClick={claim.execute}
              disabled={claim.step !== 'idle'}
              size="sm"
              variant="outline"
              className="flex-1 gap-2"
            >
              {claim.step !== 'idle' && <Loader2 className="h-4 w-4 animate-spin" />}
              <Coins className="h-4 w-4" />
              {claimStepLabel[claim.step]}
            </Button>
          )
        )}

        {/* Remove button */}
        {remove.step === 'done' ? (
          <Button onClick={remove.reset} variant="outline" size="sm" className="flex-1 gap-2">
            <CheckCircle2 className="h-4 w-4 text-emerald-400" />
            Removed!
          </Button>
        ) : remove.step === 'error' ? (
          <Button onClick={remove.reset} variant="outline" size="sm" className="flex-1 gap-2 text-red-400">
            <AlertCircle className="h-4 w-4" />
            Retry Remove
          </Button>
        ) : (
          <Button
            onClick={handleRemove}
            disabled={remove.step !== 'idle'}
            size="sm"
            variant="outline"
            className="flex-1 gap-2 text-red-400 hover:text-red-300 hover:border-red-500/30"
          >
            {remove.step !== 'idle' && <Loader2 className="h-4 w-4 animate-spin" />}
            <ArrowUpFromLine className="h-4 w-4" />
            {removeStepLabel[remove.step]}
          </Button>
        )}
      </div>
    </div>
  )
}

// ─── Main Panel ─────────────────────────────────────────────────────────────

export function TranchesPanel() {
  const { isConnected } = useWallet()

  return (
    <div className="space-y-6">
      {/* Section header */}
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-1.5 rounded-full bg-violet-500/10 px-3 py-1.5">
          <span className="text-sm font-bold text-violet-400">TrancheFi</span>
        </div>
        <h2 className="text-xl font-bold">Senior / Junior Tranches</h2>
      </div>

      {/* Info */}
      <div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4 text-sm text-blue-300/80">
        <strong className="text-blue-300">How it works:</strong> Fees are distributed via a waterfall — Senior tranche gets paid first up to its target APY, plus IL protection from the reserve. Junior absorbs impermanent loss but earns all remaining fees.
      </div>

      {/* Stats (always visible) */}
      <TrancheStats />

      {/* Deposit + Position (wallet required) */}
      {isConnected ? (
        <>
          <div className="border-t border-border/30 pt-6">
            <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
              <ArrowDownToLine className="h-5 w-5" />
              Deposit into Tranche
            </h3>
            <TrancheDeposit />
          </div>

          <div className="border-t border-border/30 pt-6">
            <h3 className="text-lg font-semibold mb-4">Your Position</h3>
            <TranchePosition />
          </div>
        </>
      ) : (
        <div className="rounded-xl border border-dashed border-border/50 p-8 text-center">
          <p className="text-muted-foreground">Connect your wallet to deposit and manage your tranche position.</p>
        </div>
      )}
    </div>
  )
}
