"use client"

import { useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Checkbox } from '@/components/ui/checkbox'
import { Slider } from '@/components/ui/slider'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { useMappedTokens, useMappedChains } from '@/hooks/use-mapped-tokens'
import { useDeployStrategy } from '@/hooks/use-deploy-strategy'
import type { DeployStep } from '@/hooks/use-deploy-strategy'
import { useWallet } from '@/contexts/wallet-context'
import { BACKEND_CHAIN_IDS } from '@/lib/contracts'
import { calculateRates } from '@/lib/swapvm/encoding'
import type { StrategyType, CreateStrategyForm, Token } from '@/lib/types'
import type { Address } from 'viem'
import { ArrowLeft, ArrowRight, Check, Loader2, Info } from 'lucide-react'
import { TokenIcon } from '@/components/token-icon'
import { ChainIcon } from '@/components/chain-icon'
import { Card, CardContent } from '@/components/ui/card'

interface CreateStrategyModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSubmit: (form: CreateStrategyForm) => Promise<void>
}

const steps = [
  { id: 1, title: 'Strategy Type' },
  { id: 2, title: 'Configuration' },
  { id: 3, title: 'Select Chains' },
  { id: 4, title: 'Initial Liquidity' },
  { id: 5, title: 'Review' },
]

const strategyTypes: { value: StrategyType; label: string; description: string }[] = [
  { value: 'constant-product', label: 'Constant Product', description: 'Classic x*y=k AMM curve' },
  { value: 'stable-swap', label: 'Stable Swap', description: 'Optimized for stable pairs' },
]

const feeTiers = [0.01, 0.05, 0.3, 1.0]

const STABLECOINS = new Set(['USDC', 'USDT', 'DAI'])

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

