import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen, cleanup, within } from '@testing-library/react'

afterEach(() => {
  cleanup()
})

// Mock next/navigation
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}))

// Mock next/link
vi.mock('next/link', () => ({
  default: ({ children, href }: { children: React.ReactNode; href: string }) => (
    <a href={href}>{children}</a>
  ),
}))

// Mock token-icon component
vi.mock('@/components/token-icon', () => ({
  TokenPairIcon: () => <div data-testid="token-pair-icon" />,
}))

import { StrategyCard, StrategyCardSkeleton } from '../strategy-card'
import type { Strategy } from '@/lib/types'

const mockStrategy: Strategy = {
  id: '1',
  name: 'ETH/USDC',
  type: 'constant-product',
  tokenPair: [
    { symbol: 'ETH', name: 'Ethereum', logo: '/crypto/ETH.png', decimals: 18, address: '0x...' },
    { symbol: 'USDC', name: 'USD Coin', logo: '/crypto/USDC.png', decimals: 6, address: '0x...' },
  ],
  apy: 5.8,
  tvl: 12500000,
  riskLevel: 'medium',
  supportedChains: [{ id: 'base', name: 'Base', logo: '/crypto/Base.png', color: '#0052FF' }],
  feeTier: 0.3,
  createdAt: '2025-01-15',
}

describe('StrategyCard', () => {
  it('renders token pair symbols', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('ETH')
    expect(container.textContent).toContain('USDC')
  })

  it('renders APY with one decimal', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('5.8%')
  })

  it('renders formatted TVL', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('$12.5M')
  })

  it('renders strategy type label', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('Constant Product')
  })

  it('renders chain name', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('Base')
  })

  it('renders fee tier', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('0.3%')
  })

  it('links to correct strategy detail page', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    const link = container.querySelector('a[href="/strategy/1"]')
    expect(link).toBeInTheDocument()
  })

  it('renders See Details button', () => {
    const { container } = render(<StrategyCard strategy={mockStrategy} />)
    expect(container.textContent).toContain('See Details')
  })
})

describe('StrategyCardSkeleton', () => {
  it('renders skeleton with pulse animations', () => {
    const { container } = render(<StrategyCardSkeleton />)
    const pulsingElements = container.querySelectorAll('.animate-pulse')
    expect(pulsingElements.length).toBeGreaterThan(0)
  })
})

describe('formatTVL via StrategyCard', () => {
  it('formats millions correctly', () => {
    const { container } = render(<StrategyCard strategy={{ ...mockStrategy, tvl: 12500000 }} />)
    expect(container.textContent).toContain('$12.5M')
  })

  it('formats thousands correctly', () => {
    const { container } = render(<StrategyCard strategy={{ ...mockStrategy, tvl: 5000 }} />)
    expect(container.textContent).toContain('$5K')
  })

  it('formats small values correctly', () => {
    const { container } = render(<StrategyCard strategy={{ ...mockStrategy, tvl: 500 }} />)
    expect(container.textContent).toContain('$500')
  })
})
