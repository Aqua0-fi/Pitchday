import { describe, it, expect, afterEach } from 'vitest'
import { render, cleanup } from '@testing-library/react'
import { LoadingSpinner, LoadingCard, LoadingPage } from '../loading-spinner'

afterEach(() => {
  cleanup()
})

describe('LoadingSpinner', () => {
  it('renders without text by default', () => {
    const { container } = render(<LoadingSpinner />)
    expect(container.querySelector('svg')).toBeInTheDocument()
    expect(container.textContent).toBe('')
  })

  it('renders with custom text', () => {
    const { container } = render(<LoadingSpinner text="Please wait" />)
    expect(container.textContent).toContain('Please wait')
  })

  it('applies default md size class', () => {
    const { container } = render(<LoadingSpinner />)
    const svg = container.querySelector('svg')
    expect(svg?.className.baseVal || svg?.getAttribute('class') || '').toContain('h-6')
  })

  it('applies sm size class', () => {
    const { container } = render(<LoadingSpinner size="sm" />)
    const svg = container.querySelector('svg')
    expect(svg?.className.baseVal || svg?.getAttribute('class') || '').toContain('h-4')
  })

  it('applies lg size class', () => {
    const { container } = render(<LoadingSpinner size="lg" />)
    const svg = container.querySelector('svg')
    expect(svg?.className.baseVal || svg?.getAttribute('class') || '').toContain('h-8')
  })
})

describe('LoadingCard', () => {
  it('renders with loading text', () => {
    const { container } = render(<LoadingCard />)
    expect(container.textContent).toContain('Loading...')
  })
})

describe('LoadingPage', () => {
  it('renders with min height wrapper and loading text', () => {
    const { container } = render(<LoadingPage />)
    const wrapper = container.firstElementChild
    expect(wrapper?.getAttribute('class')).toContain('min-h-')
    expect(container.textContent).toContain('Loading...')
  })
})
