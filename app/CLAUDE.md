# CLAUDE.md — Aqua0 Web App

This file provides context for AI assistants (Claude, Cursor, Copilot, etc.) working on the Aqua0 web application.

## Project Overview

The Aqua0 web app is the primary user interface for the cross-chain shared liquidity protocol. It enables:

- **Liquidity Providers**: Deploy capital across multiple chains, monitor positions, earn fees
- **Traders**: Execute cross-chain swaps with unified liquidity

## Quick Reference

### Commands

```bash
bun run dev      # Development server (localhost:3000)
bun run build    # Production build
bun run lint     # ESLint
bun run start    # Production server
```

### Key Files

| File                          | Purpose                     |
| ----------------------------- | --------------------------- |
| `app/page.tsx`                | Dashboard / Home page       |
| `app/deploy/page.tsx`         | Deploy liquidity flow       |
| `app/swap/page.tsx`           | Cross-chain swap interface  |
| `app/profile/page.tsx`        | User positions & history    |
| `lib/types.ts`                | TypeScript type definitions |
| `lib/api.ts`                  | API client functions        |
| `lib/wagmi.ts`                | Wallet configuration        |
| `contexts/wallet-context.tsx` | Wallet state provider       |

## Architecture

### Tech Stack

| Technology       | Why                                       |
| ---------------- | ----------------------------------------- |
| Next.js 16       | Server components, app router, optimal DX |
| TypeScript       | Type safety, better AI assistance         |
| Radix UI         | Accessible, unstyled primitives           |
| Tailwind CSS     | Utility-first, consistent styling         |
| wagmi/RainbowKit | Best-in-class wallet UX                   |
| TanStack Query   | Server state with caching                 |

### Page Structure

```
/                    → Dashboard (strategy overview, quick stats)
/deploy              → Deploy liquidity to strategies
/swap                → Cross-chain swap interface
/profile             → User positions, earnings, history
/strategy/[id]       → Individual strategy details
```

### Component Organization

```
components/
├── ui/              # Base primitives (button, card, input, etc.)
├── navbar.tsx       # Global navigation
├── footer.tsx       # Global footer
├── strategy-card.tsx
├── position-card.tsx
├── swap-form.tsx
└── ...
```

## Key Concepts

### Strategies

Strategies are trading configurations that LPs can deploy capital to:

```typescript
interface Strategy {
  id: string;
  name: string;
  type: "constant-product" | "stable-swap" | "concentrated-liquidity";
  tokenPair: [Token, Token];
  apy: number; // Historical APY
  tvl: number; // Total value locked
  riskLevel: "low" | "medium" | "high";
  supportedChains: Chain[];
}
```

### Positions

User's deployed capital across strategies:

```typescript
interface Position {
  id: string;
  strategyId: string;
  deployedAmount: number; // Initial deposit
  currentValue: number; // Current value
  earnings: number; // Fees earned
  apy: number; // Realized APY
  chains: Chain[]; // Active chains
}
```

### Swaps

Cross-chain token exchanges:

```typescript
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

## Common Patterns

### Loading States

```typescript
// Use Suspense boundaries in app router
import { Suspense } from 'react';
import { LoadingSpinner } from '@/components/ui/loading-spinner';

export default function Page() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <AsyncComponent />
    </Suspense>
  );
}
```

### Error Handling

```typescript
// Use error boundaries
'use client';

import { useEffect } from 'react';

export default function Error({
  error,
  reset,
}: {
  error: Error;
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="flex flex-col items-center gap-4 p-8">
      <h2>Something went wrong</h2>
      <button onClick={reset}>Try again</button>
    </div>
  );
}
```

### Wallet-Gated Content

```typescript
import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';

export function WalletRequired({ children }: { children: React.ReactNode }) {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center gap-4">
        <p>Please connect your wallet to continue</p>
        <ConnectButton />
      </div>
    );
  }

  return <>{children}</>;
}
```

### API Calls with TanStack Query

```typescript
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchStrategies, deployLiquidity } from "@/lib/api";

// Fetching data
export function useStrategies() {
  return useQuery({
    queryKey: ["strategies"],
    queryFn: fetchStrategies,
  });
}

// Mutations
export function useDeployLiquidity() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: deployLiquidity,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["positions"] });
    },
  });
}
```

### Form Handling

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import * as z from 'zod';

const schema = z.object({
  amount: z.string().min(1, 'Amount required'),
});

export function DepositForm() {
  const form = useForm({
    resolver: zodResolver(schema),
  });

  const onSubmit = async (data) => {
    // Handle deposit
  };

  return (
    <form onSubmit={form.handleSubmit(onSubmit)}>
      {/* Form fields */}
    </form>
  );
}
```

