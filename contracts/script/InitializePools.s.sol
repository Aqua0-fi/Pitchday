// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {
    IUnlockCallback
} from "@uniswap/v4-core/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {PoolSwapTest} from "@uniswap/v4-core/test/PoolSwapTest.sol";

contract SetupRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
    }

    function modifyLiquidity(
        PoolKey memory key,
        ModifyLiquidityParams memory params
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(abi.encode(CallbackData(msg.sender, key, params))),
            (BalanceDelta)
        );

        // We intentionally don't refund excess ETH to msg.sender to avoid a
        // known foundry bug where refunding the broadcaster hangs gas estimation.
    }

    function settle(
        Currency currency,
        address sender,
        uint256 amount
    ) internal {
        if (Currency.unwrap(currency) == address(0)) {
            manager.settle{value: amount}();
        } else {
            manager.sync(currency);
            ERC20(Currency.unwrap(currency)).transferFrom(
                sender,
                address(manager),
                amount
            );
            manager.settle();
        }
    }

    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        (BalanceDelta delta, ) = manager.modifyLiquidity(
            data.key,
            data.params,
            new bytes(0)
        );

        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        if (delta0 < 0) {
            settle(data.key.currency0, data.sender, uint256(-delta0));
        }
        if (delta1 < 0) {
            settle(data.key.currency1, data.sender, uint256(-delta1));
        }
        if (delta0 > 0) {
            manager.take(data.key.currency0, data.sender, uint256(delta0));
        }
        if (delta1 > 0) {
            manager.take(data.key.currency1, data.sender, uint256(delta1));
        }

        return abi.encode(delta);
    }
}

// ─── Simple mintable mock token ──────────────────────────────────────────────

