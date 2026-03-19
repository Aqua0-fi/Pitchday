'use client'

import dynamic from 'next/dynamic'
import type { ReactNode } from 'react'
import { Navbar } from '@/components/navbar'
import { Footer } from '@/components/footer'

/**
 * Dynamically import WalletProvider with SSR disabled.
 *
 * Privy → WalletConnect → pino → thread-stream ships test files that
 * reference dev-only modules (`tape`, `tap`, `why-is-node-running`, …).
 * When Turbopack builds the SSR bundle it walks into those test files and
 * fails because the dev deps aren't installed.
 *
 * Loading WalletProvider only on the client side avoids the SSR bundling
 * entirely, which is safe because wallet state is purely client-side.
 */
const WalletProvider = dynamic(
  () => import('@/contexts/wallet-provider').then((m) => m.WalletProvider),
  { ssr: false },
)

export function ClientProviders({ children }: { children: ReactNode }) {
  return (
    <WalletProvider>
      <Navbar />
      {children}
      <Footer />
    </WalletProvider>
  )
}
