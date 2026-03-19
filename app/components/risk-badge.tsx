import type { RiskLevel } from '@/lib/types'

interface RiskBadgeProps {
  level: RiskLevel
}

const riskConfig = {
  low: {
    label: 'Low Risk',
    className: 'bg-green-500/10 text-green-500 border-green-500/20',
  },
  medium: {
    label: 'Medium Risk',
    className: 'bg-yellow-500/10 text-yellow-500 border-yellow-500/20',
  },
  high: {
    label: 'High Risk',
    className: 'bg-red-500/10 text-red-500 border-red-500/20',
  },
}

export function RiskBadge({ level }: RiskBadgeProps) {
  const config = riskConfig[level]
  
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium ${config.className}`}>
      {config.label}
    </span>
  )
}