export function CreateStrategyModal({ open, onOpenChange, onSubmit }: CreateStrategyModalProps) {
  const { address } = useWallet()
  const { data: tokens, resolveAddress } = useMappedTokens()
  const { data: chains } = useMappedChains()

  const {
    execute: executeDeploy,
    reset: resetDeploy,
    step: deployStep,
    error: deployError,
    result: deployResult,
  } = useDeployStrategy(address ?? undefined)

  const isDeploying = deployStep !== 'idle' && deployStep !== 'done' && deployStep !== 'error'

  const [currentStep, setCurrentStep] = useState(1)
  const [amountA, setAmountA] = useState('')
  const [amountB, setAmountB] = useState('')
  const [aParameter, setAParameter] = useState(0.8)
  const [form, setForm] = useState<CreateStrategyForm>({
    type: 'constant-product',
    tokenPair: ['', ''],
    feeTier: 0.3,
    priceRange: undefined,
    chains: [],
    initialLiquidity: 0,
  })

  // Set default token pair once tokens load
  const defaultsSet = useState(false)
  if (tokens.length > 0 && !defaultsSet[0]) {
    const defaultA = tokens.find(t => t.symbol === 'ETH') || tokens[0]
    const defaultB = tokens.find(t => t.symbol === 'USDC') || tokens[1]
    if (defaultA && defaultB) {
      setForm(prev => ({ ...prev, tokenPair: [defaultA.symbol, defaultB.symbol] }))
      defaultsSet[1](true)
    }
  }

  // Filter tokens: stable-swap only shows stablecoins
  const availableTokens = form.type === 'stable-swap'
    ? tokens.filter(t => STABLECOINS.has(t.symbol))
    : tokens

  // Get token objects from symbols
  const tokenA = tokens.find(t => t.symbol === form.tokenPair[0])
  const tokenB = tokens.find(t => t.symbol === form.tokenPair[1])

  const handleAmountAChange = (value: string) => {
    setAmountA(value)
  }

  const handleAmountBChange = (value: string) => {
    setAmountB(value)
  }

  const handleNext = () => {
    if (currentStep < 5) setCurrentStep(currentStep + 1)
  }

  const handleBack = () => {
    if (currentStep > 1) setCurrentStep(currentStep - 1)
  }

  const handleSubmit = async () => {
    if (!tokenA || !tokenB) return

    const selectedChain = form.chains[0]
    const chainId = BACKEND_CHAIN_IDS[selectedChain]
    if (!chainId) return

    // Resolve chain-specific token addresses
    const addr0 = resolveAddress(tokenA.symbol, selectedChain) ?? tokenA.address
    const addr1 = resolveAddress(tokenB.symbol, selectedChain) ?? tokenB.address

    const isStableSwap = form.type === 'stable-swap'

    // Compute stableSwap-specific params
    let linearWidth: string | undefined
    let rate0: string | undefined
    let rate1: string | undefined

    if (isStableSwap) {
      // linearWidth = A parameter * 1e27
      const aBigInt = BigInt(Math.round(aParameter * 10)) * BigInt("100000000000000000000000000") // e.g. 0.8 → 8 * 1e26 = 8e26
      linearWidth = aBigInt.toString()

      // Compute decimal normalization rates
      const { rateLt, rateGt } = calculateRates(
        addr0 as Address, tokenA.decimals,
        addr1 as Address, tokenB.decimals,
      )
      // Map sorted rates back to token0/token1 order
      const isToken0Lt = addr0.toLowerCase() < addr1.toLowerCase()
      rate0 = (isToken0Lt ? rateLt : rateGt).toString()
      rate1 = (isToken0Lt ? rateGt : rateLt).toString()
    }

    await executeDeploy({
      template: isStableSwap ? 'stableSwap' : 'constantProduct',
      token0: addr0,
      token1: addr1,
      token0Decimals: tokenA.decimals,
      token1Decimals: tokenB.decimals,
      amount0: amountA,
      amount1: amountB,
      feeBps: Math.round(form.feeTier * 100),
      chainId,
      linearWidth,
      rate0,
      rate1,
    })
  }

  const canProceed = () => {
    switch (currentStep) {
      case 1:
        return true
      case 2:
        return form.tokenPair[0] && form.tokenPair[1] && form.tokenPair[0] !== form.tokenPair[1]
      case 3:
        return form.chains.length > 0
      case 4:
        return parseFloat(amountA) > 0 && parseFloat(amountB) > 0
      default:
        return true
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] flex flex-col">
        <DialogHeader className="flex-shrink-0">
          <DialogTitle>Create Strategy</DialogTitle>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto pr-2">
          {/* Progress Steps */}
          <div className="mb-6 flex items-center justify-between">
            {steps.map((step, index) => (
              <div key={step.id} className="flex items-center">
                <div
                  className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-medium ${currentStep > step.id
                      ? 'bg-primary text-primary-foreground'
                      : currentStep === step.id
                        ? 'bg-primary text-primary-foreground'
                        : 'bg-muted text-muted-foreground'
                    }`}
                >
                  {currentStep > step.id ? <Check className="h-4 w-4" /> : step.id}
                </div>
                {index < steps.length - 1 && (
                  <div
                    className={`mx-2 h-0.5 w-6 ${currentStep > step.id ? 'bg-primary' : 'bg-muted'
                      }`}
                  />
                )}
              </div>
            ))}
          </div>

          <p className="mb-4 text-sm text-muted-foreground">
            Step {currentStep}: {steps[currentStep - 1].title}
          </p>

          {/* Step 1: Strategy Type */}
          {currentStep === 1 && (
            <div className="space-y-3">
              {strategyTypes.map((type) => (
                <button
                  key={type.value}
                  type="button"
                  onClick={() => {
                    const newTokenPair: [string, string] = type.value === 'stable-swap'
                      ? ['USDC', 'DAI']
                      : ['ETH', 'USDC']
                    setForm({ ...form, type: type.value, tokenPair: newTokenPair })
                    setAmountA('')
                    setAmountB('')
                  }}
                  className={`w-full rounded-lg border p-4 text-left transition-colors ${form.type === type.value
                      ? 'border-primary bg-primary/10'
                      : 'border-border hover:border-primary/50'
                    }`}
                >
                  <p className="font-medium">{type.label}</p>
                  <p className="text-sm text-muted-foreground">{type.description}</p>
                </button>
              ))}
            </div>
          )}

          {/* Step 2: Configuration */}
          {currentStep === 2 && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Token A</Label>
                  <Select
                    value={form.tokenPair[0]}
                    onValueChange={(v) => setForm({ ...form, tokenPair: [v, form.tokenPair[1]] })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {availableTokens.map((token) => (
                        <SelectItem key={token.symbol} value={token.symbol}>
                          {token.symbol}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Token B</Label>
                  <Select
                    value={form.tokenPair[1]}
                    onValueChange={(v) => setForm({ ...form, tokenPair: [form.tokenPair[0], v] })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {availableTokens.map((token) => (
                        <SelectItem key={token.symbol} value={token.symbol}>
                          {token.symbol}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="space-y-2">
                <Label>Fee Tier</Label>
                <div className="grid grid-cols-4 gap-2">
                  {feeTiers.map((tier) => (
                    <button
                      key={tier}
                      type="button"
                      onClick={() => setForm({ ...form, feeTier: tier })}
                      className={`rounded-lg border p-2 text-sm transition-colors ${form.feeTier === tier
                          ? 'border-primary bg-primary/10'
                          : 'border-border hover:border-primary/50'
                        }`}
                    >
                      {tier}%
                    </button>
                  ))}
                </div>
              </div>

            </div>
          )}

          {/* Step 3: Select Chains */}
          {currentStep === 3 && (
            <div className="space-y-3">
              {chains.map((chain) => (
                <label
                  key={chain.id}
                  className={`flex cursor-pointer items-center gap-3 rounded-lg border p-4 transition-colors ${form.chains.includes(chain.id)
                      ? 'border-primary bg-primary/10'
                      : 'border-border hover:border-primary/50'
                    }`}
                >
                  <Checkbox
                    checked={form.chains.includes(chain.id)}
                    onCheckedChange={(checked) => {
                      if (checked) {
                        setForm({ ...form, chains: [...form.chains, chain.id] })
                      } else {
                        setForm({ ...form, chains: form.chains.filter((c) => c !== chain.id) })
                      }
                    }}
                  />
                  <ChainIcon chain={chain} size="md" showTooltip={false} />
                  <span className="font-medium">{chain.name}</span>
                </label>
              ))}
            </div>
          )}

          {/* Step 4: Initial Liquidity */}
          {currentStep === 4 && (
            <div className="space-y-4">
              {/* Token A Input */}
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  {tokenA && <TokenIcon token={tokenA} size="sm" />}
                  <Label className="font-semibold">{form.tokenPair[0]}</Label>
                </div>
                <Input
                  type="number"
                  placeholder="0.00"
                  value={amountA}
                  onChange={(e) => handleAmountAChange(e.target.value)}
                  className="text-lg font-mono"
                />
              </div>

              {/* Plus indicator */}
              <div className="flex items-center justify-center">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/10 text-primary font-bold">
                  +
                </div>
              </div>

              {/* Token B Input */}
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  {tokenB && <TokenIcon token={tokenB} size="sm" />}
                  <Label className="font-semibold">{form.tokenPair[1]}</Label>
                </div>
                <Input
                  type="number"
                  placeholder="0.00"
                  value={amountB}
                  onChange={(e) => handleAmountBChange(e.target.value)}
                  className="text-lg font-mono"
                />
              </div>

              {/* A Parameter — StableSwap only */}
              {form.type === 'stable-swap' && (
                <div className="space-y-3 rounded-lg border border-border p-4">
                  <div className="flex items-center gap-2">
                    <Label className="font-semibold">Amplification (A)</Label>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Info className="h-4 w-4 text-muted-foreground cursor-help" />
                      </TooltipTrigger>
                      <TooltipContent side="top" className="max-w-[260px]">
                        <p>Controls curve flatness near the peg price.</p>
                        <p className="mt-1">Higher A = flatter curve = less slippage for pegged assets.</p>
                        <p className="mt-1 text-muted-foreground">0.1–0.5: volatile pairs · 0.5–0.8: soft pegs · 0.8–1.0: stablecoins</p>
                      </TooltipContent>
                    </Tooltip>
                    <span className="ml-auto font-mono text-sm font-semibold text-primary">
                      {aParameter.toFixed(1)}
                    </span>
                  </div>
                  <Slider
                    min={0.1}
                    max={1.0}
                    step={0.1}
                    value={[aParameter]}
                    onValueChange={([v]) => setAParameter(v)}
                  />
                  <div className="flex justify-between text-xs text-muted-foreground">
                    <span>0.1 (volatile)</span>
                    <span>1.0 (stable)</span>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Step 5: Review */}
          {currentStep === 5 && (
            <div className="space-y-4 rounded-lg border border-border bg-secondary/30 p-4">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Strategy Type</span>
                <span className="font-medium">
                  {strategyTypes.find((t) => t.value === form.type)?.label}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Token Pair</span>
                <span className="font-medium">
                  {form.tokenPair[0]}/{form.tokenPair[1]}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Fee Tier</span>
                <span className="font-medium">{form.feeTier}%</span>
              </div>
              {form.type === 'stable-swap' && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Amplification (A)</span>
                  <span className="font-medium">{aParameter.toFixed(1)}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-muted-foreground">Chains</span>
                <span className="font-medium">{form.chains.length} selected</span>
              </div>
              <div className="border-t border-border pt-4 mt-4">
                <p className="text-sm text-muted-foreground mb-2">Initial Liquidity</p>
                <div className="flex justify-between mb-1">
                  <span className="text-muted-foreground">{form.tokenPair[0]}</span>
                  <span className="font-medium">{amountA}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">{form.tokenPair[1]}</span>
                  <span className="font-medium">{amountB}</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Deploy Progress */}
        {isDeploying && (
          <Card className="mt-4 border-primary/30 bg-primary/5">
            <CardContent className="flex items-center gap-3 p-3">
              <Loader2 className="h-4 w-4 animate-spin text-primary" />
              <span className="text-sm font-medium">{DEPLOY_STEP_LABELS[deployStep]}</span>
            </CardContent>
          </Card>
        )}

        {/* Deploy Error */}
        {deployStep === 'error' && (
          <Card className="mt-4 border-destructive/30 bg-destructive/5">
            <CardContent className="p-3">
              <p className="text-sm text-destructive">{deployError || 'Deployment failed'}</p>
              <Button variant="outline" size="sm" className="mt-2" onClick={() => resetDeploy()}>
                Try Again
              </Button>
            </CardContent>
          </Card>
        )}

        {/* Deploy Success */}
        {deployStep === 'done' && deployResult && (
          <Card className="mt-4 border-green-500/30 bg-green-500/5">
            <CardContent className="p-3 space-y-1">
              <p className="text-sm font-medium text-green-500">Strategy deployed!</p>
              <p className="font-mono text-xs text-muted-foreground">Tx: {deployResult.txHash}</p>
              <Button variant="outline" size="sm" className="mt-2" onClick={() => { resetDeploy(); onOpenChange(false); setCurrentStep(1) }}>
                Done
              </Button>
            </CardContent>
          </Card>
        )}

        {/* Navigation Buttons */}
        <div className="mt-6 flex justify-between flex-shrink-0">
          <Button variant="outline" onClick={handleBack} disabled={currentStep === 1 || isDeploying}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>

          {currentStep < 5 ? (
            <Button onClick={handleNext} disabled={!canProceed()}>
              Next
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          ) : (
            <Button onClick={handleSubmit} disabled={isDeploying || deployStep === 'done'}>
              {isDeploying ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {DEPLOY_STEP_LABELS[deployStep] || 'Deploying...'}
                </>
              ) : (
                'Create Strategy'
              )}
            </Button>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