### Security Considerations

#### Input Validation

```typescript
// Always validate user inputs
const amount = parseFloat(inputValue);
if (isNaN(amount) || amount <= 0) {
  setError("Please enter a valid amount");
  return;
}

// Validate addresses
import { isAddress } from "viem";
if (!isAddress(tokenAddress)) {
  setError("Invalid token address");
  return;
}
```

#### Transaction Safety

```typescript
// Always show confirmation before transactions
const [showConfirm, setShowConfirm] = useState(false);

// Include slippage warnings
if (priceImpact > 5) {
  return (
    <Alert variant="destructive">
      High price impact: {priceImpact}%
    </Alert>
  );
}
```

## Development Guidelines

### Code Style

#### Component Structure

```typescript
// components/feature/my-component.tsx
'use client'; // Only if client-side interactivity needed

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

interface MyComponentProps {
  title: string;
  onAction?: () => void;
  className?: string;
}

export function MyComponent({
  title,
  onAction,
  className
}: MyComponentProps) {
  const [isLoading, setIsLoading] = useState(false);

  const handleAction = async () => {
    setIsLoading(true);
    try {
      await onAction?.();
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className={cn('p-4 rounded-lg', className)}>
      <h2 className="text-lg font-semibold">{title}</h2>
      <Button onClick={handleAction} disabled={isLoading}>
        {isLoading ? 'Loading...' : 'Take Action'}
      </Button>
    </div>
  );
}
```

#### Naming Conventions

- **Components**: PascalCase (`StrategyCard`, `SwapInterface`)
- **Files**: kebab-case (`strategy-card.tsx`, `swap-interface.tsx`)
- **Hooks**: camelCase with `use` prefix (`usePositions`, `useSwapQuote`)
- **Types**: PascalCase with descriptive names (`Strategy`, `Position`, `SwapRoute`)
- **Utils**: camelCase (`formatCurrency`, `truncateAddress`)

#### Import Order

```typescript
// 1. React/Next.js
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";

// 2. External libraries
import { useAccount } from "wagmi";
import { formatUnits } from "viem";

// 3. Internal components
import { Button } from "@/components/ui/button";
import { StrategyCard } from "@/components/strategy-card";

// 4. Internal utilities
import { cn } from "@/lib/utils";
import type { Strategy } from "@/lib/types";
```

### Adding Features

1. **Plan the UI** — Sketch component structure
2. **Define types** — Add to `lib/types.ts`
3. **Create API functions** — Add to `lib/api.ts`
4. **Build components** — Start from primitives
5. **Add to page** — Integrate into app router
6. **Test** — Verify all states (loading, error, success)

### Styling Guidelines

#### Tailwind Best Practices

```typescript
// Use cn() for conditional classes
import { cn } from '@/lib/utils';

<div className={cn(
  'rounded-lg border p-4',
  isActive && 'border-primary bg-primary/10',
  className
)}>

// Use consistent spacing scale
// p-1 (4px), p-2 (8px), p-4 (16px), p-6 (24px), p-8 (32px)

// Use semantic colors
// text-foreground, text-muted-foreground
// bg-background, bg-card, bg-muted
// border-border, border-input
```

#### Responsive Design

```typescript
// Mobile-first approach
<div className="
  flex flex-col gap-4
  md:flex-row md:gap-6
  lg:gap-8
">
  <aside className="w-full md:w-64 lg:w-80">
    {/* Sidebar */}
  </aside>
  <main className="flex-1">
    {/* Content */}
  </main>
</div>
```

### State Management

- **Server state**: TanStack Query
- **Form state**: react-hook-form
- **UI state**: React useState/useReducer
- **Global state**: React Context (wallet, theme)

## Wallet Integration

### Supported Wallets

Via RainbowKit:

- MetaMask
- WalletConnect
- Coinbase Wallet
- Rainbow
- And more...

### Chain Support

Configured in `lib/wagmi.ts`:

- Base (primary)
- Base Sepolia (testnet)
- Arbitrum
- Ethereum Mainnet

### Common Hooks

```typescript
import { useAccount, useBalance, useChainId, useSwitchChain } from "wagmi";

const { address, isConnected } = useAccount();
const { data: balance } = useBalance({ address });
const chainId = useChainId();
const { switchChain } = useSwitchChain();
```

## Backend Integration

Currently uses mock data in `lib/mock-data.ts`. Will connect to NestJS/Hono backend:

### API Endpoints (Planned)

