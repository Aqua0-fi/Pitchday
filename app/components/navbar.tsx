"use client"

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { useWallet } from '@/contexts/wallet-context'
import { Menu, X, ChevronDown, Wallet, LogOut } from 'lucide-react'
import { useState } from 'react'
import Image from 'next/image'
import { useAccount, useSwitchChain } from 'wagmi'

// Map chain IDs to our local icons
const chainIcons: Record<number, string> = {
  8453: '/crypto/Base.png',       // Base mainnet
  84532: '/crypto/Base.png',      // Base Sepolia
  1301: '/crypto/Unichain.png',   // Unichain Sepolia
}

const chainNames: Record<number, string> = {
  8453: 'Base',
  84532: 'Base Sepolia',
  1301: 'Unichain Sepolia',
}

function truncateAddress(address: string): string {
  return `${address.slice(0, 6)}\u2026${address.slice(-4)}`
}

const navLinks = [
  { href: '/', label: 'Pools' },
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/swap', label: 'Swap' },
]

export function Navbar() {
  const pathname = usePathname()
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const { isConnected, address, connect, disconnect, chainId } = useWallet()
  const { chains } = useSwitchChain()
  const [chainDropdownOpen, setChainDropdownOpen] = useState(false)
  const { switchChain } = useSwitchChain()

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border bg-background/80 backdrop-blur-sm">
      <nav className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <Image
            src="/aqua0-logo.png"
            alt="Aqua0 Logo"
            width={32}
            height={32}
            className="h-8 w-8"
            unoptimized
          />
          <span className="text-lg font-bold tracking-tight">AQUA0</span>
        </Link>

        {/* Desktop Navigation */}
        <div className="hidden items-center gap-1 md:flex">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${pathname === link.href
                ? 'bg-secondary text-foreground'
                : 'text-muted-foreground hover:bg-secondary/50 hover:text-foreground'
                }`}
            >
              {link.label}
            </Link>
          ))}
        </div>

        {/* Wallet Connection */}
        <div className="flex items-center gap-3">
          {!isConnected ? (
            <Button onClick={connect} size="sm">
              <Wallet className="mr-2 h-4 w-4" />
              Log in
            </Button>
          ) : (
            <div className="flex items-center gap-2">
              {/* Chain selector */}
              <div className="relative">
                <button
                  onClick={() => setChainDropdownOpen(!chainDropdownOpen)}
                  className="flex items-center gap-1.5 rounded-lg border border-border bg-secondary/50 px-2.5 py-1.5 text-sm font-medium transition-colors hover:bg-secondary"
                >
                  {chainId && chainIcons[chainId] ? (
                    <Image
                      src={chainIcons[chainId]}
                      alt={chainNames[chainId] ?? 'Chain'}
                      width={18}
                      height={18}
                      className="rounded-full"
                      unoptimized
                    />
                  ) : null}
                  <span className="hidden sm:inline">{chainId ? chainNames[chainId] ?? `Chain ${chainId}` : 'Unknown'}</span>
                  <ChevronDown className="h-3 w-3 text-muted-foreground" />
                </button>

                {/* Chain dropdown */}
                {chainDropdownOpen && (
                  <div className="absolute right-0 top-full mt-1 z-50 min-w-[180px] rounded-lg border border-border bg-background p-1 shadow-lg">
                    {chains.map((chain) => (
                      <button
                        key={chain.id}
                        onClick={() => {
                          switchChain({ chainId: chain.id })
                          setChainDropdownOpen(false)
                        }}
                        className={`flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors hover:bg-secondary ${chainId === chain.id ? 'bg-secondary/50 font-medium' : 'text-muted-foreground'
                          }`}
                      >
                        {chainIcons[chain.id] && (
                          <Image
                            src={chainIcons[chain.id]}
                            alt={chain.name}
                            width={16}
                            height={16}
                            className="rounded-full"
                            unoptimized
                          />
                        )}
                        {chain.name}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Account */}
              <button
                onClick={disconnect}
                className="flex items-center gap-2 rounded-lg border border-border bg-secondary/50 px-3 py-1.5 text-sm font-medium transition-colors hover:bg-secondary"
              >
                <span className="h-2 w-2 rounded-full bg-emerald-500" />
                {address ? truncateAddress(address) : '...'}
              </button>
            </div>
          )}

          {/* Mobile Menu Button */}
          <Button
            variant="ghost"
            size="icon"
            className="md:hidden"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          >
            {mobileMenuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </Button>
        </div>
      </nav>

      {/* Mobile Navigation */}
      {mobileMenuOpen && (
        <div className="border-t border-border bg-background p-4 md:hidden">
          <div className="flex flex-col gap-2">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                onClick={() => setMobileMenuOpen(false)}
                className={`rounded-lg px-4 py-3 text-sm font-medium transition-colors ${pathname === link.href
                  ? 'bg-secondary text-foreground'
                  : 'text-muted-foreground hover:bg-secondary/50 hover:text-foreground'
                  }`}
              >
                {link.label}
              </Link>
            ))}
          </div>
        </div>
      )}
    </header>
  )
}
