'use client'

import { createContext, useContext } from 'react'

/**
 * Wallet context — pure React, zero heavy dependencies.
 *
 * This file deliberately does NOT import Privy, wagmi, or anything that
 * drags in WalletConnect/pino.  That keeps `useWallet()` safe to import
 * from any Client Component without bloating the SSR bundle.
 *
 * The actual provider that populates these values lives in
 * `contexts/wallet-provider.tsx` and is loaded client-only via
 * `next/dynamic` in `components/client-providers.tsx`.
 */

export interface WalletContextType {
  isConnected: boolean
  address: string | null
  chainId: number | undefined
  connect: () => void
  disconnect: () => void
  isConnecting: boolean
  // Privy extras
  email: string | null
  isAuthenticated: boolean
}

export const WalletContext = createContext<WalletContextType | null>(null)

export function useWallet() {
  const context = useContext(WalletContext)
  if (!context) {
    throw new Error('useWallet must be used within a WalletProvider')
  }
  return context
}
