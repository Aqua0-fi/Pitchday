"use client"

import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { TokenIcon } from '@/components/token-icon'
import { useWallet } from '@/contexts/wallet-context'
import { useSharedBalances } from '@/hooks/use-shared-balances'
import { useQuery } from '@tanstack/react-query'
import { V4Pool } from '@/lib/v4-api'
import { useToast } from '@/hooks/use-toast'
import { useWriteContract, usePublicClient, useReadContracts } from 'wagmi'
import { formatUnits, parseUnits } from 'viem'
import { ERC20_ABI, TRANCHES_SHARED_POOL, TRANCHES_POOLS } from '@/lib/contracts'
import { ArrowDownToLine, ArrowUpFromLine, RefreshCw } from 'lucide-react'

const AQUA_POOLS = TRANCHES_POOLS.filter(p => p.aqua)

// Token addresses for poolId computation
const MUSDC = '0x73c56ddD816e356387Caf740c804bb9D379BE47E'
const MWETH = '0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad'

// 1 mWETH = 2000 mUSDC
const ETH_PRICE_USD = 2000

// ABI to read user position from TranchesHook
const HOOK_POSITION_ABI = [
  {
    name: 'positions',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'positionKey', type: 'bytes32' }],
    outputs: [
      { name: 'tranche', type: 'uint8' },
      { name: 'amount', type: 'uint256' },
      { name: 'depositBlock', type: 'uint256' },
      { name: 'rewardDebt0', type: 'uint256' },
      { name: 'rewardDebt1', type: 'uint256' },
      { name: 'depositSqrtPriceX96', type: 'uint160' },
    ],
  },
] as const

const SHARED_POOL_ABI = [
  {
    name: 'deposit',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'to', type: 'address' },
    ],
    outputs: [],
  },
  {
    name: 'withdraw',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
    ],
    outputs: [],
  },
] as const

interface RealLiquidityManagerProps {
    pools: V4Pool[]
}

