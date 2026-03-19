# Aqua0 Web Application

The primary user interface for the Aqua0 cross-chain shared liquidity protocol. This application enables liquidity providers to manage strategies across multiple blockchains and traders to execute cross-chain swaps.

## Overview

Aqua0 Web App serves two primary user types:

1. **Liquidity Providers (LPs)**: Browse strategies, deposit capital, monitor positions, and manage cross-chain liquidity
2. **Traders**: Execute cross-chain swaps with unified liquidity and reduced slippage

## Technology Stack

| Layer         | Technology           | Purpose                             |
| ------------- | -------------------- | ----------------------------------- |
| Framework     | Next.js 16           | React server components, app router |
| Language      | TypeScript 5         | Type safety                         |
| UI Components | Radix UI + shadcn/ui | Accessible, customizable components |
| Styling       | Tailwind CSS 4       | Utility-first CSS                   |
| Wallet        | wagmi + RainbowKit   | Ethereum wallet connection          |
| State         | TanStack Query       | Server state management             |
| Analytics     | Vercel Analytics     | Usage tracking                      |

## Quick Start

```bash
# Install dependencies
bun install

# Start development server
bun run dev

# Build for production
bun run build

# Start production server
bun run start

# Lint code
bun run lint
```

## Project Structure

```
web-app/
├── app/                    # Next.js App Router pages
│   ├── page.tsx            # Dashboard / Home
│   ├── layout.tsx          # Root layout with providers
│   ├── deploy/             # Deploy liquidity flow
│   │   └── page.tsx
│   ├── swap/               # Cross-chain swap interface
│   │   └── page.tsx
│   ├── profile/            # User profile & positions
│   │   └── page.tsx
│   └── strategy/[id]/      # Individual strategy details
│       └── page.tsx
├── components/             # React components
│   ├── ui/                 # shadcn/ui base components
│   ├── theme-provider.tsx  # Dark/light mode
│   └── ...                 # Feature components
├── contexts/               # React contexts
│   └── wallet-context.tsx  # Wallet connection state
├── hooks/                  # Custom React hooks
├── lib/                    # Utilities and types
│   ├── api.ts              # API client functions
│   ├── types.ts            # TypeScript interfaces
│   ├── wagmi.ts            # wagmi/RainbowKit config
│   ├── utils.ts            # Utility functions
│   └── mock-data.ts        # Mock data for development
├── public/                 # Static assets
├── styles/                 # Global styles
└── package.json            # Dependencies and scripts
```

## Key Features

### Strategy Browser

Browse available liquidity strategies with filtering by:

- Chain (Ethereum, Base, Arbitrum, etc.)
- APY range
- Risk level (Low, Medium, High)
- Strategy type (Constant Product, Stable Swap, Concentrated Liquidity)

### Liquidity Deployment

1. Select strategy from browser
2. View strategy details and historical performance
3. Enter deposit amount
4. Approve token spending (ERC-20)
5. Confirm deposit transaction
6. Monitor position in profile

### Cross-Chain Swap

1. Select input/output tokens
2. Choose source/destination chains
3. Enter swap amount
4. View route, price impact, and fees
5. Execute atomic swap via LayerZero
6. Track status across chains

### User Profile

- View all active positions
- Monitor total vTVL (Virtual Total Value Locked)
- Track earnings by strategy
- View transaction history
- Manage rebalancer authorization

## Configuration

### Environment Variables

Create `.env.local` for local development:

```env
# RPC Endpoints (required)
NEXT_PUBLIC_ALCHEMY_ID=your_alchemy_key
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_walletconnect_id

# API Backend (when available)
NEXT_PUBLIC_API_URL=http://localhost:3001

# Feature Flags
NEXT_PUBLIC_ENABLE_TESTNET=true
NEXT_PUBLIC_ENABLE_MAINNET=false
```

### Supported Chains

Currently supported (configurable in `lib/wagmi.ts`):

- Base (mainnet + Sepolia testnet)
- Arbitrum
- Ethereum Mainnet

## Development

### Adding a New Page

1. Create directory in `app/` with `page.tsx`
2. Add loading state in `loading.tsx` (optional)
3. Add route to navigation in `components/navbar.tsx`

### Adding a New Component

1. Create component in `components/`
2. Use Radix UI primitives from `components/ui/`
3. Apply Tailwind classes for styling
4. Export from component index if shared

### Working with the API

The API client is in `lib/api.ts`. Currently uses mock data; will connect to NestJS/Hono backend:

```typescript
import { fetchStrategies, deployLiquidity, fetchSwapQuote } from "@/lib/api";

// Fetch all strategies
const strategies = await fetchStrategies();

// Deploy liquidity
const result = await deployLiquidity({
  strategyId: "strategy-id",
  amount: "1000000000", // 1000 USDC (6 decimals)
  token: "0x...",
});

// Get swap quote
const quote = await fetchSwapQuote({
  tokenIn: "0x...",
  tokenOut: "0x...",
  amountIn: "1000000000",
  chainIn: "base",
  chainOut: "arbitrum",
});
```

## Type Definitions

Key types are defined in `lib/types.ts`:

```typescript
interface Strategy {
  id: string;
  name: string;
  type: "constant-product" | "stable-swap" | "concentrated-liquidity";
  tokenPair: [Token, Token];
  apy: number;
  tvl: number;
  riskLevel: "low" | "medium" | "high";
  supportedChains: Chain[];
  feeTier: number;
}

interface Position {
  id: string;
  strategyId: string;
  deployedAmount: number;
  currentValue: number;
  earnings: number;
  apy: number;
  chains: Chain[];
}

interface SwapRoute {
  tokenIn: Token;
  tokenOut: Token;
  amountIn: string;
  amountOut: string;
  priceImpact: number;
  route: RouteStep[];
  estimatedGas: string;
}
```

## Wallet Integration

Wallet connection is handled via wagmi + RainbowKit:

```typescript
import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';

// Use ConnectButton for UI
<ConnectButton />

// Or programmatically
const { address, isConnected } = useAccount();
const { connect, connectors } = useConnect();
const { disconnect } = useDisconnect();
```

## Testing

```bash
# Run ESLint
bun run lint

# Type check
bun x tsc --noEmit
```

## Deployment

The application is designed for Vercel deployment:

```bash
# Build and verify
bun run build

# Deploy to Vercel
vercel deploy
```

## Related Documentation

- `CLAUDE.md` — AI assistant context
- `AGENTS.md` — AI workflow guidelines
- `../contracts/README.md` — Smart contract documentation
- `../docs/` — Full protocol documentation site
