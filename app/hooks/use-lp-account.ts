import { useState, useCallback, useRef } from 'react'
import { keccak256, encodePacked, zeroAddress } from 'viem'
import type { Address } from 'viem'
import { useSignMessage, useReadContract, useSendTransaction, useWaitForTransactionReceipt } from 'wagmi'
import { api } from '@/lib/api-client'
import { ACCOUNT_FACTORY, ACCOUNT_FACTORY_ABI } from '@/lib/contracts'
import type { PrepareCalldataResponse } from '@/lib/api-types'

export type LpAccountStep =
  | 'idle'
  | 'signing'
  | 'creating'
  | 'confirming'
  | 'ready'
  | 'error'

/**
 * Hook to manage LP Account creation and detection.
 *
 * Flow:
 * 1. Sign chain-agnostic create-account message
 * 2. Derive salt = keccak256(signature)
 * 3. Check if AccountFactory.getAccount(owner, salt) != 0x0
 * 4. If not, call POST /lp/accounts/prepare-create → send tx
 * 5. Return LP Account address
 */
export function useLpAccount(owner?: string) {
  const [step, setStep] = useState<LpAccountStep>('idle')
  const [error, setError] = useState<string | null>(null)
  const [lpAccount, setLpAccount] = useState<Address | null>(null)
  const [createTxHash, setCreateTxHash] = useState<`0x${string}` | undefined>()

  // Store signature + salt across renders
  const signatureRef = useRef<`0x${string}` | null>(null)
  const saltRef = useRef<`0x${string}` | null>(null)

  const { signMessageAsync } = useSignMessage()
  const { sendTransactionAsync } = useSendTransaction()

  // Wait for creation tx receipt
  const { data: receipt } = useWaitForTransactionReceipt({ hash: createTxHash })

  // When receipt arrives during confirming step, extract LP Account address
  if (receipt && step === 'confirming') {
    // The AccountCreated event logs contain the new account address
    // Topic[0] = event sig, Topic[1] = owner, Topic[2] = account
    const accountCreatedLog = receipt.logs.find(
      (log) => log.topics.length >= 3
    )
    if (accountCreatedLog && accountCreatedLog.topics[2]) {
      const accountAddr = ('0x' + accountCreatedLog.topics[2].slice(26)) as Address
      setLpAccount(accountAddr)
      setStep('ready')
    } else {
      // Fallback: re-read from factory after creation
      setStep('ready')
    }
  }

  // Read existing account (only when we have a salt)
  const { refetch: refetchAccount } = useReadContract({
    address: ACCOUNT_FACTORY,
    abi: ACCOUNT_FACTORY_ABI,
    functionName: 'getAccount',
    args: owner && saltRef.current
      ? [owner as Address, saltRef.current]
      : undefined,
    query: { enabled: false }, // manual trigger only
  })

  /**
   * Ensure the user has an LP Account. If one exists, resolves immediately.
   * If not, signs message, creates account on-chain, and returns the address.
   */
  const ensureAccount = useCallback(async (chainId: number): Promise<Address> => {
    // If we already have the account, return it
    if (lpAccount) return lpAccount

    if (!owner) throw new Error('Wallet not connected')

    setError(null)

    try {
      // 1. Sign the create-account message
      setStep('signing')
      const messageHash = keccak256(
        encodePacked(
          ['string', 'address'],
          ['aqua0.create-account:', ACCOUNT_FACTORY]
        )
      )

      const signature = await signMessageAsync({
        message: { raw: messageHash },
      })
      signatureRef.current = signature

      // 2. Derive salt
      const salt = keccak256(signature)
      saltRef.current = salt

      // 3. Check if account exists on-chain
      const { data: existingAccount } = await refetchAccount()

      if (existingAccount && existingAccount !== zeroAddress) {
        setLpAccount(existingAccount as Address)
        setStep('ready')
        return existingAccount as Address
      }

      // 4. Account doesn't exist — create it
      setStep('creating')
      const { calldata } = await api.post<PrepareCalldataResponse>(
        'lp/accounts/prepare-create',
        { signature },
        { chainId: String(chainId) },
      )

      const hash = await sendTransactionAsync({
        to: calldata.to as Address,
        data: calldata.data as `0x${string}`,
      })

      // 5. Wait for confirmation
      setStep('confirming')
      setCreateTxHash(hash)

      // The receipt handler above will set lpAccount and step='ready'
      // But we need to return the address. Poll until ready.
      return new Promise<Address>((resolve, reject) => {
        const check = setInterval(() => {
          if (lpAccount) {
            clearInterval(check)
            resolve(lpAccount)
          }
        }, 500)

        // Timeout after 60s
        setTimeout(() => {
          clearInterval(check)
          reject(new Error('Account creation timed out'))
        }, 60_000)
      })
    } catch (err) {
      setStep('error')
      const msg = err instanceof Error ? err.message : 'Failed to create LP Account'
      setError(msg)
      throw err
    }
  }, [owner, lpAccount, signMessageAsync, sendTransactionAsync, refetchAccount])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setLpAccount(null)
    setCreateTxHash(undefined)
    signatureRef.current = null
    saltRef.current = null
  }, [])

  return {
    lpAccount,
    ensureAccount,
    reset,
    step,
    error,
    signature: signatureRef.current,
  }
}
