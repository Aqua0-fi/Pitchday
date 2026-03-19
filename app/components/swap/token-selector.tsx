"use client"

import { useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { TokenIcon } from '@/components/token-icon'
import { useMappedTokens } from '@/hooks/use-mapped-tokens'
import type { Token } from '@/lib/types'
import { ChevronDown, Search, Loader2 } from 'lucide-react'

interface TokenSelectorProps {
  selectedToken: Token | null
  onSelectToken: (token: Token) => void
  excludeToken?: Token | null
  chain?: string
}

export function TokenSelector({ selectedToken, onSelectToken, excludeToken, chain }: TokenSelectorProps) {
  const [open, setOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const { data: tokens, isLoading } = useMappedTokens(chain)

  const filteredTokens = tokens.filter((token) => {
    const matchesSearch =
      token.symbol.toLowerCase().includes(searchQuery.toLowerCase()) ||
      token.name.toLowerCase().includes(searchQuery.toLowerCase())
    const isNotExcluded = !excludeToken || token.symbol !== excludeToken.symbol
    return matchesSearch && isNotExcluded
  })

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" className="gap-2 min-w-[140px] justify-between bg-transparent">
          {selectedToken ? (
            <>
              <TokenIcon token={selectedToken} size="sm" />
              <span className="font-medium">{selectedToken.symbol}</span>
            </>
          ) : (
            <span className="text-muted-foreground">Select token</span>
          )}
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Select a token</DialogTitle>
        </DialogHeader>

        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search by name or symbol..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>

        <div className="max-h-64 overflow-y-auto space-y-1">
          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </div>
          ) : filteredTokens.length === 0 ? (
            <p className="text-center text-sm text-muted-foreground py-4">
              No tokens found
            </p>
          ) : (
            filteredTokens.map((token) => (
              <button
                key={token.address}
                type="button"
                onClick={() => {
                  onSelectToken(token)
                  setOpen(false)
                  setSearchQuery('')
                }}
                className={`w-full flex items-center gap-3 rounded-lg p-3 text-left transition-colors hover:bg-secondary ${
                  selectedToken?.symbol === token.symbol ? 'bg-secondary' : ''
                }`}
              >
                <TokenIcon token={token} size="lg" />
                <div>
                  <p className="font-medium">{token.symbol}</p>
                  <p className="text-sm text-muted-foreground">{token.name}</p>
                </div>
              </button>
            ))
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
