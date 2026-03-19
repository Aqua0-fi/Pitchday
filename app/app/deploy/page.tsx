"use client"

import { useState, useEffect, Suspense } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Checkbox } from '@/components/ui/checkbox'
import { LoadingSpinner } from '@/components/loading-spinner'
import { TokenIcon } from '@/components/token-icon'
import { fetchStrategy } from '@/lib/api'
import { useMappedTokens, useMappedChains } from '@/hooks/use-mapped-tokens'
import { useDeployStrategy } from '@/hooks/use-deploy-strategy'
import type { DeployStep } from '@/hooks/use-deploy-strategy'
import { useWallet } from '@/contexts/wallet-context'
import { BACKEND_CHAIN_IDS } from '@/lib/contracts'
import { calculateRates } from '@/lib/swapvm/encoding'
import type { Token, Chain, StrategyType } from '@/lib/types'
import type { Address } from 'viem'
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronRight,
  AlertTriangle,
  Loader2,
  CheckCircle2,
  XCircle
} from 'lucide-react'
import Loading from './loading'

interface DeployFormState {
  strategyType: StrategyType | null
  tokenA: Token | null
  tokenB: Token | null
  feeTier: number
  selectedChains: string[]
  amountA: string
  amountB: string
}

const initialFormState: DeployFormState = {
  strategyType: null,
  tokenA: null,
  tokenB: null,
  feeTier: 0.3,
  selectedChains: [],
  amountA: '',
  amountB: '',
}

const strategyTypeInfo = [
  {
    type: 'constant-product' as StrategyType,
    label: 'Constant Product',
    formula: 'x * y = k',
    description: 'Classic AMM curve, best for volatile pairs',
    useCases: ['ETH/USDC', 'WBTC/ETH', 'Any volatile pairs'],
  },
  {
    type: 'stable-swap' as StrategyType,
    label: 'Stable Swap',
    formula: 'Curve-style',
    description: 'Optimized for stablecoin pairs with low slippage',
    useCases: ['USDC/USDT', 'DAI/USDC', 'Pegged assets'],
  },
]

const feeTiers = [
  { value: 0.01, label: '0.01%', description: 'Very stable pairs' },
  { value: 0.05, label: '0.05%', description: 'Stable pairs' },
  { value: 0.3, label: '0.3%', description: 'Standard' },
  { value: 1, label: '1%', description: 'Exotic pairs' },
]

const DEPLOY_STEP_LABELS: Record<DeployStep, string> = {
  'idle': '',
  'ensuring-account': 'Creating LP Account...',
  'building': 'Building strategy...',
  'transferring': 'Transferring tokens...',
  'approving': 'Approving tokens...',
  'shipping': 'Deploying strategy...',
  'confirming': 'Confirming transaction...',
  'done': 'Strategy deployed!',
  'error': 'Deployment failed',
}

