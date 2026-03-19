"use client"

import { useState, useEffect } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Slider } from '@/components/ui/slider'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { TokenSelector } from '@/components/swap/token-selector'
import { ChainIcon } from '@/components/chain-icon'
import { useMappedTokens, useMappedChains } from '@/hooks/use-mapped-tokens'
import { useV4Pools } from '@/hooks/use-v4-pools'
import { useSwapQuote } from '@/hooks/use-swap-quote'
import { useExecuteSwap } from '@/hooks/use-execute-swap'
import { BACKEND_CHAIN_IDS } from '@/lib/contracts'
import type { Token, Chain } from '@/lib/types'
import { ArrowDownUp, Settings, Loader2, AlertCircle, Droplets, Info } from 'lucide-react'
import { formatUnits } from 'viem'
import { useToast } from '@/hooks/use-toast'
import { useWallet } from '@/contexts/wallet-context'
import { useBalance, useSwitchChain } from 'wagmi'
import { base, baseSepolia } from 'wagmi/chains'
import type { Address } from 'viem'

// Map our internal chain IDs to wagmi chain IDs
const chainIdMap: Record<string, number[]> = {
  base: [base.id, baseSepolia.id],     // 8453, 84532
  unichain: [130, 1301],               // mainnet, sepolia
  local: [696969],                     // local devnet
}

function isOnCorrectChain(walletChainId: number | undefined, selectedChainId: string): boolean {
  if (!walletChainId) return false
  const validIds = chainIdMap[selectedChainId]
  return validIds ? validIds.includes(walletChainId) : false
}

function getTargetChainId(selectedChainId: string): number {
  if (selectedChainId === 'local') return 696969;
  return selectedChainId === 'base' ? baseSepolia.id : 1301
}

const STEP_LABELS: Record<string, string> = {
  approving: 'Approving...',
  preparing: 'Preparing...',
  swapping: 'Sending transaction...',
  confirming: 'Confirming...',
}

