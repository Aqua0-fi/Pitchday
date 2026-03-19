"use client"

import { useState } from 'react'
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

    // Read user positions from each Aqua pool to compute virtual capital
    const { data: positionData } = useQuery({
        queryKey: ['aqua-positions', address],
        queryFn: async () => {
            if (!address || !publicClient) return { count: 0, totalLiquidity: 0n }

            let activeCount = 0
            let totalLiq = 0n

            for (const pool of AQUA_POOLS) {
                // Compute poolId = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks))
                const { encodePacked, keccak256, encodeAbiParameters } = await import('viem')
                const poolId = keccak256(encodeAbiParameters(
                    [{ type: 'address' }, { type: 'address' }, { type: 'uint24' }, { type: 'int24' }, { type: 'address' }],
                    [MUSDC as `0x${string}`, MWETH as `0x${string}`, pool.fee, pool.tickSpacing, pool.hook]
                ))
                // posKey = keccak256(encodePacked(user, poolId))
                const posKey = keccak256(encodePacked(['address', 'bytes32'], [address as `0x${string}`, poolId]))

                const result = await publicClient.readContract({
                    address: pool.hook,
                    abi: HOOK_POSITION_ABI,
                    functionName: 'positions',
                    args: [posKey],
                }) as any

                const amount = result[1] as bigint
                if (amount > 0n) {
                    activeCount++
                    totalLiq += amount
                }
            }

            return { count: activeCount, totalLiquidity: totalLiq }
        },
        enabled: !!address && !!publicClient,
        refetchInterval: 15000,
    })

    const activePoolCount = positionData?.count ?? 0

    // Modal state
    const [actionDialog, setActionDialog] = useState<{ isOpen: boolean; type: 'deposit' | 'withdraw'; tokenAddress: string } | null>(null)
    const [amount, setAmount] = useState('')
    const [isSubmitting, setIsSubmitting] = useState(false)

    const activeToken = uniqueTokens.find(t => actionDialog?.tokenAddress && t.address.toLowerCase() === actionDialog.tokenAddress.toLowerCase())
    const activeBalance = balances?.find(b => actionDialog?.tokenAddress && b.token.toLowerCase() === actionDialog.tokenAddress.toLowerCase())

    const handleMax = () => {
        if (!activeBalance || !activeToken) return
        const val = actionDialog?.type === 'deposit' ? activeBalance.walletBalance : activeBalance.freeBalance
        setAmount(formatUnits(BigInt(val), activeToken.decimals))
    }

    const handleSubmit = async () => {
        if (!activeToken || !actionDialog || !amount || parseFloat(amount) <= 0 || !address) return

        setIsSubmitting(true)
        try {
            const amountParsed = parseUnits(amount, activeToken.decimals)

            if (actionDialog.type === 'deposit') {
                // Step 1: Check allowance, approve if needed (use maxUint256 for infinite approval)
                const allowance = await publicClient!.readContract({
                    address: activeToken.address as `0x${string}`,
                    abi: ERC20_ABI,
                    functionName: 'allowance',
                    args: [address as `0x${string}`, TRANCHES_SHARED_POOL],
                }) as bigint

                if (allowance < amountParsed) {
                    toast({ title: `Approving ${activeToken.symbol}...`, description: 'Confirm in wallet' })
                    const maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935n
                    const approveHash = await writeContractAsync({
                        address: activeToken.address as `0x${string}`,
                        abi: ERC20_ABI,
                        functionName: 'approve',
                        args: [TRANCHES_SHARED_POOL, maxUint],
                    })
                    await publicClient!.waitForTransactionReceipt({ hash: approveHash })
                    // Small delay to let MetaMask sync nonce
                    await new Promise(r => setTimeout(r, 2000))
                }

                // Step 2: Deposit to SharedPool
                toast({ title: `Depositing ${activeToken.symbol}...`, description: 'Confirm in wallet' })
                const depositHash = await writeContractAsync({
                    address: TRANCHES_SHARED_POOL,
                    abi: SHARED_POOL_ABI,
                    functionName: 'deposit',
                    args: [activeToken.address as `0x${string}`, amountParsed, address as `0x${string}`],
                })
                await publicClient!.waitForTransactionReceipt({ hash: depositHash })

                toast({ title: "✅ Deposit Successful!" })
            } else {
                // Withdraw from SharedPool
                toast({ title: `Withdrawing ${activeToken.symbol}...`, description: 'Confirm in wallet' })
                const withdrawHash = await writeContractAsync({
                    address: TRANCHES_SHARED_POOL,
                    abi: SHARED_POOL_ABI,
                    functionName: 'withdraw',
                    args: [activeToken.address as `0x${string}`, amountParsed, address as `0x${string}`, address as `0x${string}`],
                })
                await publicClient!.waitForTransactionReceipt({ hash: withdrawHash })

                toast({ title: "✅ Withdrawal Successful!" })
            }

            setActionDialog(null)
            setAmount('')
            refetch()
        } catch (error: any) {
            console.error(error)
            toast({ title: "Action Failed", description: error?.shortMessage || error.message || "Unknown error", variant: "destructive" })
        } finally {
            setIsSubmitting(false)
        }
    }

    if (!isConnected || uniqueTokens.length === 0) return null

    return (
        <Card className="mb-8">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle>Real Liquidity (Shared Pool)</CardTitle>
                <Button variant="ghost" size="icon" onClick={() => refetch()} disabled={isLoading} className="h-8 w-8">
                    <RefreshCw className={`h-4 w-4 text-muted-foreground ${isLoading ? 'animate-spin' : ''}`} />
                </Button>
            </CardHeader>
            <CardContent>
                <div className="space-y-4 pt-4">
                    {uniqueTokens.map(token => {
                        const bal = balances?.find(b => b.token.toLowerCase() === token.address.toLowerCase())
                        const depositedFmt = bal ? Number(formatUnits(BigInt(bal.freeBalance), token.decimals)).toFixed(4) : "0.0000"
                        const amplifiedVal = bal && activePoolCount > 0 ? BigInt(bal.freeBalance) * BigInt(activePoolCount) : 0n
                        const sharedFmt = Number(formatUnits(amplifiedVal, token.decimals)).toFixed(4)

                        return (
                            <div key={token.address} className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 p-4 rounded-xl border border-border/50 bg-secondary/10">
                                <div className="flex items-center gap-3">
                                    <TokenIcon token={token as any} size="md" />
                                    <div>
                                        <h4 className="font-semibold">{token.symbol}</h4>
                                        <div className="flex gap-4 mt-1 text-sm font-mono flex-wrap">
                                            <span className="text-muted-foreground">Deposited: {depositedFmt}</span>
                                            <span className="text-emerald-500 font-medium">Virtual{activePoolCount > 0 ? ` (${activePoolCount}x)` : ''}: {sharedFmt}</span>
                                            {bal && BigInt(bal.earnedFees || "0") > 0n && (
                                                <span className="text-amber-500 font-medium">Fees: {Number(formatUnits(BigInt(bal.earnedFees), token.decimals)).toFixed(4)}</span>
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
                                    onChange={(e) => setAmount(e.target.value)}
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
                                {isSubmitting ? "Processing..." : `Confirm ${actionDialog?.type}`}
                            </Button>
                        </div>
                    )}
                </DialogContent>
            </Dialog>
        </Card>
    )
}
