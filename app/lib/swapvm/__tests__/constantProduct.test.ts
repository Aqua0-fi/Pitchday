import { describe, it, expect } from 'vitest'
import { buildConstantProductProgram } from '../constantProduct'

describe('buildConstantProductProgram', () => {
  it('generates correct bytecode for USDC/DAI (0.3% fee)', () => {
    const bytecode = buildConstantProductProgram(
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
      '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI
      10_000n * 10n ** 6n,  // 10k USDC (6 decimals)
      10_000n * 10n ** 18n, // 10k DAI (18 decimals)
      30, // 0.3% fee
    )

    expect(bytecode).toBe(
      '0x126a0002a0b86991c6218b36c1d19d4a2e9eb0ce3606eb486b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000002540be40000000000000000000000000000000000000000000000021e19e0c9bab240000026040000001e1600'
    )
  })

  it('generates correct bytecode for WETH/USDC (1% fee)', () => {
    const bytecode = buildConstantProductProgram(
      '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
      10n * 10n ** 18n,     // 10 ETH (18 decimals)
      20_000n * 10n ** 6n,  // 20k USDC (6 decimals)
      100, // 1% fee
    )

    expect(bytecode).toBe(
      '0x126a0002c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000004a817c8002604000000641600'
    )
  })
})
