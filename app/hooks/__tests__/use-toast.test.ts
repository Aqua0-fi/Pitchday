import { describe, it, expect } from 'vitest'
import { reducer } from '../use-toast'

type State = { toasts: Array<{ id: string; open?: boolean; [key: string]: unknown }> }

describe('use-toast reducer', () => {
  const emptyState: State = { toasts: [] }

  describe('ADD_TOAST', () => {
    it('adds a toast to empty state', () => {
      const result = reducer(emptyState, {
        type: 'ADD_TOAST',
        toast: { id: '1', title: 'Test' } as never,
      })
      expect(result.toasts).toHaveLength(1)
      expect(result.toasts[0].id).toBe('1')
    })

    it('respects TOAST_LIMIT of 1', () => {
      const stateWithOne: State = {
        toasts: [{ id: '1', title: 'First' } as never],
      }
      const result = reducer(stateWithOne, {
        type: 'ADD_TOAST',
        toast: { id: '2', title: 'Second' } as never,
      })
      // TOAST_LIMIT is 1, so only the newest toast should remain
      expect(result.toasts).toHaveLength(1)
      expect(result.toasts[0].id).toBe('2')
    })
  })

  describe('UPDATE_TOAST', () => {
    it('updates matching toast by id', () => {
      const state: State = {
        toasts: [{ id: '1', title: 'Old' } as never],
      }
      const result = reducer(state, {
        type: 'UPDATE_TOAST',
        toast: { id: '1', title: 'New' } as never,
      })
      expect(result.toasts[0].title).toBe('New')
    })

    it('does not affect non-matching toasts', () => {
      const state: State = {
        toasts: [{ id: '1', title: 'Keep' } as never],
      }
      const result = reducer(state, {
        type: 'UPDATE_TOAST',
        toast: { id: '999', title: 'New' } as never,
      })
      expect(result.toasts[0].title).toBe('Keep')
    })
  })

  describe('DISMISS_TOAST', () => {
    it('sets open to false for matching toast', () => {
      const state: State = {
        toasts: [{ id: '1', open: true } as never],
      }
      const result = reducer(state, {
        type: 'DISMISS_TOAST',
        toastId: '1',
      })
      expect(result.toasts[0].open).toBe(false)
    })

    it('sets open to false for all toasts when no id provided', () => {
      const state: State = {
        toasts: [{ id: '1', open: true } as never],
      }
      const result = reducer(state, {
        type: 'DISMISS_TOAST',
      })
      expect(result.toasts[0].open).toBe(false)
    })
  })

  describe('REMOVE_TOAST', () => {
    it('removes a specific toast by id', () => {
      const state: State = {
        toasts: [{ id: '1' } as never],
      }
      const result = reducer(state, {
        type: 'REMOVE_TOAST',
        toastId: '1',
      })
      expect(result.toasts).toHaveLength(0)
    })

    it('clears all toasts when no id provided', () => {
      const state: State = {
        toasts: [{ id: '1' } as never, { id: '2' } as never],
      }
      const result = reducer(state, {
        type: 'REMOVE_TOAST',
      })
      expect(result.toasts).toHaveLength(0)
    })
  })
})