contract MockERC20 is ERC20 {
    uint8 private _dec;

    constructor(
        string memory name,
        string memory symbol,
        uint8 dec,
        uint256 supply,
        address mintTo
    ) ERC20(name, symbol) {
        _dec = dec;
        _mint(mintTo, supply);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Pool initializer ─────────────────────────────────────────────────────────

contract InitializePools is Script {
    // SqrtPriceX96 constants
    // 1:1 price (for mDAI / mUSDC)
    uint160 constant SQRT_PRICE_1_TO_1 = 79228162514264337593543950336;

    // sqrtPriceX96 for 1 WBTC = 67848.1 USDC (or DAI)
    uint160 constant SQRT_PRICE_WBTC_1 = 304166050470486642314444800; // when Stable < WBTC
    uint160 constant SQRT_PRICE_WBTC_0 = 20636906163351982855239162986496; // when WBTC < Stable

    // Supply minted to deployer at deploy time (massive for testnets)
    uint256 constant STABLE_SUPPLY = 10_000_000 * 1e18; // 10M 
    uint256 constant WBTC_SUPPLY = 1_000 * 1e18;        // 1K
    uint256 constant WETH_SUPPLY = 1_000_000 * 1e18;    // 1M

    // ── Helper to determine price and sorted tokens ──
    function getSorted(address tA, address tB, uint160 pA, uint160 pB) internal pure returns (address t0, address t1, uint160 p) {
        if (tA < tB) {
            t0 = tA;
            t1 = tB;
            p = pA;
        } else {
            t0 = tB;
            t1 = tA;
            p = pB;
        }
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address hookAddr = vm.envAddress("AQUA0_HOOK_ADDR");
        address poolManagerAddr = vm.envAddress("POOL_MANAGER_ADDR");
        address fundTarget = vm.envAddress("FUND_TARGET");

        IPoolManager pm = IPoolManager(poolManagerAddr);
        IHooks hook = IHooks(hookAddr);

        console.log("=== InitializePools ===");
        console.log("Deployer:    ", deployer);
        console.log("Hook:        ", hookAddr);
        console.log("PoolManager: ", poolManagerAddr);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy mock tokens
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 18, STABLE_SUPPLY, deployer);
        MockERC20 mockDAI  = new MockERC20("Mock DAI", "mDAI", 18, STABLE_SUPPLY, deployer);
        MockERC20 mockWBTC = new MockERC20("Mock WBTC", "mWBTC", 18, WBTC_SUPPLY, deployer);
        MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18, WETH_SUPPLY, deployer);

        console.log("MockUSDC deployed:", address(mockUSDC));
        console.log("MockDAI deployed: ", address(mockDAI));
        console.log("MockWBTC deployed:", address(mockWBTC));
        console.log("MockWETH deployed:", address(mockWETH));

        // 1.5 Mint tokens to the fund target
        mockUSDC.mint(fundTarget, STABLE_SUPPLY);
        mockDAI.mint(fundTarget, STABLE_SUPPLY);
        mockWBTC.mint(fundTarget, WBTC_SUPPLY);
        mockWETH.mint(fundTarget, WETH_SUPPLY);
        console.log("Minted", STABLE_SUPPLY / 1e18, "mUSDC to", fundTarget);
        console.log("Minted", STABLE_SUPPLY / 1e18, "mDAI to", fundTarget);
        console.log("Minted", WBTC_SUPPLY / 1e18, "mWBTC to", fundTarget);
        console.log("Minted", WETH_SUPPLY / 1e18, "mWETH to", fundTarget);

        // 1.75 Deploy V4 Liquidity modification router for initial liquidity setup
        SetupRouter router = new SetupRouter(pm);
        PoolSwapTest swapRouter = new PoolSwapTest(pm);

        mockUSDC.approve(address(router), type(uint256).max);
        mockDAI.approve(address(router), type(uint256).max);
        mockWBTC.approve(address(router), type(uint256).max);
        mockWETH.approve(address(router), type(uint256).max);
        
        mockUSDC.approve(address(swapRouter), type(uint256).max);
        mockDAI.approve(address(swapRouter), type(uint256).max);
        mockWBTC.approve(address(swapRouter), type(uint256).max);
        mockWETH.approve(address(swapRouter), type(uint256).max);

        // 2. Pool 1: mUSDC / mWBTC
        (address u_w_0, address u_w_1, uint160 p_u_w) = getSorted(address(mockUSDC), address(mockWBTC), SQRT_PRICE_WBTC_1, SQRT_PRICE_WBTC_0);
        PoolKey memory pool1 = PoolKey({
            currency0: Currency.wrap(u_w_0),
            currency1: Currency.wrap(u_w_1),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        pm.initialize(pool1, p_u_w);
        console.log("Pool 1 (mUSDC / mWBTC) initialized");
        // Target Liquidity: $2000 total -> 1000 USDC / 0.0147 WBTC
        router.modifyLiquidity(
            pool1,
            ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper: 887220,
                liquidityDelta: 3839115294586368902, // Exactly half of the previous 7.67e18 to reach $2k equivalent
                salt: 0
            })
        );
        console.log("Pool 1 seeded with ~$2000 initial liquidity.");

        // 3. Pool 2: mDAI / mWBTC
        (address d_w_0, address d_w_1, uint160 p_d_w) = getSorted(address(mockDAI), address(mockWBTC), SQRT_PRICE_WBTC_1, SQRT_PRICE_WBTC_0);
        PoolKey memory pool2 = PoolKey({
            currency0: Currency.wrap(d_w_0),
            currency1: Currency.wrap(d_w_1),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        pm.initialize(pool2, p_d_w);
        console.log("Pool 2 (mDAI / mWBTC) initialized");
        router.modifyLiquidity(
            pool2,
            ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper: 887220,
                liquidityDelta: 3839115294586368902, // ~$2000
                salt: 0
            })
        );
        console.log("Pool 2 seeded with ~$2000 initial liquidity.");

        // 4. Pool 3: mDAI / mUSDC (1:1)
        (address d_u_0, address d_u_1, uint160 p_d_u) = getSorted(address(mockDAI), address(mockUSDC), SQRT_PRICE_1_TO_1, SQRT_PRICE_1_TO_1);
        PoolKey memory pool3 = PoolKey({
            currency0: Currency.wrap(d_u_0),
            currency1: Currency.wrap(d_u_1),
            fee: 500, // Stables usually use 0.05%
            tickSpacing: 10,
            hooks: hook
        });
        pm.initialize(pool3, p_d_u);
        console.log("Pool 3 (mDAI / mUSDC) initialized");
        // For a 1:1 pool at full range, L = sqrt(x * y) = amount (since x=y)
        // For $2k total, we need 1000 of each.
        router.modifyLiquidity(
            pool3,
            ModifyLiquidityParams({
                tickLower: -887270, // nearest multiple of 10
                tickUpper: 887270,
                liquidityDelta: 1000 * 1e18, 
                salt: 0
            })
        );
        console.log("Pool 3 seeded with ~$2000 initial liquidity.");

        // 5. Pool 4: mWETH / mUSDC
        // approx 1 ETH = 2000 USDC -> sqrtPriceX96 for Stable/WETH is roughly 3543191142285914205922034323200
        // inverted: 1771595571142957102961017
        (address e_u_0, address e_u_1, uint160 p_e_u) = getSorted(address(mockWETH), address(mockUSDC), 3543191142285914205922034323200, 1771595571142957102961017);
        PoolKey memory pool4 = PoolKey({
            currency0: Currency.wrap(e_u_0),
            currency1: Currency.wrap(e_u_1),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        pm.initialize(pool4, p_e_u);
        console.log("Pool 4 (mWETH / mUSDC) initialized");
        router.modifyLiquidity(
            pool4,
            ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper: 887220,
                liquidityDelta: 3839115294586368902, // ~$2000
                salt: 0
            })
        );
        console.log("Pool 4 seeded with ~$2000 initial liquidity.");

        vm.stopBroadcast();

        // 5. Write token addresses
        // Determine the chain string logic so we can output the correct tokens JSON file safely 
        // across Mainnets / Testnets / Local
        string memory chainSuffix = "local";
        if (block.chainid == 84532) chainSuffix = "base-sepolia";
        else if (block.chainid == 1301) chainSuffix = "unichain-sepolia";

        string memory json = string.concat(
            "{\n",
            '  "mockUsdc": "', vm.toString(address(mockUSDC)), '",\n',
            '  "mockDai": "', vm.toString(address(mockDAI)), '",\n',
            '  "mockWbtc": "', vm.toString(address(mockWBTC)), '",\n',
            '  "mockWeth": "', vm.toString(address(mockWETH)), '",\n',
            // Return keys so backend logic can automatically index the mock pools natively
            '  "pool1Currency0": "', vm.toString(u_w_0), '",\n',
            '  "pool1Currency1": "', vm.toString(u_w_1), '",\n',
            '  "pool2Currency0": "', vm.toString(d_w_0), '",\n',
            '  "pool2Currency1": "', vm.toString(d_w_1), '",\n',
            '  "pool3Currency0": "', vm.toString(d_u_0), '",\n',
            '  "pool3Currency1": "', vm.toString(d_u_1), '",\n',
            '  "pool4Currency0": "', vm.toString(e_u_0), '",\n',
            '  "pool4Currency1": "', vm.toString(e_u_1), '",\n',
            '  "poolSwapTest": "', vm.toString(address(swapRouter)), '"\n',
            "}"
        );
        string memory outPath = string.concat("deployments/v4-hookathon-", chainSuffix, "-tokens.json");
        vm.writeFile(outPath, json);
        console.log("\nToken + pool data saved to", outPath);
    }
}