function DeployPageContent() {
  const router = useRouter()
  const { isConnected, address } = useWallet()
  const [step, setStep] = useState(1)
  const [form, setForm] = useState<DeployFormState>(initialFormState)
  const [validationErrors, setValidationErrors] = useState<string[]>([])
  const [preselectedStrategyId, setPreselectedStrategyId] = useState<string | null>(null)

  // Real data from API
  const { data: tokens, isLoading: tokensLoading, resolveAddress } = useMappedTokens()
  const { data: chains, isLoading: chainsLoading } = useMappedChains()
  const isLoading = tokensLoading || chainsLoading

  // Deploy hook
  const {
    execute: executeDeploy,
    reset: resetDeploy,
    step: deployStep,
    error: deployError,
    result: deployResult,
  } = useDeployStrategy(address ?? undefined)

  const isDeploying = deployStep !== 'idle' && deployStep !== 'done' && deployStep !== 'error'

  const totalSteps = 5

  // Load preselected strategy from URL param
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    setPreselectedStrategyId(params.get('strategy'))
  }, [])

  useEffect(() => {
    if (!preselectedStrategyId) return
    async function loadPreselected() {
      const strategy = await fetchStrategy(preselectedStrategyId!)
      if (strategy) {
        setForm(prev => ({
          ...prev,
          strategyType: strategy.type,
          tokenA: strategy.tokenPair[0],
          tokenB: strategy.tokenPair[1],
          feeTier: strategy.feeTier,
          selectedChains: [strategy.supportedChains[0]?.id || 'base'],
        }))
        setStep(2)
      }
    }
    loadPreselected()
  }, [preselectedStrategyId])

  const handleAmountAChange = (value: string) => {
    setForm(prev => ({ ...prev, amountA: value }))
  }

  const handleAmountBChange = (value: string) => {
    setForm(prev => ({ ...prev, amountB: value }))
  }
  // Validate current step
  const validateStep = (): boolean => {
    const errors: string[] = []

    switch (step) {
      case 1:
        if (!form.strategyType) errors.push('Please select a strategy type')
        break
      case 2:
        if (!form.tokenA) errors.push('Please select Token A')
        if (!form.tokenB) errors.push('Please select Token B')
        if (form.tokenA?.symbol === form.tokenB?.symbol) errors.push('Tokens must be different')
        break
      case 3:
        if (form.selectedChains.length === 0) errors.push('Please select at least one chain')
        break
      case 4:
        {
          const amountA = parseFloat(form.amountA) || 0
          const amountB = parseFloat(form.amountB) || 0
          if (amountA <= 0) errors.push('Please enter amount for Token A')
          if (amountB <= 0) errors.push('Please enter amount for Token B')
        }
        break
    }

    setValidationErrors(errors)
    return errors.length === 0
  }

  const handleNext = () => {
    if (validateStep()) {
      setStep(prev => prev + 1)
    }
  }

  const handleBack = () => {
    setValidationErrors([])
    setStep(prev => prev - 1)
  }

  const handleDeploy = async () => {
    if (!validateStep()) return
    if (!form.tokenA || !form.tokenB || !form.strategyType) return

    const selectedChain = form.selectedChains[0]
    const chainId = BACKEND_CHAIN_IDS[selectedChain]
    if (!chainId) return

    // Resolve chain-specific token addresses
    const addr0 = resolveAddress(form.tokenA.symbol, selectedChain) ?? form.tokenA.address
    const addr1 = resolveAddress(form.tokenB.symbol, selectedChain) ?? form.tokenB.address

    const isStableSwap = form.strategyType === 'stable-swap'

    // Compute stableSwap-specific params
    let linearWidth: string | undefined
    let rate0: string | undefined
    let rate1: string | undefined

    if (isStableSwap) {
      // Default A = 0.8 for the deploy page (modal has its own slider)
      const aBigInt = BigInt("800000000000000000000000000") // 0.8e27
      linearWidth = aBigInt.toString()

      const { rateLt, rateGt } = calculateRates(
        addr0 as Address, form.tokenA.decimals,
        addr1 as Address, form.tokenB.decimals,
      )
      const isToken0Lt = addr0.toLowerCase() < addr1.toLowerCase()
      rate0 = (isToken0Lt ? rateLt : rateGt).toString()
      rate1 = (isToken0Lt ? rateGt : rateLt).toString()
    }

    await executeDeploy({
      template: isStableSwap ? 'stableSwap' : 'constantProduct',
      token0: addr0,
      token1: addr1,
      token0Decimals: form.tokenA.decimals,
      token1Decimals: form.tokenB.decimals,
      amount0: form.amountA,
      amount1: form.amountB,
      feeBps: Math.round(form.feeTier * 100),
      chainId,
      linearWidth,
      rate0,
      rate1,
    })
  }

  if (isLoading) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  // Success state
  if (deployStep === 'done' && deployResult) {
    return (
      <div className="container mx-auto max-w-lg px-4 py-8">
        <Card>
          <CardContent className="py-12 text-center">
            <CheckCircle2 className="mx-auto mb-4 h-16 w-16 text-green-500" />
            <h2 className="mb-2 text-2xl font-bold">Strategy Deployed!</h2>
            <p className="mb-4 text-muted-foreground">
              Your strategy has been deployed successfully.
            </p>
            <div className="mb-6 space-y-1 font-mono text-sm text-muted-foreground">
              <p>Tx: {deployResult.txHash}</p>
              <p>Strategy: {deployResult.strategyHash}</p>
            </div>
            <div className="flex justify-center gap-4">
              <Button variant="outline" onClick={() => router.push('/profile')}>
                View Position
              </Button>
              <Button onClick={() => router.push('/')}>
                Back to Strategies
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Error state
  if (deployStep === 'error') {
    return (
      <div className="container mx-auto max-w-lg px-4 py-8">
        <Card>
          <CardContent className="py-12 text-center">
            <XCircle className="mx-auto mb-4 h-16 w-16 text-destructive" />
            <h2 className="mb-2 text-2xl font-bold">Deployment Failed</h2>
            <p className="mb-6 text-muted-foreground">
              {deployError || 'Something went wrong. Please try again.'}
            </p>
            <Button onClick={() => resetDeploy()}>
              Try Again
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="container mx-auto max-w-3xl px-4 py-8">
      {/* Header */}
      <div className="mb-8">
        <Link
          href="/"
          className="mb-4 inline-flex items-center text-sm text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Strategies
        </Link>
        <h1 className="text-2xl font-bold">Deploy Liquidity</h1>
        <p className="text-muted-foreground">Configure and deploy your liquidity position</p>
      </div>

      {/* Progress indicator */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          {Array.from({ length: totalSteps }, (_, i) => i + 1).map((s) => (
            <div key={s} className="flex items-center">
              <div
                className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-medium transition-colors ${s < step
                    ? 'bg-primary text-primary-foreground'
                    : s === step
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground'
                  }`}
              >
                {s < step ? <Check className="h-4 w-4" /> : s}
              </div>
              {s < totalSteps && (
                <div className={`mx-2 h-0.5 w-8 md:w-16 ${s < step ? 'bg-primary' : 'bg-muted'}`} />
              )}
            </div>
          ))}
        </div>
        <div className="mt-2 flex justify-between text-xs text-muted-foreground">
          <span>Type</span>
          <span>Tokens</span>
          <span>Chains</span>
          <span>Amount</span>
          <span>Review</span>
        </div>
      </div>

      {/* Validation Errors */}
      {validationErrors.length > 0 && (
        <div className="mb-6 rounded-lg border border-destructive/50 bg-destructive/10 p-4">
          <div className="flex items-start gap-2">
            <AlertTriangle className="mt-0.5 h-4 w-4 text-destructive" />
            <div>
              {validationErrors.map((error, i) => (
                <p key={i} className="text-sm text-destructive">{error}</p>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Step 1: Strategy Type */}
      {step === 1 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold">Select Strategy Type</h2>
          <div className="grid gap-4">
            {strategyTypeInfo.map((info) => (
              <Card
                key={info.type}
                className={`cursor-pointer transition-all ${form.strategyType === info.type
                    ? 'border-primary ring-2 ring-primary/20'
                    : 'hover:border-primary/50'
                  }`}
                onClick={() => setForm(prev => ({ ...prev, strategyType: info.type }))}
              >
                <CardContent className="p-6">
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <div className="mb-2 flex items-center gap-2">
                        <h3 className="font-semibold">{info.label}</h3>
                        <Badge variant="secondary">{info.formula}</Badge>
                      </div>
                      <p className="mb-3 text-sm text-muted-foreground">{info.description}</p>
                      <div className="flex flex-wrap gap-2">
                        {info.useCases.map((useCase, i) => (
                          <span key={i} className="rounded bg-muted px-2 py-1 text-xs">
                            {useCase}
                          </span>
                        ))}
                      </div>
                    </div>
                    <div className={`h-5 w-5 rounded-full border-2 ${form.strategyType === info.type
                        ? 'border-primary bg-primary'
                        : 'border-muted'
                      }`}>
                      {form.strategyType === info.type && (
                        <Check className="h-full w-full p-0.5 text-primary-foreground" />
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      {/* Step 2: Token Pair & Fee */}
      {step === 2 && (
        <div className="space-y-6">
          <h2 className="text-lg font-semibold">Token Pair & Fee Configuration</h2>

          {/* Token Selection */}
          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label>Token A</Label>
              <div className="grid grid-cols-2 gap-2">
                {tokens.slice(0, 6).map((token) => (
                  <button
                    key={token.symbol}
                    onClick={() => setForm(prev => ({ ...prev, tokenA: token }))}
                    className={`flex items-center gap-2 rounded-lg border p-3 transition-colors ${form.tokenA?.symbol === token.symbol
                        ? 'border-primary bg-primary/10'
                        : 'hover:border-primary/50'
                      }`}
                  >
                    <TokenIcon token={token} size="sm" />
                    <div className="text-left">
                      <p className="text-sm font-medium">{token.symbol}</p>
                    </div>
                  </button>
                ))}
              </div>
            </div>
            <div className="space-y-2">
              <Label>Token B</Label>
              <div className="grid grid-cols-2 gap-2">
                {tokens.slice(0, 6).map((token) => (
                  <button
                    key={token.symbol}
                    onClick={() => setForm(prev => ({ ...prev, tokenB: token }))}
                    className={`flex items-center gap-2 rounded-lg border p-3 transition-colors ${form.tokenB?.symbol === token.symbol
                        ? 'border-primary bg-primary/10'
                        : 'hover:border-primary/50'
                      }`}
                  >
                    <TokenIcon token={token} size="sm" />
                    <div className="text-left">
                      <p className="text-sm font-medium">{token.symbol}</p>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* Fee Tier */}
          <div className="space-y-3">
            <Label>Fee Tier</Label>
            <RadioGroup
              value={String(form.feeTier)}
              onValueChange={(v) => setForm(prev => ({ ...prev, feeTier: parseFloat(v) }))}
              className="grid grid-cols-2 gap-4 md:grid-cols-4"
            >
              {feeTiers.map((tier) => (
                <div key={tier.value}>
                  <RadioGroupItem
                    value={String(tier.value)}
                    id={`fee-${tier.value}`}
                    className="peer sr-only"
                  />
                  <Label
                    htmlFor={`fee-${tier.value}`}
                    className="flex cursor-pointer flex-col items-center rounded-lg border-2 border-muted p-4 transition-colors hover:border-primary/50 peer-data-[state=checked]:border-primary peer-data-[state=checked]:bg-primary/10"
                  >
                    <span className="text-lg font-bold">{tier.label}</span>
                    <span className="text-xs text-muted-foreground">{tier.description}</span>
                  </Label>
                </div>
              ))}
            </RadioGroup>
          </div>

          {/* Selected pair summary */}
          {form.tokenA && form.tokenB && (
            <Card className="bg-muted/30">
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">Selected Pair</span>
                  <span className="font-medium">{form.tokenA.symbol}/{form.tokenB.symbol}</span>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Step 3: Chain Selection */}
      {step === 3 && (
        <div className="space-y-6">
          <h2 className="text-lg font-semibold">Select Chain</h2>
          <p className="text-sm text-muted-foreground">
            Choose where to deploy your liquidity
          </p>

          <div className="grid gap-4 md:grid-cols-3">
            {chains.map((chain) => {
              const isSelected = form.selectedChains.includes(chain.id)
              const gasEstimate = chain.id === 'base' ? 0.5 : 0.3

              return (
                <Card
                  key={chain.id}
                  className={`cursor-pointer transition-all ${isSelected ? 'border-primary ring-2 ring-primary/20' : 'hover:border-primary/50'
                    }`}
                  onClick={() => {
                    setForm(prev => ({
                      ...prev,
                      selectedChains: isSelected
                        ? prev.selectedChains.filter(c => c !== chain.id)
                        : [...prev.selectedChains, chain.id]
                    }))
                  }}
                >
                  <CardContent className="p-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div
                          className="flex h-10 w-10 items-center justify-center rounded-full text-lg font-bold text-white"
                          style={{ backgroundColor: chain.color }}
                        >
                          {chain.name.charAt(0)}
                        </div>
                        <div>
                          <p className="font-medium">{chain.name}</p>
                          <p className="text-xs text-muted-foreground">
                            Gas: ~${gasEstimate.toFixed(2)}
                          </p>
                        </div>
                      </div>
                      <Checkbox checked={isSelected} />
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>

          {form.selectedChains.length > 0 && (
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">Estimated Total Gas</span>
                  <span className="font-medium">
                    ${form.selectedChains.reduce((acc, chainId) => {
                      const gas = chainId === 'base' ? 0.5 : 0.3
                      return acc + gas
                    }, 0).toFixed(2)}
                  </span>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Step 4: Liquidity Amount */}
      {step === 4 && (
        <div className="space-y-6">
          <h2 className="text-lg font-semibold">Enter Liquidity Amount</h2>
          <p className="text-sm text-muted-foreground">
            Enter the amount of each token to deposit into your strategy.
          </p>

          {/* Token A Input */}
          <Card>
            <CardContent className="p-4 space-y-3">
              <div className="flex items-center gap-2">
                {form.tokenA && <TokenIcon token={form.tokenA} size="sm" />}
                <Label className="text-base font-semibold">{form.tokenA?.symbol || 'Token A'}</Label>
              </div>
              <Input
                type="number"
                placeholder="0.00"
                value={form.amountA}
                onChange={(e) => handleAmountAChange(e.target.value)}
                className="text-xl h-14 font-mono"
              />
            </CardContent>
          </Card>

          {/* Plus indicator */}
          <div className="flex items-center justify-center">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10 text-primary text-lg font-bold">
              +
            </div>
          </div>

          {/* Token B Input */}
          <Card>
            <CardContent className="p-4 space-y-3">
              <div className="flex items-center gap-2">
                {form.tokenB && <TokenIcon token={form.tokenB} size="sm" />}
                <Label className="text-base font-semibold">{form.tokenB?.symbol || 'Token B'}</Label>
              </div>
              <Input
                type="number"
                placeholder="0.00"
                value={form.amountB}
                onChange={(e) => handleAmountBChange(e.target.value)}
                className="text-xl h-14 font-mono"
              />
            </CardContent>
          </Card>
        </div>
      )}

      {/* Step 5: Review & Confirm */}
      {step === 5 && (
        <div className="space-y-6">
          <h2 className="text-lg font-semibold">Review & Confirm</h2>

          {/* Summary Card */}
          <Card>
            <CardHeader>
              <CardTitle>Position Summary</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between border-b pb-4">
                <span className="text-muted-foreground">Strategy Type</span>
                <span className="font-medium">
                  {strategyTypeInfo.find(s => s.type === form.strategyType)?.label}
                </span>
              </div>
              <div className="flex items-center justify-between border-b pb-4">
                <span className="text-muted-foreground">Token Pair</span>
                <span className="font-medium">
                  {form.tokenA?.symbol}/{form.tokenB?.symbol}
                </span>
              </div>
              <div className="flex items-center justify-between border-b pb-4">
                <span className="text-muted-foreground">Fee Tier</span>
                <span className="font-medium">{form.feeTier}%</span>
              </div>
              <div className="flex items-center justify-between border-b pb-4">
                <span className="text-muted-foreground">Chain</span>
                <div className="flex gap-2">
                  {form.selectedChains.map(chainId => {
                    const chain = chains.find(c => c.id === chainId)
                    return chain ? (
                      <span
                        key={chainId}
                        className="rounded-full px-2 py-1 text-xs font-medium text-white"
                        style={{ backgroundColor: chain.color }}
                      >
                        {chain.name}
                      </span>
                    ) : null
                  })}
                </div>
              </div>
              <div className="flex items-center justify-between border-b pb-4">
                <span className="text-muted-foreground">{form.tokenA?.symbol} Amount</span>
                <span className="font-medium">{parseFloat(form.amountA).toFixed(6)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">{form.tokenB?.symbol} Amount</span>
                <span className="font-medium">{parseFloat(form.amountB).toFixed(6)}</span>
              </div>
            </CardContent>
          </Card>

          {/* Risk Warnings */}
          <Card className="border-yellow-500/30 bg-yellow-500/5">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-yellow-500">
                <AlertTriangle className="h-5 w-5" />
                Risk Warnings
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <p className="text-sm text-yellow-500">
                Impermanent loss is possible with volatile token pairs.
              </p>
              <a href="#" className="inline-flex items-center text-sm text-primary hover:underline">
                Learn more about risks
                <ChevronRight className="ml-1 h-4 w-4" />
              </a>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Deploy Progress */}
      {isDeploying && (
        <Card className="mt-6 border-primary/30 bg-primary/5">
          <CardContent className="flex items-center gap-3 p-4">
            <Loader2 className="h-5 w-5 animate-spin text-primary" />
            <span className="font-medium">{DEPLOY_STEP_LABELS[deployStep]}</span>
          </CardContent>
        </Card>
      )}

      {/* Navigation Buttons */}
      <div className="mt-8 flex justify-between">
        <Button
          variant="outline"
          onClick={handleBack}
          disabled={step === 1 || isDeploying}
        >
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back
        </Button>

        {step === 5 ? (
          !isConnected ? (
            <Button onClick={() => { /* wallet connect handled by provider */ }} disabled className="min-w-[140px]">
              Connect Wallet
            </Button>
          ) : (
            <Button onClick={handleDeploy} disabled={isDeploying} className="min-w-[140px]">
              {isDeploying ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {DEPLOY_STEP_LABELS[deployStep] || 'Deploying...'}
                </>
              ) : (
                <>
                  Deploy Strategy
                  <Check className="ml-2 h-4 w-4" />
                </>
              )}
            </Button>
          )
        ) : (
          <Button onClick={handleNext}>
            Next
            <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        )}
      </div>
    </div>
  )
}

export default function DeployPage() {
  return (
    <Suspense fallback={<Loading />}>
      <DeployPageContent />
    </Suspense>
  )
}
