import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useIsMobile } from '../use-mobile'

describe('useIsMobile', () => {
  let listeners: Array<() => void> = []

  beforeEach(() => {
    listeners = []
    Object.defineProperty(window, 'innerWidth', {
      writable: true,
      configurable: true,
      value: 1024,
    })
    window.matchMedia = vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      addEventListener: (_: string, fn: () => void) => {
        listeners.push(fn)
      },
      removeEventListener: vi.fn(),
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }))
  })

  it('returns false when window width is >= 768', () => {
    Object.defineProperty(window, 'innerWidth', { value: 1024 })
    const { result } = renderHook(() => useIsMobile())
    expect(result.current).toBe(false)
  })

  it('returns true when window width is < 768', () => {
    Object.defineProperty(window, 'innerWidth', { value: 500 })
    const { result } = renderHook(() => useIsMobile())
    expect(result.current).toBe(true)
  })

  it('updates when window resizes', () => {
    Object.defineProperty(window, 'innerWidth', { value: 1024 })
    const { result } = renderHook(() => useIsMobile())
    expect(result.current).toBe(false)

    act(() => {
      Object.defineProperty(window, 'innerWidth', { value: 500 })
      listeners.forEach(fn => fn())
    })
    expect(result.current).toBe(true)
  })
})
