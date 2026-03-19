import type { Chain } from '@/lib/types'
import Image from 'next/image'

interface ChainIconProps {
  chain: Chain
  size?: 'sm' | 'md' | 'lg'
  showTooltip?: boolean
}

const sizeMap = {
  sm: { className: 'h-5 w-5', px: 20 },
  md: { className: 'h-6 w-6', px: 24 },
  lg: { className: 'h-8 w-8', px: 32 },
}

export function ChainIcon({ chain, size = 'md', showTooltip = true }: ChainIconProps) {
  const { className, px } = sizeMap[size]

  return (
    <div
      className={`relative flex-shrink-0 rounded-full overflow-hidden ${className}`}
      title={showTooltip ? chain.name : undefined}
    >
      <Image
        src={chain.logo}
        alt={`${chain.name} icon`}
        width={px}
        height={px}
        className="rounded-full"
        unoptimized
      />
    </div>
  )
}

interface ChainIconsProps {
  chains: Chain[]
  size?: 'sm' | 'md' | 'lg'
  max?: number
}

export function ChainIcons({ chains, size = 'sm', max = 4 }: ChainIconsProps) {
  const displayed = chains.slice(0, max)
  const remaining = chains.length - max

  return (
    <div className="flex -space-x-1.5">
      {displayed.map((chain) => (
        <ChainIcon key={chain.id} chain={chain} size={size} />
      ))}
      {remaining > 0 && (
        <div
          className={`flex items-center justify-center rounded-full bg-muted ${sizeMap[size].className}`}
          title={`+${remaining} more chains`}
        >
          <span className="text-[10px] font-medium text-muted-foreground">
            +{remaining}
          </span>
        </div>
      )}
    </div>
  )
}
