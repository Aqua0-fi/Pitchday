import { useState, useCallback } from 'react'
import { parseUnits } from 'viem'
import type { Address } from 'viem'
import { useWriteContract, useSendTransaction, useWaitForTransactionReceipt } from 'wagmi'
import { api } from '@/lib/api-client'
import { ERC20_ABI, BACKEND_CHAIN_IDS } from '@/lib/contracts'
import { useLpAccount } from './use-lp-account'
import type { StrategyBuildRequest, StrategyBuildResponse, PrepareCalldataResponse, PrepareShipResponse } from '@/lib/api-types'

export type DeployStep =
  | 'idle'
  | 'building'          // POST /strategies/build
  | 'ensuring-account'  // Check/create LP Account
  | 'transferring'      // ERC20.transfer tokens to LP Account
  | 'approving'         // POST /lp/accounts/:addr/prepare-approve
  | 'shipping'          // POST /lp/accounts/:addr/prepare-ship
  | 'confirming'        // Wait for ship tx receipt
  | 'done'
  | 'error'

export interface DeployParams {
  template: 'constantProduct' | 'stableSwap'
  token0: string          // token address
  token1: string          // token address
  token0Decimals: number
  token1Decimals: number
  amount0: string         // human-readable (e.g. "1.5")
  amount1: string         // human-readable (e.g. "2000")
  feeBps: number          // basis points (e.g. 30 = 0.3%)
  chainId: number
  // stableSwap extras
  linearWidth?: string
  rate0?: string
  rate1?: string
}

export interface DeployResult {
  strategyHash: string
  txHash: string
  lpAccount: string
}

export function useDeployStrategy(owner?: string) {
  const [step, setStep] = useState<DeployStep>('idle')
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<DeployResult | null>(null)
  const [shipTxHash, setShipTxHash] = useState<`0x${string}` | undefined>()

  const { ensureAccount, step: accountStep, reset: resetAccount } = useLpAccount(owner)
  const { writeContractAsync } = useWriteContract()
  const { sendTransactionAsync } = useSendTransaction()
  const { data: shipReceipt } = useWaitForTransactionReceipt({ hash: shipTxHash })

  // When ship receipt arrives, mark done
  if (shipReceipt && step === 'confirming') {
    setStep('done')
  }

  const execute = useCallback(async (params: DeployParams) => {
    const {
      template, token0, token1,
      token0Decimals, token1Decimals,
      amount0, amount1, feeBps, chainId,
      linearWidth, rate0, rate1,
    } = params

    setError(null)
    setResult(null)
    setShipTxHash(undefined)

    try {
      // Convert human-readable amounts to raw uint256 strings
      const amount0Raw = parseUnits(amount0, token0Decimals)
      const amount1Raw = parseUnits(amount1, token1Decimals)

      // 1. Ensure LP Account exists (sign + check + create if needed)
      setStep('ensuring-account')
      const lpAccount = await ensureAccount(chainId)

      // 2. Build strategy via backend
      setStep('building')
      const buildBody: StrategyBuildRequest = {
        template,
        maker: lpAccount,
        token0,
        token1,
        balance0: amount0Raw.toString(),
        balance1: amount1Raw.toString(),
        feeBps,
      }

      // Add stableSwap-specific fields
      if (template === 'stableSwap') {
        if (linearWidth) buildBody.linearWidth = linearWidth
        if (rate0) buildBody.rate0 = rate0
        if (rate1) buildBody.rate1 = rate1
      }

      const buildResult = await api.post<StrategyBuildResponse>(
        'strategies/build',
        buildBody,
        { chainId: String(chainId) },
      )

      // 3. Transfer tokens to LP Account
      setStep('transferring')
      await writeContractAsync({
        address: token0 as Address,
        abi: ERC20_ABI,
        functionName: 'transfer',
        args: [lpAccount, amount0Raw],
      })

      await writeContractAsync({
        address: token1 as Address,
        abi: ERC20_ABI,
        functionName: 'transfer',
        args: [lpAccount, amount1Raw],
      })

      // 4. Approve tokens on LP Account (LP Account → Aqua)
      setStep('approving')
      const approve0 = await api.post<PrepareCalldataResponse>(
        `lp/accounts/${lpAccount}/prepare-approve`,
        { token: token0, amount: amount0Raw.toString() },
      )
      await sendTransactionAsync({
        to: approve0.calldata.to as Address,
        data: approve0.calldata.data as `0x${string}`,
      })

      const approve1 = await api.post<PrepareCalldataResponse>(
        `lp/accounts/${lpAccount}/prepare-approve`,
        { token: token1, amount: amount1Raw.toString() },
      )
      await sendTransactionAsync({
        to: approve1.calldata.to as Address,
        data: approve1.calldata.data as `0x${string}`,
      })

      // 5. Ship strategy on-chain
      setStep('shipping')
      const shipResult = await api.post<PrepareShipResponse>(
        `lp/accounts/${lpAccount}/prepare-ship`,
        {
          strategyBytes: buildResult.strategyBytes,
          tokens: buildResult.tokens,
          amounts: buildResult.amounts,
        },
      )

      const hash = await sendTransactionAsync({
        to: shipResult.calldata.to as Address,
        data: shipResult.calldata.data as `0x${string}`,
      })

      // 6. Wait for confirmation
      setStep('confirming')
      setShipTxHash(hash)
      setResult({
        strategyHash: shipResult.strategyHash,
        txHash: hash,
        lpAccount,
      })

    } catch (err) {
      setStep('error')
      setError(err instanceof Error ? err.message : 'Strategy deployment failed')
    }
  }, [owner, ensureAccount, writeContractAsync, sendTransactionAsync])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setResult(null)
    setShipTxHash(undefined)
    resetAccount()
  }, [resetAccount])

  return {
    execute,
    reset,
    step,
    accountStep,
    error,
    result,
    shipReceipt,
  }
}