```
GET  /api/v1/strategies          # List all strategies
GET  /api/v1/strategies/:id      # Strategy details
GET  /api/v1/positions           # User's positions
POST /api/v1/positions           # Create position
POST /api/v1/swap/quote          # Get swap quote
POST /api/v1/swap/route          # Get optimal route
GET  /api/v1/analytics/tvl       # Protocol TVL
```

## Testing (TDD Required)

### Test-Driven Development Workflow

**Default to writing tests first** for any meaningful feature or bug fix:

1. **Write the test** — Define expected behavior (inputs, outputs, edge cases)
2. **Watch it fail** — Confirm the test fails for the right reason
3. **Implement the code** — Write minimal code to make the test pass
4. **Refactor** — Clean up while keeping tests green

### When to Write Tests

- **New components**: Test rendering, props, user interactions
- **Custom hooks**: Test state changes, side effects, error handling
- **API functions**: Test request/response handling, error cases
- **Utilities**: Test edge cases, type coercion, validation logic

### Testing Patterns

```typescript
// Component test example (React Testing Library)
import { render, screen, fireEvent } from '@testing-library/react';
import { StrategyCard } from '@/components/strategy-card';

describe('StrategyCard', () => {
  const mockStrategy = {
    id: '1',
    name: 'USDC-ETH',
    apy: 12.5,
    tvl: 1000000,
  };

  it('should display strategy name and APY', () => {
    render(<StrategyCard strategy={mockStrategy} />);

    expect(screen.getByText('USDC-ETH')).toBeInTheDocument();
    expect(screen.getByText('12.5%')).toBeInTheDocument();
  });

  it('should call onSelect when clicked', () => {
    const onSelect = jest.fn();
    render(<StrategyCard strategy={mockStrategy} onSelect={onSelect} />);

    fireEvent.click(screen.getByRole('button'));
    expect(onSelect).toHaveBeenCalledWith('1');
  });
});
```

```typescript
// Hook test example
import { renderHook, waitFor } from "@testing-library/react";
import { useStrategies } from "@/hooks/use-strategies";

describe("useStrategies", () => {
  it("should fetch and return strategies", async () => {
    const { result } = renderHook(() => useStrategies());

    expect(result.current.isLoading).toBe(true);

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.data).toHaveLength(3);
  });

  it("should handle errors gracefully", async () => {
    // Mock API failure
    const { result } = renderHook(() => useStrategies());

    await waitFor(() => {
      expect(result.current.error).toBeDefined();
    });
  });
});
```

### Test Commands

```bash
bun test                 # Run all tests
bun test --watch         # Watch mode
bun test --coverage      # Coverage report
bun test ComponentName   # Run specific test file
```

### Checklist Before Committing

- [ ] `bun run lint` passes
- [ ] `bun x tsc --noEmit` passes (no type errors)
- [ ] `bun test` passes
- [ ] **Tests written first** for new features/fixes
- [ ] All pages render correctly
- [ ] Loading states display properly
- [ ] Error handling works
- [ ] Mobile responsive
- [ ] Wallet flows functional

## Common Tasks

### Adding a New Page

1. Create `app/[page-name]/page.tsx`
2. Add loading state in `app/[page-name]/loading.tsx`
3. Add error boundary in `app/[page-name]/error.tsx` (optional)
4. Update navigation in `components/navbar.tsx`

### Adding a New Component

1. Create file in `components/` (or `components/ui/` for primitives)
2. Define props interface
3. Implement with proper TypeScript types
4. Add to component index if shared widely

### Adding a New API Function

1. Add function to `lib/api.ts`
2. Define request/response types in `lib/types.ts`
3. Create hook in `hooks/` using TanStack Query
4. Handle loading/error states in consuming components

### Adding a New Hook

```typescript
// hooks/use-my-hook.ts
import { useState, useEffect } from "react";

export function useMyHook(param: string) {
  const [data, setData] = useState<MyType | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    // Implementation
  }, [param]);

  return { data, isLoading, error };
}
```

## External Dependencies

| Package        | Purpose            | Docs                                             |
| -------------- | ------------------ | ------------------------------------------------ |
| wagmi          | Ethereum hooks     | [wagmi.sh](https://wagmi.sh)                     |
| RainbowKit     | Wallet UI          | [rainbowkit.com](https://www.rainbowkit.com)     |
| viem           | Ethereum utilities | [viem.sh](https://viem.sh)                       |
| TanStack Query | Server state       | [tanstack.com/query](https://tanstack.com/query) |
| Radix UI       | Primitives         | [radix-ui.com](https://www.radix-ui.com)         |
| Tailwind CSS   | Styling            | [tailwindcss.com](https://tailwindcss.com)       |

## Related Files

- `README.md` — Full documentation
- `../contracts/` — Smart contract code
- `../backend/` — API backend (NestJS/Hono)
