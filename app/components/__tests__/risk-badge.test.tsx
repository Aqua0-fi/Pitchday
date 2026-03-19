import { describe, it, expect, afterEach } from 'vitest'
import { render, cleanup } from '@testing-library/react'
import { RiskBadge } from '../risk-badge'

afterEach(() => {
  cleanup()
})

describe('RiskBadge', () => {
  it('renders "Low Risk" for low level', () => {
    const { container } = render(<RiskBadge level="low" />)
    expect(container.textContent).toBe('Low Risk')
  })

  it('renders "Medium Risk" for medium level', () => {
    const { container } = render(<RiskBadge level="medium" />)
    expect(container.textContent).toBe('Medium Risk')
  })

  it('renders "High Risk" for high level', () => {
    const { container } = render(<RiskBadge level="high" />)
    expect(container.textContent).toBe('High Risk')
  })

  it('applies green classes for low risk', () => {
    const { container } = render(<RiskBadge level="low" />)
    const badge = container.querySelector('span')!
    expect(badge.getAttribute('class')).toContain('text-green-500')
  })

  it('applies yellow classes for medium risk', () => {
    const { container } = render(<RiskBadge level="medium" />)
    const badge = container.querySelector('span')!
    expect(badge.getAttribute('class')).toContain('text-yellow-500')
  })

  it('applies red classes for high risk', () => {
    const { container } = render(<RiskBadge level="high" />)
    const badge = container.querySelector('span')!
    expect(badge.getAttribute('class')).toContain('text-red-500')
  })
})
