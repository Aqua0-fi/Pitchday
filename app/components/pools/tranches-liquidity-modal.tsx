"use client"

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { useWallet } from '@/contexts/wallet-context'
import { TrancheDeposit } from './tranches-panel'

interface TranchesLiquidityModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  poolPrice?: number
  hookAddress?: `0x${string}`
}

export function TranchesLiquidityModal({ open, onOpenChange, poolPrice = 2000, hookAddress }: TranchesLiquidityModalProps) {
  const { isConnected } = useWallet()

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-3">
            <div className="flex items-center gap-1.5 rounded-full bg-violet-500/10 px-3 py-1">
              <span className="text-sm font-bold text-violet-400">TrancheFi</span>
            </div>
            Provide Liquidity
          </DialogTitle>
          <DialogDescription>
            Choose a risk tranche and deposit. Senior gets priority fees + IL protection. Junior earns higher yield but absorbs IL.
          </DialogDescription>
        </DialogHeader>

        {isConnected ? (
          <TrancheDeposit poolPrice={poolPrice} hookAddress={hookAddress} />
        ) : (
          <div className="rounded-xl border border-dashed border-border/50 p-6 text-center">
            <p className="text-muted-foreground text-sm">Connect your wallet to deposit into a tranche.</p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
