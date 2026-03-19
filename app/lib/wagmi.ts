import { http } from 'wagmi'
import { baseSepolia, base } from 'wagmi/chains'
import { unichainSepolia } from 'viem/chains'
import { createConfig } from '@privy-io/wagmi'
import type { Chain } from 'viem'

// Custom local devnet chain — 696969 avoids Otterscan misidentifying as GoChain (1337/31337)
export const localAqua0Chain: Chain = {
  id: 696969,
  name: 'Aqua0 Local Devnet',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['http://localhost:8545'] } },
}

export const config = createConfig({
  chains: [base, baseSepolia, unichainSepolia, localAqua0Chain],
  transports: {
    [base.id]: http(),
    [baseSepolia.id]: http(),
    [unichainSepolia.id]: http(),
    [localAqua0Chain.id]: http('http://localhost:8545'),
  },
})
