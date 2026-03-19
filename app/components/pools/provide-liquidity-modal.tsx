"use client"

import { useState, useEffect } from 'react'
import {
    Dialog,
    DialogContent,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { TokenIcon, TokenPairIcon } from '@/components/token-icon'
import { type V4Pool, fetchUserPositions } from '@/lib/v4-api'
import { Loader2, ArrowUpRight } from 'lucide-react'
import { useWallet } from '@/contexts/wallet-context'
import { useToast } from '@/hooks/use-toast'
import { useBalance, useSendTransaction, useReadContract, usePublicClient } from 'wagmi'
import { formatUnits, parseUnits } from 'viem'
import { priceToTick, tickToPrice, formatPrice, getSqrtRatioAtTick, getLiquidityForAmounts, getAmountsForLiquidity } from '@/lib/utils/tick-math'
import { api } from '@/lib/api-client'
import { BACKEND_CHAIN_IDS } from '@/lib/contracts'

interface ProvideLiquidityModalProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    pool: V4Pool
}

export function ProvideLiquidityModal({
    open,
    onOpenChange,
    pool,
}: ProvideLiquidityModalProps) {
    const { isConnected, connect, address, chainId } = useWallet()
    const { toast } = useToast()
    const { sendTransactionAsync } = useSendTransaction()
    const publicClient = usePublicClient()
    const [isSubmitting, setIsSubmitting] = useState(false)

    const [amount0, setAmount0] = useState('')
    const [amount1, setAmount1] = useState('')

    // Modal Tab State
    const [activeTab, setActiveTab] = useState<'deposit' | 'positions'>('deposit')

    // Price / Tick State
    const currentPrice = tickToPrice(pool.currentTick, pool.token0.decimals, pool.token1.decimals)
    const [priceLower, setPriceLower] = useState(formatPrice(currentPrice * 0.9))
    const [priceUpper, setPriceUpper] = useState(formatPrice(currentPrice * 1.1))
    const [strategy, setStrategy] = useState<'custom' | 'stable' | 'wide' | 'lower' | 'upper'>('custom')

    const [positions, setPositions] = useState<any[]>([])
    const [isLoadingPositions, setIsLoadingPositions] = useState(false)

    const getLogo = (symbol: string) => {
        const cleanSymbol = symbol.replace(/^m/, '');
        if (cleanSymbol === 'WBTC') return '/crypto/BTC.png';
        return `/crypto/${cleanSymbol}.png`;
    };

    const token0 = { ...pool.token0, logo: getLogo(pool.token0.symbol) }
    const token1 = { ...pool.token1, logo: getLogo(pool.token1.symbol) }

    const isNative0 = pool.token0.address === '0x0000000000000000000000000000000000000000';
    const isNative1 = pool.token1.address === '0x0000000000000000000000000000000000000000';

    const { data: balance0Data } = useBalance({
        address: address as `0x${string}` | undefined,
        token: isNative0 ? undefined : pool.token0.address as `0x${string}`,
        query: { enabled: !!address, refetchInterval: 10000 }
    })

    const { data: balance1Data } = useBalance({
        address: address as `0x${string}` | undefined,
        token: isNative1 ? undefined : pool.token1.address as `0x${string}`,
        query: { enabled: !!address, refetchInterval: 10000 }
    })

    const balance0 = balance0Data ? Number(formatUnits(balance0Data.value, pool.token0.decimals)) : 0
    const balance1 = balance1Data ? Number(formatUnits(balance1Data.value, pool.token1.decimals)) : 0

    const [freeBalance0, setFreeBalance0] = useState<number>(0)
    const [freeBalance1, setFreeBalance1] = useState<number>(0)

    useEffect(() => {
        if (!address || !chainId || !open) return;
        const backendChainId = BACKEND_CHAIN_IDS[chainId] ?? 696969;
        api.get<{ balances: { token: string, freeBalance: string }[] }>(`v4/lp/balances/${address}?chainId=${backendChainId}&tokens=${token0.address},${token1.address}`)
            .then(res => {
                const f0 = res.balances.find((b: any) => b.token.toLowerCase() === token0.address.toLowerCase())?.freeBalance || "0";
                const f1 = res.balances.find((b: any) => b.token.toLowerCase() === token1.address.toLowerCase())?.freeBalance || "0";
                setFreeBalance0(Number(formatUnits(BigInt(f0), token0.decimals)));
                setFreeBalance1(Number(formatUnits(BigInt(f1), token1.decimals)));
            })
            .catch(console.error);
    }, [address, chainId, token0.address, token1.address, open, isSubmitting])

    const handleAmount0Change = (value: string) => setAmount0(value)
    const handleAmount1Change = (value: string) => setAmount1(value)

    const handleMax0 = () => handleAmount0Change(balance0.toString())
    const handleMax1 = () => handleAmount1Change(balance1.toString())

    // Apply Strategies
    const applyStrategy = (type: 'custom' | 'stable' | 'wide' | 'lower' | 'upper') => {
        setStrategy(type)
        if (type === 'custom') return

        const p = currentPrice
        let newLower = p
        let newUpper = p

        switch (type) {
            case 'stable':
                const stableLowerTick = pool.currentTick - (pool.tickSpacing * 3)
                const stableUpperTick = pool.currentTick + (pool.tickSpacing * 3)
                newLower = tickToPrice(stableLowerTick, token0.decimals, token1.decimals)
                newUpper = tickToPrice(stableUpperTick, token0.decimals, token1.decimals)
                break;
            case 'wide':
                newLower = p * 0.5
                newUpper = p * 2.0
                break;
            case 'lower':
                newLower = p * 0.5
                newUpper = p
                break;
            case 'upper':
                newLower = p
                newUpper = p * 2.0
                break;
        }

        setPriceLower(formatPrice(newLower))
        setPriceUpper(formatPrice(newUpper))
    }

    const handleSubmit = async () => {
        setIsSubmitting(true)
        try {
            const val0 = parseFloat(amount0) || 0;
            const val1 = parseFloat(amount1) || 0;
            if (val0 === 0 && val1 === 0) throw new Error("Enter amounts");

            const backendChainId = BACKEND_CHAIN_IDS[chainId!] ?? 696969;
            const amt0Raw = parseUnits(amount0 || '0', token0.decimals).toString();
            const amt1Raw = parseUnits(amount1 || '0', token1.decimals).toString();

            /** Helper: send tx, then wait for it to be mined */
            const sendAndWait = async (calldata: any, label: string) => {
                toast({ title: `${label}...`, description: 'Waiting for wallet confirmation' })
                const hash = await sendTransactionAsync({
                    to: calldata.to,
                    data: calldata.data,
                    value: calldata.value ? BigInt(calldata.value) : undefined
                })
                toast({ title: `${label} submitted`, description: 'Waiting for chain confirmation…' })
                await publicClient!.waitForTransactionReceipt({ hash })
            }

            // Fetch current free balances from the SharedLiquidityPool
            const { balances } = await api.get<{ balances: { token: string, freeBalance: string }[] }>(
                `v4/lp/balances/${address}?chainId=${backendChainId}&tokens=${token0.address},${token1.address}`
            );

            const free0 = BigInt(balances.find((b: any) => b.token.toLowerCase() === token0.address.toLowerCase())?.freeBalance || "0");
            const free1 = BigInt(balances.find((b: any) => b.token.toLowerCase() === token1.address.toLowerCase())?.freeBalance || "0");

            const req0 = BigInt(amt0Raw) > free0 ? BigInt(amt0Raw) - free0 : 0n;
            const req1 = BigInt(amt1Raw) > free1 ? BigInt(amt1Raw) - free1 : 0n;

            // 1. Approve & Deposit Token 0 (Only if deficit)
            if (req0 > 0n) {
                if (!isNative0) {
                    const { calldata: aprvCall } = await api.post<{ calldata: any }>('v4/lp/prepare-approve', { token: token0.address, amount: req0.toString() }, { chainId: String(backendChainId) });
                    await sendAndWait(aprvCall, `Approve ${token0.symbol}`)
                }
                const { calldata: depCall } = await api.post<{ calldata: any }>('v4/lp/prepare-deposit', { token: token0.address, amount: req0.toString() }, { chainId: String(backendChainId) });
                await sendAndWait(depCall, `Deposit ${token0.symbol}`)
            }

            // 2. Approve & Deposit Token 1 (Only if deficit)
            if (req1 > 0n) {
                if (!isNative1) {
                    const { calldata: aprvCall } = await api.post<{ calldata: any }>('v4/lp/prepare-approve', { token: token1.address, amount: req1.toString() }, { chainId: String(backendChainId) });
                    await sendAndWait(aprvCall, `Approve ${token1.symbol}`)
                }
                const { calldata: depCall } = await api.post<{ calldata: any }>('v4/lp/prepare-deposit', { token: token1.address, amount: req1.toString() }, { chainId: String(backendChainId) });
                await sendAndWait(depCall, `Deposit ${token1.symbol}`)
            }

            // 3. Add Position (only called AFTER deposit txs are confirmed)
            const tickLower = priceToTick(parseFloat(priceLower) || 0, pool.tickSpacing, token0.decimals, token1.decimals);
            const tickUpper = priceToTick(parseFloat(priceUpper) || 0, pool.tickSpacing, token0.decimals, token1.decimals);

            // Calculate Exact V4 Liquidity
            const tickLowerInt = Math.round(tickLower / pool.tickSpacing) * pool.tickSpacing;
            const tickUpperInt = Math.round(tickUpper / pool.tickSpacing) * pool.tickSpacing;

            const sqrtRatioX96 = BigInt(pool.sqrtPriceX96);
            const sqrtRatioAX96 = getSqrtRatioAtTick(tickLowerInt);
            const sqrtRatioBX96 = getSqrtRatioAtTick(tickUpperInt);

            const liquidity = getLiquidityForAmounts(
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                BigInt(amt0Raw),
                BigInt(amt1Raw)
            ).toString();

            const { calldata: addCall } = await api.post<{ calldata: any }>('v4/lp/prepare-add-position', {
                poolKey: pool.poolKey,
                tickLower: tickLowerInt,
                tickUpper: tickUpperInt,
                liquidity,
                token0Amount: amt0Raw,
                token1Amount: amt1Raw
            }, { chainId: String(backendChainId) });

            await sendAndWait(addCall, 'Add Position')

            toast({
                title: "✅ Liquidity Approved!",
                description: `Successfully deposited into the Aqua0 SharedLiquidityPool.`
            })

            onOpenChange(false)
            setAmount0('')
            setAmount1('')
        } catch (error) {
            console.error(error)
            toast({
                title: "Transaction Failed",
                description: error instanceof Error ? error.message : "Failed to deposit liquidity.",
                variant: "destructive",
            })
        } finally {
            setIsSubmitting(false)
        }
    }

    const handleRemovePosition = async (pos: any) => {
        try {
            setIsSubmitting(true)

            // 1. Fetch remove calldata
            const backendChainId = BACKEND_CHAIN_IDS[chainId!] ?? 696969
            const { calldata } = await api.post<{ calldata: any }>('v4/lp/prepare-remove-position', {
                poolKey: pool.poolKey,
                tickLower: pos.tickLower,
                tickUpper: pos.tickUpper,
            }, { chainId: String(backendChainId) })

            // 3. Send transaction
            toast({ title: 'Remove Position...', description: 'Waiting for wallet confirmation' })
            const hash = await sendTransactionAsync({
                to: calldata.to,
                data: calldata.data,
                value: calldata.value ? BigInt(calldata.value) : undefined
            })
            toast({ title: 'Remove submitted', description: 'Waiting for chain confirmation…' })
            await publicClient!.waitForTransactionReceipt({ hash })

            toast({
                title: "Position Removed!",
                description: "Your virtual liquidity has been successfully withdrawn.",
            })

            // 4. Reload
            onOpenChange(false)
        } catch (err: any) {
            console.error(err)
            toast({
                title: "Transaction failed",
                description: err.message,
                variant: "destructive",
            })
        } finally {
            setIsSubmitting(false)
        }
    }

    const isValid = parseFloat(amount0) > 0 || parseFloat(amount1) > 0

    const backendChainIdObj = BACKEND_CHAIN_IDS[chainId!] ?? 696969;
    const isWrongNetwork = chainId && BACKEND_CHAIN_IDS[chainId] === undefined && chainId !== 696969;

    useEffect(() => {
        if (!open) {
            setAmount0('')
            setAmount1('')
            setStrategy('custom')
            setPriceLower(formatPrice(currentPrice * 0.9))
            setPriceUpper(formatPrice(currentPrice * 1.1))
        }
    }, [open, pool, currentPrice])

    useEffect(() => {
        const backendChainId = BACKEND_CHAIN_IDS[chainId!] ?? 696969;
        if (open && activeTab === 'positions' && address) {
            setIsLoadingPositions(true);
            fetchUserPositions(backendChainId, address)
                .then((allPositions) => {
                    const poolPositions = allPositions.filter(p => p.poolId === pool.poolId);
                    setPositions(poolPositions);
                })
                .catch(err => {
                    console.error("Failed to fetch positions", err);
                    toast({
                        title: "Failed to load positions",
                        description: "Could not fetch user positions.",
                        variant: "destructive",
                    });
                })
                .finally(() => {
                    setIsLoadingPositions(false);
                });
        }
    }, [open, activeTab, address, chainId, pool.poolId]);

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent aria-describedby={undefined} className="max-w-lg max-h-[90vh] flex flex-col">
                <DialogHeader className="flex-shrink-0">
                    <DialogTitle className="flex items-center gap-3">
                        <TokenPairIcon tokens={[token0, token1] as any} size="md" />
                        <span>Manage JIT Liquidity</span>
                    </DialogTitle>
                </DialogHeader>

                <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as any)} className="flex-1 overflow-y-auto pr-2 mt-4">
                    <TabsList className="grid w-full grid-cols-2 mb-4 bg-secondary/30">
                        <TabsTrigger value="deposit">Deposit</TabsTrigger>
                        <TabsTrigger value="positions">Active Positions</TabsTrigger>
                    </TabsList>

                    <TabsContent value="deposit" className="space-y-6 m-0">

                        {/* Price Range & Strategies */}
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <Label className="font-semibold text-foreground">Set price range</Label>
                                <span className="text-xs text-muted-foreground bg-secondary/50 px-2 py-1 rounded-md">
                                    Current: {formatPrice(currentPrice)} {token1.symbol} per {token0.symbol}
                                </span>
                            </div>

                            {/* Strategy Presets */}
                            <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                                <Button
                                    variant={strategy === 'stable' ? 'default' : 'outline'}
                                    size="sm"
                                    className="flex flex-col h-auto py-2 items-start"
                                    onClick={() => applyStrategy('stable')}
                                >
                                    <span className="font-semibold">Stable</span>
                                    <span className="text-[10px] text-muted-foreground font-normal">± 3 ticks</span>
                                </Button>
                                <Button
                                    variant={strategy === 'wide' ? 'default' : 'outline'}
                                    size="sm"
                                    className="flex flex-col h-auto py-2 items-start"
                                    onClick={() => applyStrategy('wide')}
                                >
                                    <span className="font-semibold">Wide</span>
                                    <span className="text-[10px] text-muted-foreground font-normal">-50% — +100%</span>
                                </Button>
                                <Button
                                    variant={strategy === 'lower' ? 'default' : 'outline'}
                                    size="sm"
                                    className="flex flex-col h-auto py-2 items-start"
                                    onClick={() => applyStrategy('lower')}
                                >
                                    <span className="font-semibold">Lower Only</span>
                                    <span className="text-[10px] text-muted-foreground font-normal">-50%</span>
                                </Button>
                                <Button
                                    variant={strategy === 'upper' ? 'default' : 'outline'}
                                    size="sm"
                                    className="flex flex-col h-auto py-2 items-start"
                                    onClick={() => applyStrategy('upper')}
                                >
                                    <span className="font-semibold">Upper Only</span>
                                    <span className="text-[10px] text-muted-foreground font-normal">+100%</span>
                                </Button>
                            </div>

                            {/* Price Inputs */}
                            <div className="flex gap-4">
                                <div className="flex-1 space-y-1 rounded-xl border border-border/50 bg-secondary/20 p-3">
                                    <Label className="text-[10px] uppercase tracking-wider text-muted-foreground">Min price</Label>
                                    <div className="flex items-center">
                                        <Input
                                            type="number"
                                            value={priceLower}
                                            onChange={(e) => {
                                                setStrategy('custom')
                                                setPriceLower(e.target.value)
                                            }}
                                            className="border-0 bg-transparent text-xl font-bold p-0 focus-visible:ring-0 h-auto"
                                        />
                                    </div>
                                    <span className="text-[10px] text-muted-foreground">{token1.symbol} per {token0.symbol}</span>
                                </div>
                                <div className="flex-1 space-y-1 rounded-xl border border-border/50 bg-secondary/20 p-3">
                                    <Label className="text-[10px] uppercase tracking-wider text-muted-foreground">Max price</Label>
                                    <div className="flex items-center">
                                        <Input
                                            type="number"
                                            value={priceUpper}
                                            onChange={(e) => {
                                                setStrategy('custom')
                                                setPriceUpper(e.target.value)
                                            }}
                                            className="border-0 bg-transparent text-xl font-bold p-0 focus-visible:ring-0 h-auto"
                                        />
                                    </div>
                                    <span className="text-[10px] text-muted-foreground">{token1.symbol} per {token0.symbol}</span>
                                </div>
                            </div>
                        </div>

                        <div className="h-px bg-border my-4" />

                        {/* Token 0 Input */}
                        <div className="space-y-2">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    <TokenIcon token={token0 as any} size="sm" />
                                    <Label className="font-semibold">{token0.symbol}</Label>
                                </div>
                                <span className="flex flex-col items-end text-xs text-muted-foreground font-mono">
                                    <span>Wallet: {balance0.toFixed(4)}</span>
                                    <span className="text-emerald-500">Shared: {freeBalance0.toFixed(4)}</span>
                                </span>
                            </div>
                            <div className="relative">
                                <Input
                                    type="number"
                                    placeholder="0.00"
                                    value={amount0}
                                    onChange={(e) => handleAmount0Change(e.target.value)}
                                    className="pr-16 text-lg font-mono"
                                />
                                <Button
                                    type="button"
                                    variant="secondary"
                                    size="sm"
                                    className="absolute right-1 top-1/2 h-7 -translate-y-1/2 text-xs"
                                    onClick={handleMax0}
                                >
                                    MAX
                                </Button>
                            </div>
                        </div>

                        <div className="flex items-center justify-center">
                            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-emerald-500/10 text-emerald-500 font-bold">
                                +
                            </div>
                        </div>

                        {/* Token 1 Input */}
                        <div className="space-y-2">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    <TokenIcon token={token1 as any} size="sm" />
                                    <Label className="font-semibold">{token1.symbol}</Label>
                                </div>
                                <span className="flex flex-col items-end text-xs text-muted-foreground font-mono">
                                    <span>Wallet: {balance1.toFixed(4)}</span>
                                    <span className="text-emerald-500">Shared: {freeBalance1.toFixed(4)}</span>
                                </span>
                            </div>
                            <div className="relative">
                                <Input
                                    type="number"
                                    placeholder="0.00"
                                    value={amount1}
                                    onChange={(e) => handleAmount1Change(e.target.value)}
                                    className="pr-16 text-lg font-mono"
                                />
                                <Button
                                    type="button"
                                    variant="secondary"
                                    size="sm"
                                    className="absolute right-1 top-1/2 h-7 -translate-y-1/2 text-xs"
                                    onClick={handleMax1}
                                >
                                    MAX
                                </Button>
                            </div>
                        </div>

                        {/* Action Button */}
                        <div className="mt-4 flex-shrink-0">
                            <Button
                                className="w-full relative py-6 text-lg font-bold bg-[#E11D48] hover:bg-[#BE123C] text-white transition-colors rounded-xl"
                                disabled={isSubmitting || !isValid || !address || !!isWrongNetwork}
                                onClick={handleSubmit}
                            >
                                <span className="relative flex items-center justify-center gap-2">
                                    {isSubmitting ? (
                                        <>
                                            <Loader2 className="w-5 h-5 animate-spin" />
                                            {parseFloat(amount0) > 0 && parseFloat(amount1) > 0 ? 'Approving pair...' : 'Approving...'}
                                        </>
                                    ) : isWrongNetwork ? (
                                        'Wrong Network'
                                    ) : !isValid ? (
                                        'Enter Amounts'
                                    ) : (
                                        <>
                                            Approve JIT Liquidity
                                            <ArrowUpRight className="h-5 w-5" />
                                        </>
                                    )}
                                </span>
                            </Button>
                        </div>
                    </TabsContent>

                    <TabsContent value="positions" className="space-y-4 m-0">
                        {isLoadingPositions ? (
                            <div className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground border rounded-xl bg-secondary/10 border-dashed">
                                <Loader2 className="w-8 h-8 animate-spin mb-2" />
                                <p className="text-sm">Fetching active positions...</p>
                            </div>
                        ) : positions.length === 0 ? (
                            <div className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground border rounded-xl bg-secondary/10 border-dashed">
                                <p className="mb-2">No active positions</p>
                                <p className="text-sm">Deposit tokens to create virtual JIT liquidity.</p>
                            </div>
                        ) : (
                            <div className="space-y-3">
                                {positions.map((pos) => {
                                    const minPrice = formatPrice(tickToPrice(pos.tickLower, token0.decimals, token1.decimals))
                                    const maxPrice = formatPrice(tickToPrice(pos.tickUpper, token0.decimals, token1.decimals))
                                    const isCurrent = pool.currentTick >= pos.tickLower && pool.currentTick <= pos.tickUpper

                                    return (
                                        <Card key={pos.positionId} className="border-border/50 bg-secondary/20">
                                            <CardContent className="p-4 flex items-center justify-between gap-4">
                                                <div className="space-y-1">
                                                    <div className="flex items-center gap-2">
                                                        <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400">
                                                            Active
                                                        </span>
                                                        {isCurrent && (
                                                            <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-blue-500/20 text-blue-400">
                                                                In Range
                                                            </span>
                                                        )}
                                                    </div>
                                                    <div className="text-sm font-medium mt-2">
                                                        {minPrice} - {maxPrice} <span className="text-muted-foreground text-xs">{token1.symbol} per {token0.symbol}</span>
                                                    </div>
                                                </div>
                                                <div className="text-right">
                                                    <div className="text-xs text-muted-foreground">Liquidity Shares</div>
                                                    <div className="font-mono font-semibold text-foreground truncate max-w-[120px]" title={pos.liquidityShares}>
                                                        {parseFloat(formatUnits(BigInt(pos.liquidityShares), 18)).toFixed(4)}
                                                    </div>
                                                    <Button
                                                        variant="destructive"
                                                        size="sm"
                                                        className="h-6 text-[10px] mt-2 w-full"
                                                        onClick={() => handleRemovePosition(pos)}
                                                        disabled={isSubmitting}
                                                    >
                                                        {isSubmitting ? <Loader2 className="w-3 h-3 animate-spin" /> : 'Remove'}
                                                    </Button>
                                                </div>
                                            </CardContent>
                                        </Card>
                                    )
                                })}
                            </div>
                        )}
                    </TabsContent>
                </Tabs>
            </DialogContent>
        </Dialog >
    )
}
