import { describe, it, expect } from 'vitest'
import { buildStableSwapProgram } from '../stableSwap'
import { sortTokens, calculateRates } from '../encoding'

describe('sortTokens', () => {
  it('sorts tokens by address ascending', () => {
    // DAI (0x6B...) < USDC (0xA0...) → DAI is tokenLt
    const result = sortTokens(
      '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI (lower)
      10_000n * 10n ** 18n,
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC (higher)
      10_000n * 10n ** 6n,
    )

    expect(result.tokenLt.toLowerCase()).toBe('0x6b175474e89094c44da98b954eedeac495271d0f')
    expect(result.tokenGt.toLowerCase()).toBe('0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48')
    expect(result.balanceLt).toBe(10_000n * 10n ** 18n)
    expect(result.balanceGt).toBe(10_000n * 10n ** 6n)
  })

  it('swaps when token0 > token1', () => {
    // USDC (0xA0...) > DAI (0x6B...) → should swap
    const result = sortTokens(
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC (higher)
      10_000n * 10n ** 6n,
      '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI (lower)
      10_000n * 10n ** 18n,
    )

    expect(result.tokenLt.toLowerCase()).toBe('0x6b175474e89094c44da98b954eedeac495271d0f')
    expect(result.tokenGt.toLowerCase()).toBe('0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48')
    expect(result.balanceLt).toBe(10_000n * 10n ** 18n)
    expect(result.balanceGt).toBe(10_000n * 10n ** 6n)
  })
})

describe('calculateRates', () => {
  it('computes rates for DAI(18)/USDC(6) pair', () => {
    // DAI (0x6B...) < USDC (0xA0...) → tokenLt=DAI, tokenGt=USDC
    const { rateLt, rateGt } = calculateRates(
      '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI (18 dec)
      18,
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC (6 dec)
      6,
    )
    expect(rateLt).toBe(1_000_000_000_000n) // 1e12 (18 - 6 = 12)
    expect(rateGt).toBe(1n)                 // 10^0 = 1
  })

  it('computes rates for same-decimal pair (18/18)', () => {
    const { rateLt, rateGt } = calculateRates(
      '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', // stETH
      18,
      '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
      18,
    )
    expect(rateLt).toBe(1n)
    expect(rateGt).toBe(1n)
  })

  it('handles reversed token order (USDC first, DAI second)', () => {
    const { rateLt, rateGt } = calculateRates(
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC (higher addr, 6 dec)
      6,
      '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI (lower addr, 18 dec)
      18,
    )
    // After sorting: tokenLt=DAI(18), tokenGt=USDC(6)
    expect(rateLt).toBe(1_000_000_000_000n) // 1e12 for DAI
    expect(rateGt).toBe(1n)                 // 1 for USDC
  })
})

describe('buildStableSwapProgram', () => {
  it('generates correct bytecode for USDC/DAI (A=0.8, 0.05% fee)', () => {
    const bytecode = buildStableSwapProgram({
      token0: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
      token1: '0x6B175474E89094C44Da98b954EedeAC495271d0F', // DAI
      balance0: 10_000n * 10n ** 6n,  // 10k USDC (6 decimals)
      balance1: 10_000n * 10n ** 18n, // 10k DAI (18 decimals)
      linearWidth: 800_000_000_000_000_000_000_000_000n, // 0.8e27
      rateLt: 1_000_000_000_000n, // 1e12
      rateGt: 1n,
      feeBps: 5, // 0.05%
    })

    // After sorting: tokenLt=DAI(0x6B), tokenGt=USDC(0xA0)
    // balanceLt=10_000e18 (DAI), balanceGt=10_000e6 (USDC)
    // x0 = balanceLt * rateLt = 10_000e18 * 1e12 = 1e34
    // y0 = balanceGt * rateGt = 10_000e6 * 1 = 1e10
    expect(bytecode).toBe(
      '0x126a0002' +
      '6b175474e89094c44da98b954eedeac495271d0f' + // DAI (tokenLt)
      'a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48' + // USDC (tokenGt)
      '00000000000000000000000000000000000000000000021e19e0c9bab2400000' + // 10_000e18
      '00000000000000000000000000000000000000000000000000000002540be400' + // 10_000e6
      '26040000000' + '5' + // Fee: opcode 0x26, 4 bytes, 5 bps
      '2ca0' + // PeggedSwap: opcode 0x2c, 160 bytes
      '000000000000000000000000000000000001ed09bead87c0378d8e6400000000' + // x0
      '00000000000000000000000000000000000000000000000000000002540be400' + // y0
      '00000000000000000000000000000000000000000295be96e640669720000000' + // linearWidth
      '000000000000000000000000000000000000000000000000000000e8d4a51000' + // rateLt
      '0000000000000000000000000000000000000000000000000000000000000001'   // rateGt
    )

    expect((bytecode.length - 2) / 2).toBe(276)
  })

  it('generates correct bytecode for WETH/stETH (A=0.5, 0.1% fee)', () => {
    const bytecode = buildStableSwapProgram({
      token0: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
      token1: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', // stETH
      balance0: 100n * 10n ** 18n, // 100 WETH
      balance1: 100n * 10n ** 18n, // 100 stETH
      linearWidth: 500_000_000_000_000_000_000_000_000n, // 0.5e27
      rateLt: 1n,
      rateGt: 1n,
      feeBps: 10, // 0.1%
    })

    // After sorting: tokenLt=stETH(0xae), tokenGt=WETH(0xc0)
    // balanceLt=100e18 (stETH), balanceGt=100e18 (WETH)
    // x0 = 100e18 * 1 = 100e18, y0 = 100e18 * 1 = 100e18
    expect(bytecode).toBe(
      '0x126a0002' +
      'ae7ab96520de3a18e5e111b5eaab095312d7fe84' + // stETH (tokenLt)
      'c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' + // WETH (tokenGt)
      '0000000000000000000000000000000000000000000000056bc75e2d63100000' + // 100e18
      '0000000000000000000000000000000000000000000000056bc75e2d63100000' + // 100e18
      '2604' + '0000000a' + // Fee: 10 bps
      '2ca0' + // PeggedSwap: opcode 0x2c, 160 bytes
      '0000000000000000000000000000000000000000000000056bc75e2d63100000' + // x0
      '0000000000000000000000000000000000000000000000056bc75e2d63100000' + // y0
      '0000000000000000000000000000000000000000019d971e4fe8401e74000000' + // linearWidth
      '0000000000000000000000000000000000000000000000000000000000000001' + // rateLt
      '0000000000000000000000000000000000000000000000000000000000000001'   // rateGt
    )

    expect((bytecode.length - 2) / 2).toBe(276)
  })
})