export function RealLiquidityManager({ pools }: RealLiquidityManagerProps) {
    const { isConnected, address, chainId } = useWallet()
    const { toast } = useToast()
    const { writeContractAsync } = useWriteContract()
    const publicClient = usePublicClient()

    // Extract unique tokens from pools
    const tokensMap = new Map<string, { address: string; symbol: string; decimals: number; logo: string }>()
    pools.forEach(p => {
        const getLogo = (symbol: string) => {
            const clean = symbol.replace(/^m/, '')
            if (clean === 'WBTC') return '/crypto/BTC.png'
            if (clean === 'WETH') return '/crypto/ETH.png'
            return `/crypto/${clean}.png`
        }
        if (!tokensMap.has(p.token0.address.toLowerCase())) {
            tokensMap.set(p.token0.address.toLowerCase(), { ...p.token0, logo: getLogo(p.token0.symbol) })
        }
        if (!tokensMap.has(p.token1.address.toLowerCase())) {
            tokensMap.set(p.token1.address.toLowerCase(), { ...p.token1, logo: getLogo(p.token1.symbol) })
        }
    })
    const uniqueTokens = Array.from(tokensMap.values())
    const tokenAddresses = uniqueTokens.map(t => t.address)

    const { data: balances, isLoading, refetch } = useSharedBalances(chainId, address || undefined, tokenAddresses)

    // Read user positions from each Aqua pool (per-pool breakdown, no auto-amplification)
    const { data: poolPositions } = useQuery({
        queryKey: ['aqua-positions', address],
        queryFn: async () => {
            if (!address || !publicClient) return []

            const positions: { poolName: string; amount: bigint; hook: string }[] = []

            for (const pool of AQUA_POOLS) {
                const { encodePacked, keccak256, encodeAbiParameters } = await import('viem')
                const poolId = keccak256(encodeAbiParameters(
                    [{ type: 'address' }, { type: 'address' }, { type: 'uint24' }, { type: 'int24' }, { type: 'address' }],
                    [MUSDC as `0x${string}`, MWETH as `0x${string}`, pool.fee, pool.tickSpacing, pool.hook]
                ))
                const posKey = keccak256(encodePacked(['address', 'bytes32'], [address as `0x${string}`, poolId]))

                const result = await publicClient.readContract({
                    address: pool.hook,
                    abi: HOOK_POSITION_ABI,
                    functionName: 'positions',
                    args: [posKey],
                }) as any

                const amount = result[1] as bigint
                if (amount > 0n) {
                    positions.push({ poolName: pool.label, amount, hook: pool.hook })
                }
            }

            return positions
        },
        enabled: !!address && !!publicClient,
        refetchInterval: 15000,
    })

    const activePositions = poolPositions ?? []

    // Modal state
    const [actionDialog, setActionDialog] = useState<{ isOpen: boolean; type: 'deposit' | 'withdraw'; tokenAddress: string } | null>(null)
    const [amount, setAmount] = useState('')
    const [isSubmitting, setIsSubmitting] = useState(false)
    const [needsApproval, setNeedsApproval] = useState(false)
    const [approvalDone, setApprovalDone] = useState(false)

    const activeToken = uniqueTokens.find(t => actionDialog?.tokenAddress && t.address.toLowerCase() === actionDialog.tokenAddress.toLowerCase())
    const activeBalance = balances?.find(b => actionDialog?.tokenAddress && b.token.toLowerCase() === actionDialog.tokenAddress.toLowerCase())

    const handleMax = () => {
        if (!activeBalance || !activeToken) return
        const val = actionDialog?.type === 'deposit' ? activeBalance.walletBalance : activeBalance.freeBalance
        setAmount(formatUnits(BigInt(val), activeToken.decimals))
    }

    const [depositStep, setDepositStep] = useState<'idle' | 'approving' | 'depositing'>('idle')

    // Auto-check allowance when amount changes or dialog opens
    useEffect(() => {
        if (!activeToken || !address || !publicClient || !amount || parseFloat(amount) <= 0 || actionDialog?.type !== 'deposit') {
            setNeedsApproval(false)
            return
        }
        let cancelled = false
        const check = async () => {
            try {
                const amountParsed = parseUnits(amount, activeToken.decimals)
                const allowance = await publicClient.readContract({
                    address: activeToken.address as `0x${string}`,
                    abi: ERC20_ABI,
                    functionName: 'allowance',
                    args: [address as `0x${string}`, TRANCHES_SHARED_POOL],
                }) as bigint
                if (!cancelled) {
                    setNeedsApproval(allowance < amountParsed)
                }
            } catch { if (!cancelled) setNeedsApproval(false) }
        }
        check()
        return () => { cancelled = true }
    }, [amount, activeToken?.address, address, actionDialog?.type])

    // Single handler: approve (if needed) + deposit/withdraw — modal stays open
    const handleSubmit = async () => {
        if (!activeToken || !actionDialog || !amount || parseFloat(amount) <= 0 || !address) return

        setIsSubmitting(true)
        try {
            const amountParsed = parseUnits(amount, activeToken.decimals)

            if (actionDialog.type === 'deposit') {
                // Check allowance and approve if needed
                const allowance = await publicClient!.readContract({
                    address: activeToken.address as `0x${string}`,
                    abi: ERC20_ABI,
                    functionName: 'allowance',
                    args: [address as `0x${string}`, TRANCHES_SHARED_POOL],
                }) as bigint

                if (allowance < amountParsed) {
                    setDepositStep('approving')
                    toast({ title: `Step 1: Approving ${activeToken.symbol}...`, description: 'Confirm in wallet' })
                    const maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935n
                    const approveHash = await writeContractAsync({
                        address: activeToken.address as `0x${string}`,
                        abi: ERC20_ABI,
                        functionName: 'approve',
                        args: [TRANCHES_SHARED_POOL, maxUint],
                    })
                    await publicClient!.waitForTransactionReceipt({ hash: approveHash })
                    toast({ title: `Approved! Now depositing...` })
                }

                setDepositStep('depositing')
                toast({ title: `Step 2: Depositing ${activeToken.symbol}...`, description: 'Confirm in wallet' })
                const depositHash = await writeContractAsync({
                    address: TRANCHES_SHARED_POOL,
                    abi: SHARED_POOL_ABI,
                    functionName: 'deposit',
                    args: [activeToken.address as `0x${string}`, amountParsed, address as `0x${string}`],
                })
                await publicClient!.waitForTransactionReceipt({ hash: depositHash })
                toast({ title: "Deposit Successful!" })
            } else {
                toast({ title: `Withdrawing ${activeToken.symbol}...`, description: 'Confirm in wallet' })
                const withdrawHash = await writeContractAsync({
                    address: TRANCHES_SHARED_POOL,
                    abi: SHARED_POOL_ABI,
                    functionName: 'withdraw',
                    args: [activeToken.address as `0x${string}`, amountParsed, address as `0x${string}`, address as `0x${string}`],
                })
                await publicClient!.waitForTransactionReceipt({ hash: withdrawHash })
                toast({ title: "Withdrawal Successful!" })
            }

            setActionDialog(null)
            setAmount('')
            setDepositStep('idle')
            setNeedsApproval(false)
            setApprovalDone(false)
            refetch()
        } catch (error: any) {
            console.error(error)
            setDepositStep('idle')
            toast({ title: "Action Failed", description: error?.shortMessage || error.message || "Unknown error", variant: "destructive" })
        } finally {
            setIsSubmitting(false)
        }
    }

    if (!isConnected || uniqueTokens.length === 0) return null

    return (
        <Card className="mb-8">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle>Your Capital</CardTitle>
                <Button variant="ghost" size="icon" onClick={() => refetch()} disabled={isLoading} className="h-8 w-8">
                    <RefreshCw className={`h-4 w-4 text-muted-foreground ${isLoading ? 'animate-spin' : ''}`} />
                </Button>
            </CardHeader>
            <CardContent>
                <div className="space-y-4 pt-4">
                    {uniqueTokens.map(token => {
                        const bal = balances?.find(b => b.token.toLowerCase() === token.address.toLowerCase())
                        const freeBalanceRaw = BigInt(bal?.freeBalance || "0")
                        const depositedNum = Number(formatUnits(freeBalanceRaw, token.decimals))
                        const depositedFmt = depositedNum.toFixed(4)
                        const isETH = token.symbol.toLowerCase().includes('weth') || token.symbol.toLowerCase().includes('eth')
                        const usdValue = isETH ? depositedNum * ETH_PRICE_USD : depositedNum
                        const earnedFeesRaw = BigInt(bal?.earnedFees || "0")

                        return (
                            <div key={token.address} className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 p-4 rounded-xl border border-border/50 bg-secondary/10">
                                <div className="flex items-center gap-3">
                                    <TokenIcon token={token as any} size="md" />
                                    <div>
                                        <h4 className="font-semibold">{token.symbol}</h4>
                                        <div className="flex gap-4 mt-1 text-sm font-mono flex-wrap">
                                            <span className="text-muted-foreground">Deposited: {depositedFmt}</span>
                                            <span className="text-muted-foreground/60">~${usdValue.toLocaleString(undefined, { maximumFractionDigits: 2 })}</span>
                                            {earnedFeesRaw > 0n && (
                                                <span className="text-amber-500 font-medium">Fees: {Number(formatUnits(earnedFeesRaw, token.decimals)).toFixed(4)}</span>
                                            )}
                                        </div>
                                    </div>
                                </div>
                                <div className="flex gap-2 justify-end w-full sm:w-auto flex-wrap mt-3 sm:mt-0">
                                    <Button
                                        variant="outline"
                                        size="sm"
                                        className="flex-1 sm:flex-none border-emerald-500/20 bg-emerald-500/10 text-emerald-500 hover:bg-emerald-500/20 hover:text-emerald-400"
                                        onClick={() => setActionDialog({ isOpen: true, type: 'deposit', tokenAddress: token.address })}
                                    >
                                        <ArrowDownToLine className="mr-1 h-3.5 w-3.5" /> Deposit
                                    </Button>
                                    <Button
                                        variant="outline"
                                        size="sm"
                                        className="flex-1 sm:flex-none"
                                        onClick={() => setActionDialog({ isOpen: true, type: 'withdraw', tokenAddress: token.address })}
                                    >
                                        <ArrowUpFromLine className="mr-1 h-3.5 w-3.5" /> Withdraw
                                    </Button>
                                </div>
                            </div>
                        )
                    })}

                    {/* Active Pool Positions — only shown if user has amplified to pools */}
                    {activePositions.length > 0 && (
                        <div className="mt-4 rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4">
                            <h4 className="text-sm font-semibold text-emerald-400 mb-3">Amplified in {activePositions.length} pool{activePositions.length > 1 ? 's' : ''}</h4>
                            <div className="space-y-2">
                                {activePositions.map(pos => (
                                    <div key={pos.hook} className="flex items-center justify-between text-sm">
                                        <span className="text-muted-foreground">{pos.poolName}</span>
                                        <span className="font-mono">{Number(formatUnits(pos.amount, 18)).toFixed(4)} liquidity</span>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )}

                    {activePositions.length === 0 && (
                        <div className="mt-2 rounded-lg border border-dashed border-border/40 p-3 text-center">
                            <p className="text-xs text-muted-foreground">
                                Capital deposited but not yet amplified. Go to a pool to amplify your capital across strategies.
                            </p>
                        </div>
                    )}
                </div>
            </CardContent>

            <Dialog open={actionDialog?.isOpen} onOpenChange={(open) => !open && setActionDialog(null)}>
                <DialogContent className="sm:max-w-[400px]">
                    <DialogHeader>
                        <DialogTitle className="capitalize">{actionDialog?.type} {activeToken?.symbol}</DialogTitle>
                    </DialogHeader>

                    {activeToken && (
                        <div className="space-y-4 py-4">
                            <div className="flex justify-between items-center text-sm font-mono">
                                <span className="text-muted-foreground">Available to {actionDialog?.type}:</span>
                                <span>
                                    {Number(formatUnits(BigInt(actionDialog?.type === 'deposit' ? (activeBalance?.walletBalance || "0") : (activeBalance?.freeBalance || "0")), activeToken.decimals)).toFixed(4)} {activeToken.symbol}
                                </span>
                            </div>

                            <div className="relative">
                                <Input
                                    type="number"
                                    placeholder="0.00"
                                    value={amount}
                                    onChange={(e) => { setAmount(e.target.value); setApprovalDone(false) }}
                                    className="pr-16 text-lg font-mono"
                                    disabled={isSubmitting}
                                />
                                <Button
                                    type="button"
                                    variant="secondary"
                                    size="sm"
                                    className="absolute right-1 top-1/2 h-7 -translate-y-1/2 text-xs"
                                    onClick={handleMax}
                                    disabled={isSubmitting}
                                >
                                    MAX
                                </Button>
                            </div>

                            <Button onClick={handleSubmit} disabled={isSubmitting || !amount || parseFloat(amount) <= 0} className="w-full">
                                {isSubmitting
                                    ? (depositStep === 'approving' ? 'Approving...' : depositStep === 'depositing' ? 'Depositing...' : 'Processing...')
                                    : actionDialog?.type === 'deposit'
                                        ? (needsApproval ? 'Approve & Deposit' : 'Deposit')
                                        : 'Withdraw'}
                            </Button>
                            {actionDialog?.type === 'deposit' && needsApproval && !isSubmitting && (
                                <p className="text-xs text-center text-muted-foreground">Will ask for 2 signatures: approve + deposit</p>
                            )}
                        </div>
                    )}
                </DialogContent>
            </Dialog>
        </Card>
    )
}
