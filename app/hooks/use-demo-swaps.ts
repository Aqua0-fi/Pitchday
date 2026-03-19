import { useState, useCallback } from 'react'
import { useWriteContract, usePublicClient, useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import { TRANCHES_POOLS, TRANCHES_POOL_KEY, ERC20_ABI, V4_ROUTER_ABI, SWAP_VM_ROUTER } from '@/lib/contracts'
import type { Address } from 'viem'

const MUSDC = TRANCHES_POOL_KEY.currency0
const MWETH = TRANCHES_POOL_KEY.currency1

const MIN_SQRT_PRICE = BigInt('4295128740')
const MAX_SQRT_PRICE = BigInt('1461446703485210103287273052203988822378723970341')

interface DemoSwap {
  label: string
  poolIndex: number // index into TRANCHES_POOLS
  zeroForOne: boolean // true = mUSDC→mWETH, false = mWETH→mUSDC
  amount: string // human readable
  token: 'mUSDC' | 'mWETH'
}

const DEMO_SWAPS: DemoSwap[] = [
  { label: '500 mUSDC → mWETH via Conservative (0.05%)', poolIndex: 0, zeroForOne: true, amount: '500', token: 'mUSDC' },
  { label: '0.1 mWETH → mUSDC via Standard (0.30%)', poolIndex: 1, zeroForOne: false, amount: '0.1', token: 'mWETH' },
  { label: '1000 mUSDC → mWETH via Aggressive (1.00%)', poolIndex: 2, zeroForOne: true, amount: '1000', token: 'mUSDC' },
  { label: '0.05 mWETH → mUSDC via Traditional (0.30%)', poolIndex: 3, zeroForOne: false, amount: '0.05', token: 'mWETH' },
  { label: '200 mUSDC → mWETH via Conservative (0.05%)', poolIndex: 0, zeroForOne: true, amount: '200', token: 'mUSDC' },
]

export function useDemoSwaps() {
  const [isRunning, setIsRunning] = useState(false)
  const [currentSwap, setCurrentSwap] = useState(0)
  const [results, setResults] = useState<string[]>([])
  const [error, setError] = useState<string | null>(null)

  const { writeContractAsync } = useWriteContract()
  const publicClient = usePublicClient()
  const { address } = useAccount()

  const run = useCallback(async () => {
    if (!address || !publicClient) return
    setIsRunning(true)
    setResults([])
    setError(null)

    try {
      // Approve router for both tokens (infinite)
      const maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935n

      setCurrentSwap(-1)
      setResults(r => [...r, 'Approving mUSDC...'])
      const h1 = await writeContractAsync({
        address: MUSDC,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [SWAP_VM_ROUTER as Address, maxUint],
      })
      await publicClient.waitForTransactionReceipt({ hash: h1 })

      setResults(r => [...r, 'Approving mWETH...'])
      const h2 = await writeContractAsync({
        address: MWETH,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [SWAP_VM_ROUTER as Address, maxUint],
      })
      await publicClient.waitForTransactionReceipt({ hash: h2 })

      // Execute 5 swaps
      for (let i = 0; i < DEMO_SWAPS.length; i++) {
        const swap = DEMO_SWAPS[i]
        const pool = TRANCHES_POOLS[swap.poolIndex]
        setCurrentSwap(i)
        setResults(r => [...r, `Swap ${i + 1}/5: ${swap.label}`])

        const amountIn = parseUnits(swap.amount, 18)

        const hash = await writeContractAsync({
          address: SWAP_VM_ROUTER as Address,
          abi: V4_ROUTER_ABI,
          functionName: 'swap',
          args: [
            {
              currency0: MUSDC,
              currency1: MWETH,
              fee: pool.fee,
              tickSpacing: pool.tickSpacing,
              hooks: pool.hook as Address,
            },
            {
              zeroForOne: swap.zeroForOne,
              amountSpecified: -amountIn,
              sqrtPriceLimitX96: swap.zeroForOne ? MIN_SQRT_PRICE : MAX_SQRT_PRICE,
            },
            {
              takeClaims: false,
              settleUsingBurn: false,
            },
            '0x',
          ],
        })
        await publicClient.waitForTransactionReceipt({ hash })
        setResults(r => [...r, `  ✓ Confirmed: ${hash.slice(0, 10)}...`])
      }

      setResults(r => [...r, '=== All 5 swaps complete ==='])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Demo swap failed')
    } finally {
      setIsRunning(false)
      setCurrentSwap(0)
    }
  }, [address, publicClient, writeContractAsync])

  return { run, isRunning, currentSwap, results, error, totalSwaps: DEMO_SWAPS.length }
}
