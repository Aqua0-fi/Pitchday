"use client"

import { useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { ChainIcon } from '@/components/chain-icon'
import { chains } from '@/lib/mock-data'
import type { Chain } from '@/lib/types'
import { ChevronDown } from 'lucide-react'

interface ChainSelectorProps {
  selectedChain: Chain | null
  onSelectChain: (chain: Chain) => void
}

export function ChainSelector({ selectedChain, onSelectChain }: ChainSelectorProps) {
  const [open, setOpen] = useState(false)

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="ghost" size="sm" className="gap-1.5 h-8 px-2">
          {selectedChain ? (
            <>
              <ChainIcon chain={selectedChain} size="sm" />
              <span className="text-xs">{selectedChain.name}</span>
            </>
          ) : (
            <span className="text-xs text-muted-foreground">Chain</span>
          )}
          <ChevronDown className="h-3 w-3 text-muted-foreground" />
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-xs">
        <DialogHeader>
          <DialogTitle>Select chain</DialogTitle>
        </DialogHeader>

        <div className="space-y-1">
          {chains.map((chain) => (
            <button
              key={chain.id}
              type="button"
              onClick={() => {
                onSelectChain(chain)
                setOpen(false)
              }}
              className={`w-full flex items-center gap-3 rounded-lg p-3 text-left transition-colors hover:bg-secondary ${
                selectedChain?.id === chain.id ? 'bg-secondary' : ''
              }`}
            >
              <ChainIcon chain={chain} size="md" />
              <span className="font-medium">{chain.name}</span>
            </button>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  )
}