export default function SwapPage() {
  const { isConnected, chainId, address, connect } = useWallet()
  const { toast } = useToast()
  const { switchChain, isPending: isSwitchingChain } = useSwitchChain()

  // Real data from API
  const { data: chains } = useMappedChains()

  // Chain state — single chain, default to first available
  const [selectedChain, setSelectedChain] = useState<Chain | null>(null)

  // Set default chain once chains load
  useEffect(() => {
    if (chains.length > 0 && !selectedChain) {
      setSelectedChain(chains[0])
    }
  }, [chains, selectedChain])

  // Fetch tokens filtered by selected chain (avoids duplicates like USDC on Base + Arbitrum)
  const { data: tokens } = useMappedTokens(selectedChain?.id)

  // Detect if wallet is on a different chain than selected
  const needsChainSwitch = isConnected && selectedChain && !isOnCorrectChain(chainId, selectedChain.id)

  // Sync with wallet chain on connect
  useEffect(() => {
    if (chainId && chains.length > 0) {
      const walletChain = chains.find(c => isOnCorrectChain(chainId, c.id))
      if (walletChain) {
        setSelectedChain(walletChain)
      }
    }
  }, [chainId, chains])

  // Form state — set defaults once tokens load
  const [fromToken, setFromToken] = useState<Token | null>(null)
  const [toToken, setToToken] = useState<Token | null>(null)

  // Reset selected tokens when chain changes (tokens are different per chain)
  useEffect(() => {
    setFromToken(null)
    setToToken(null)
    setFromAmount('')
  }, [selectedChain?.id])

  // Set default tokens once they load
  useEffect(() => {
    if (tokens.length > 0 && !fromToken) {
      setFromToken(tokens[0])
      if (tokens.length > 1) setToToken(tokens[1])
    }
  }, [tokens, fromToken])
  const [fromAmount, setFromAmount] = useState('')
  const [slippage, setSlippage] = useState(0.5)

  // Backend chain ID for API calls
  const backendChainId = selectedChain?.id ? BACKEND_CHAIN_IDS[selectedChain.id] : undefined

  // V4 Pools from backend
  const { data: v4Pools, isLoading: isLoadingPools } = useV4Pools(backendChainId ?? 84532)

  // Find ALL matching pools for the selected token pair, then round-robin across them
  const [swapCounter, setSwapCounter] = useState(0)
  const matchingPools = v4Pools?.filter((p) =>
    (p.token0.address.toLowerCase() === fromToken?.address.toLowerCase() && p.token1.address.toLowerCase() === toToken?.address.toLowerCase()) ||
    (p.token1.address.toLowerCase() === fromToken?.address.toLowerCase() && p.token0.address.toLowerCase() === toToken?.address.toLowerCase())
  ) ?? []
  const matchedPool = matchingPools.length > 0 ? matchingPools[swapCounter % matchingPools.length] : undefined

  const hasLiquidity = !!matchedPool

  // Real quote from exact math
  const {
    data: quoteData,
    isLoading: isLoadingQuote,
  } = useSwapQuote(
    matchedPool,
    fromToken?.address,
    fromAmount,
    fromToken?.decimals,
    toToken?.decimals,
    backendChainId,
  )

  // Swap execution
  const {
    execute: executeSwap,
    reset: resetSwap,
    step: swapStep,
    error: swapError,
    txHash,
  } = useExecuteSwap(address ?? undefined)

  // Toast on swap completion
  useEffect(() => {
    if (swapStep === 'done') {
      toast({
        title: 'Swap Successful',
        description: `Swapped ${fromAmount} ${fromToken?.symbol} for ${quoteData?.amountOut ?? ''} ${toToken?.symbol}`,
      })
      setFromAmount('')
      resetSwap()
    }
  }, [swapStep, fromAmount, fromToken?.symbol, toToken?.symbol, quoteData?.amountOut, toast, resetSwap])

  // Real wallet balance via wagmi
  const isNativeToken = fromToken?.symbol === 'ETH'
  const hasValidTokenAddress = fromToken?.address && fromToken.address !== '0x...'
  const { data: balanceData } = useBalance({
    address: address as Address | undefined,
    token: isNativeToken ? undefined : (hasValidTokenAddress ? fromToken?.address as Address : undefined),
    query: {
      enabled: isConnected && !!address && (isNativeToken || !!hasValidTokenAddress),
    },
  })
  const fromBalance = balanceData ? Number(balanceData.formatted) : null

  const handleSwapDirection = () => {
    setFromToken(toToken)
    setToToken(fromToken)
    setFromAmount('')
    resetSwap()
  }

  const handleSwap = () => {
    if (!matchedPool || !quoteData || !fromToken || !toToken || !backendChainId) return

    executeSwap({
      pool: matchedPool,
      tokenIn: fromToken.address,
      tokenOut: toToken.address,
      amountIn: fromAmount,
      decimalsIn: fromToken.decimals,
      slippageBps: Math.round(slippage * 100), // 0.5% → 50 bps
    })
    // Rotate to next pool for the following swap
    setSwapCounter(c => c + 1)
  }

  const isSwapBusy = swapStep !== 'idle' && swapStep !== 'done' && swapStep !== 'error'
  const hasValidAmount = !!fromAmount && Number(fromAmount) > 0
  const isValidSwap = fromToken && toToken && hasValidAmount && quoteData && hasLiquidity && !needsChainSwitch

  const handleSwitchChain = () => {
    if (!selectedChain) return
    const targetId = getTargetChainId(selectedChain.id)
    switchChain({ chainId: targetId })
  }

  // Exchange rate from quote
  const exchangeRate = quoteData && hasValidAmount
    ? (Number(quoteData.amountOut) / Number(fromAmount)).toFixed(6)
    : null

  // Chain-specific accent color for background orbs
  const chainColor = selectedChain?.color ?? '#0052FF'

  return (
    <div className="min-h-screen relative overflow-hidden">
      {/* Background Effects */}
      <div className="absolute inset-0 -z-10">
        {/* Animated gradient orbs — color follows selected chain */}
        <div
          className="absolute w-[500px] h-[500px] rounded-full blur-[120px] transition-colors duration-700"
          style={{
            backgroundColor: `${chainColor}40`,
            animation: 'float1 8s ease-in-out infinite',
            top: '10%',
            left: '10%',
          }}
        />
        <div
          className="absolute w-[400px] h-[400px] rounded-full blur-[100px] transition-colors duration-700"
          style={{
            backgroundColor: `${chainColor}33`,
            animation: 'float2 10s ease-in-out infinite',
            bottom: '20%',
            right: '10%',
          }}
        />
        <div
          className="absolute w-[350px] h-[350px] rounded-full blur-[80px] transition-colors duration-700"
          style={{
            backgroundColor: `${chainColor}26`,
            animation: 'float3 12s ease-in-out infinite',
            top: '50%',
            left: '50%',
          }}
        />

        {/* Grid pattern */}
        <div
          className="absolute inset-0 opacity-[0.03]"
          style={{
            backgroundImage: `linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)`,
            backgroundSize: '50px 50px',
          }}
        />

        {/* Radial gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-background/50 to-background" />

        {/* CSS Animations */}
        <style jsx>{`
          @keyframes float1 {
            0%, 100% { transform: translate(0, 0) scale(1); }
            25% { transform: translate(50px, 30px) scale(1.1); }
            50% { transform: translate(20px, -40px) scale(0.95); }
            75% { transform: translate(-30px, 20px) scale(1.05); }
          }
          @keyframes float2 {
            0%, 100% { transform: translate(0, 0) scale(1); }
            25% { transform: translate(-40px, -30px) scale(1.05); }
            50% { transform: translate(30px, 50px) scale(1.1); }
            75% { transform: translate(20px, -20px) scale(0.95); }
          }
          @keyframes float3 {
            0%, 100% { transform: translate(-50%, -50%) scale(1); }
            33% { transform: translate(-40%, -60%) scale(1.15); }
            66% { transform: translate(-60%, -40%) scale(0.9); }
          }
        `}</style>
      </div>

      <div className="mx-auto max-w-lg px-4 py-8 sm:px-6 lg:px-8 relative z-10">
        {/* Header */}
        <div className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Swap</h1>
            <p className="text-sm text-muted-foreground">
              Trade tokens on {selectedChain?.name ?? 'Base'}
            </p>
          </div>

          {/* Settings */}
          <Dialog>
            <DialogTrigger asChild>
              <Button variant="ghost" size="icon">
                <Settings className="h-5 w-5" />
              </Button>
            </DialogTrigger>
            <DialogContent className="max-w-sm">
              <DialogHeader>
                <DialogTitle>Swap Settings</DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <div className="space-y-2">
                  <Label>Slippage Tolerance</Label>
                  <div className="flex items-center gap-4">
                    <Slider
                      value={[slippage]}
                      onValueChange={([value]) => setSlippage(value)}
                      min={0.1}
                      max={5}
                      step={0.1}
                      className="flex-1"
                    />
                    <span className="text-sm font-medium w-12 text-right">{slippage}%</span>
                  </div>
                </div>
                <div className="flex gap-2">
                  {[0.5, 1, 2].map((value) => (
                    <Button
                      key={value}
                      variant={slippage === value ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => setSlippage(value)}
                    >
                      {value}%
                    </Button>
                  ))}
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>

        {/* Chain Toggle */}
        {chains.length > 0 && (
          <div className="mb-4 flex items-center gap-2 rounded-lg bg-secondary/50 p-1">
            {chains.map((chain) => (
              <button
                key={chain.id}
                type="button"
                onClick={() => setSelectedChain(chain)}
                className={`flex flex-1 items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors ${selectedChain?.id === chain.id
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
                  }`}
              >
                <ChainIcon chain={chain} size="sm" />
                {chain.name}
              </button>
            ))}
          </div>
        )}

        {/* Swap Card */}
        <Card className="overflow-hidden">
          <CardContent className="p-0">
            {/* From Section */}
            <div className="border-b border-border p-4">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-sm text-muted-foreground">From</span>
                {isConnected && (
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">
                      Balance: {fromBalance !== null ? fromBalance.toFixed(4) : '--'} {fromToken?.symbol}
                    </span>
                    {fromBalance !== null && fromBalance > 0 && (
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-6 px-2 text-xs text-primary"
                        onClick={() => setFromAmount(String(fromBalance))}
                      >
                        MAX
                      </Button>
                    )}
                  </div>
                )}
              </div>

              <div className="flex items-center gap-3">
                <Input
                  type="number"
                  placeholder="0.00"
                  value={fromAmount}
                  onChange={(e) => setFromAmount(e.target.value)}
                  className="flex-1 border-0 bg-transparent text-2xl font-medium focus-visible:ring-0 p-0 h-auto"
                />
                <TokenSelector
                  selectedToken={fromToken}
                  onSelectToken={setFromToken}
                  excludeToken={toToken}
                  chain={selectedChain?.id}
                />
              </div>
            </div>

            {/* Swap Direction Button */}
            <div className="relative py-2">
              <div className="absolute inset-x-0 top-1/2 -translate-y-1/2 border-t border-border" />
              <div className="relative flex justify-center">
                <Button
                  variant="outline"
                  size="icon"
                  className="h-10 w-10 rounded-full bg-background"
                  onClick={handleSwapDirection}
                >
                  <ArrowDownUp className="h-4 w-4" />
                </Button>
              </div>
            </div>

            {/* To Section */}
            <div className="border-b border-border p-4">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-sm text-muted-foreground">To</span>
                <div className="flex items-center gap-2">
                  {(isLoadingQuote || isLoadingPools) && (
                    <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                  )}
                  {quoteData && !quoteData.isExactSimulation && (
                    <span className="text-xs text-amber-400/80">~Estimated</span>
                  )}
                </div>
              </div>

              <div className="flex items-center gap-3">
                <div className="flex-1 flex items-center gap-2">
                  <p className="text-2xl font-medium">
                    {quoteData ? Number(quoteData.amountOut).toFixed(4) : '0.00'}
                  </p>
                  {/* JIT Breakdown info button */}
                  {quoteData?.isExactSimulation && quoteData.apiResult && (
                    <Popover>
                      <PopoverTrigger asChild>
                        <button className="text-muted-foreground hover:text-foreground transition-colors">
                          <Info className="h-4 w-4" />
                        </button>
                      </PopoverTrigger>
                      <PopoverContent className="w-72 p-4 text-sm" side="top">
                        <p className="font-semibold mb-3">Liquidity Breakdown</p>
                        <p className="text-xs text-muted-foreground mb-3">
                          This swap was simulated exactly as the smart contract executes it.
                        </p>
                        {(() => {
                          const r = quoteData.apiResult!
                          const zfo = r.zeroForOne
                          // For zeroForOne:
                          //   virtualDelta0 < 0 means pool paid token0 (we got it)
                          //   virtualDelta1 > 0 means we gave token1 to pool
                          // What user cares about: how much of output came from JIT?
                          const virtualOut = zfo
                            ? BigInt(r.virtualDelta1)  // token1 out from JIT (positive = JIT received = jit gave token1)
                            : BigInt(r.virtualDelta0)
                          const totalOut = BigInt(r.totalAmountOut)
                          const absVirtual = virtualOut < 0n ? -virtualOut : virtualOut
                          const absTotalOut = totalOut < 0n ? -totalOut : totalOut
                          const jitPct = absTotalOut > 0n
                            ? Number((absVirtual * 10000n) / absTotalOut) / 100
                            : 0
                          const realPct = Math.max(0, 100 - jitPct)
                          const sym = toToken?.symbol ?? ''
                          const dec = toToken?.decimals ?? 18
                          const jitAmt = formatUnits(absVirtual, dec)
                          const realAmt = formatUnits(absTotalOut - absVirtual > 0n ? absTotalOut - absVirtual : 0n, dec)
                          return (
                            <div className="space-y-2">
                              <div className="flex justify-between items-center">
                                <div className="flex items-center gap-2">
                                  <div className="h-2.5 w-2.5 rounded-full bg-blue-500" />
                                  <span className="text-muted-foreground">Virtual JIT Pool</span>
                                </div>
                                <span className="font-mono text-blue-400">{Number(jitAmt).toFixed(4)} {sym} ({jitPct.toFixed(1)}%)</span>
                              </div>
                              <div className="flex justify-between items-center">
                                <div className="flex items-center gap-2">
                                  <div className="h-2.5 w-2.5 rounded-full bg-pink-500" />
                                  <span className="text-muted-foreground">Real V4 Liquidity</span>
                                </div>
                                <span className="font-mono text-pink-400">{Number(realAmt).toFixed(4)} {sym} ({realPct.toFixed(1)}%)</span>
                              </div>
                              <div className="border-t border-border pt-2 flex justify-between items-center">
                                <span className="text-muted-foreground">Total Out</span>
                                <span className="font-mono font-semibold">{Number(formatUnits(absTotalOut, dec)).toFixed(4)} {sym}</span>
                              </div>
                            </div>
                          )
                        })()}
                      </PopoverContent>
                    </Popover>
                  )}
                </div>
                <TokenSelector
                  selectedToken={toToken}
                  onSelectToken={setToToken}
                  excludeToken={fromToken}
                  chain={selectedChain?.id}
                />
              </div>
            </div>

            {/* Pool Routing Info */}
            {matchedPool && matchingPools.length > 1 && (
              <div className="border-b border-border bg-secondary/20 px-4 py-2.5 flex items-center justify-between">
                <span className="text-xs text-muted-foreground">Routing via</span>
                <span className="text-xs font-medium text-emerald-400">
                  {matchedPool.label || `Pool ${matchedPool.fee / 10000}%`} ({swapCounter % matchingPools.length + 1}/{matchingPools.length})
                </span>
              </div>
            )}

            {/* No Liquidity Warning */}
            {fromToken && toToken && hasValidAmount && !isLoadingPools && !hasLiquidity && (
              <div className="border-b border-border bg-muted/50 p-4">
                <div className="flex items-start gap-3">
                  <Droplets className="h-5 w-5 text-muted-foreground shrink-0" />
                  <div>
                    <p className="text-sm font-medium">No liquidity (or Pool) available</p>
                    <p className="text-xs text-muted-foreground">
                      There is no Uniswap V4 pool deployed for {fromToken.symbol}/{toToken.symbol} on {selectedChain?.name ?? 'this chain'} yet.
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* Quote Details */}
            {quoteData && (
              <div className="border-b border-border bg-secondary/30 p-4 space-y-3">
                {/* Exchange Rate */}
                {exchangeRate && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Rate {quoteData.isExactSimulation ? '' : '(estimated)'}</span>
                    <span>1 {fromToken?.symbol} = {exchangeRate} {toToken?.symbol}</span>
                  </div>
                )}

                {/* Fee */}
                {matchedPool && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Pool Fee</span>
                    <span>{(matchedPool.fee / 10000).toFixed(2)}%</span>
                  </div>
                )}

                {/* Slippage */}
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">Max Slippage</span>
                  <span>{slippage}%</span>
                </div>

                {/* Exact sim badge */}
                {quoteData.isExactSimulation && (
                  <div className="flex items-center gap-1 text-xs text-emerald-400">
                    <span className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-400" />
                    Exact simulation — click ⓘ next to output for JIT breakdown
                  </div>
                )}
              </div>
            )}

            {/* Swap Error */}
            {swapError && (
              <div className="border-b border-border bg-destructive/10 p-4">
                <div className="flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-destructive shrink-0" />
                  <div>
                    <p className="text-sm font-medium text-destructive">
                      {swapError}
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* Swap Button */}
            <div className="p-4">
              {!isConnected ? (
                <Button className="w-full" size="lg" onClick={connect}>
                  Log in
                </Button>
              ) : needsChainSwitch ? (
                <Button
                  className="w-full"
                  size="lg"
                  onClick={handleSwitchChain}
                  disabled={isSwitchingChain}
                >
                  {isSwitchingChain ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Switching...
                    </>
                  ) : (
                    `Switch to ${selectedChain?.name ?? 'correct chain'}`
                  )}
                </Button>
              ) : isSwapBusy ? (
                <Button className="w-full" size="lg" disabled>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {STEP_LABELS[swapStep] ?? 'Processing...'}
                </Button>
              ) : !isValidSwap ? (
                <Button className="w-full" size="lg" disabled>
                  {!hasValidAmount
                    ? 'Enter an amount'
                    : isLoadingPools || isLoadingQuote
                      ? 'Fetching quote...'
                      : !hasLiquidity
                        ? 'No liquidity'
                        : 'Swap'}
                </Button>
              ) : (
                <Button
                  className="w-full"
                  size="lg"
                  onClick={handleSwap}
                >
                  Swap
                </Button>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
