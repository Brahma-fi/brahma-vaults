// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {BrahmaVault, IERC20Metadata} from "../contracts/Vault.sol";
import {StrategyParams} from "../contracts/interfaces/IVault.sol";

import "./utils/IWETH9.sol";
import "./utils/ISwapRouter.sol";

import {Strategy} from "../../lib/perp-interface/contracts/Strategy.sol";
import "../../lib/ds-test/src/test.sol";

contract ContractTest is DSTest {
    BrahmaVault private vault;

    ISwapRouter private immutable SwapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20Metadata private constant USDC =
        IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH9 private constant WETH =
        IWETH9(payable(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)));

    function setUp() public {
        vault = new BrahmaVault(
            10**5 * 10**USDC.decimals(),
            address(USDC),
            self(),
            self(),
            self(),
            self(),
            "Perp Vault",
            "bPerp",
            18
        );
        swapAndGetBalances(1);

        emit log_named_address("Self", self());
    }

    /* CONFIGS */

    function testDeployment() public {
        assertEq(address(USDC), address(vault.token()));
        assertEq(self(), vault.governance());
        assertEq(self(), vault.rewards());
        assertEq(self(), vault.guardian());
        assertEq(self(), vault.management());

        emit log_named_address("Vault Token", address(vault.token()));
        emit log_named_address("Governance", vault.governance());
    }

    /* DEPOSIT */

    function testDeposit() public {
        _deposit();
    }

    function testFailExcessDeposit() public {
        swapAndGetBalances(100);

        USDC.approve(address(vault), type(uint256).max);
        vault.deposit(usdcBal(), self());
    }

    function testFailShutDownVaultDeposit() public {
        vault.setEmergencyShutdown(true);
        vault.deposit(usdcBal(), self());
    }

    function testFailDepositZero() public {
        vault.deposit(0, self());
    }

    function _deposit() internal {
        uint256 balanceBeforeDeposit = vault.balanceOf(self());
        emit log_named_uint("Vault token before deposit", balanceBeforeDeposit);

        USDC.approve(address(vault), type(uint256).max);
        vault.deposit(usdcBal(), self());

        uint256 balanceAfterDeposit = vault.balanceOf(self());
        emit log_named_uint("Vault tokens after deposit", balanceAfterDeposit);

        assertGt(
            balanceAfterDeposit,
            balanceBeforeDeposit,
            "Vault tokens not received after deposit"
        );
    }

    /* STRATEGY */

    function testAddStrategy() public {
        Strategy strategy = _addStrategy(50, 500, 1000, 2000);

        address addedStrategy = vault.withdrawalQueue(0);
        emit log_named_address("Added strategy", addedStrategy);

        assertEq(addedStrategy, address(strategy));
        _assertStrategyParams(
            vault.getStrategy(address(strategy)),
            50,
            500,
            1000,
            2000
        );
    }

    function testUpdateStrategy() public {
        Strategy strategy = _addStrategy(50, 500, 1000, 2000);

        vault.updateStrategyDebtRatio(address(strategy), 65);
        vault.updateStrategyMinDebtPerHarvest(address(strategy), 750);
        vault.updateStrategyMaxDebtPerHarvest(address(strategy), 1500);
        vault.updateStrategyPerformanceFee(address(strategy), 1500);

        _assertStrategyParams(
            vault.getStrategy(address(strategy)),
            65,
            750,
            1500,
            1500
        );
    }

    function testRevokeStrategy() public {
        _addStrategy(50, 500, 1000, 2000);
        Strategy strategy = _addStrategy(50, 500, 1000, 2000);

        uint256 initialDebtRatio = vault.debtRatio();
        vault.revokeStrategy(address(strategy));
        uint256 finalDebtRatio = vault.debtRatio();

        StrategyParams memory removedStrategy = vault.getStrategy(
            address(strategy)
        );

        emit log_named_uint("Initial debt ratio", initialDebtRatio);
        emit log_named_uint("Final debt ratio", finalDebtRatio);

        assertEq(removedStrategy.debtRatio, 0);
        assertEq(initialDebtRatio, 100);
        assertEq(finalDebtRatio, initialDebtRatio - 50);
    }

    function testMigrateStrategy() public {
        Strategy oldStrategy = _addStrategy(50, 500, 1000, 2000);
        Strategy newStrategy = new Strategy(address(vault), 1000, 6400, 100, 0);

        uint256 oldDebtRatio = vault.debtRatio();

        _assertStrategyParams(
            vault.getStrategy(address(newStrategy)),
            0,
            0,
            0,
            0
        );

        vault.migrateStrategy(address(oldStrategy), address(newStrategy));
        _assertStrategyParams(
            vault.getStrategy(address(newStrategy)),
            50,
            500,
            1000,
            2000
        );

        emit log_named_address("Old strategy", address(oldStrategy));
        emit log_named_address("New strategy", address(newStrategy));

        assertEq(oldDebtRatio, vault.debtRatio());
        assertEq(address(newStrategy), vault.withdrawalQueue(0));
    }

    function testAddStrategyToQueue() public {
        Strategy strategy = _removeStrategyFromQueueAndAssert();

        vault.addStrategyToQueue(address(strategy));
        emit log_named_address("Added strategy", address(strategy));

        assertEq(vault.withdrawalQueue(0), address(strategy));
    }

    function testRemoveStrategyFromQueue() public {
        _removeStrategyFromQueueAndAssert();
    }

    function _addStrategy(
        uint256 debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest,
        uint256 performanceFee
    ) internal returns (Strategy strategy) {
        strategy = new Strategy(address(vault), 1000, 6400, 100, 0);
        vault.addStrategy(
            address(strategy),
            debtRatio,
            minDebtPerHarvest,
            maxDebtPerHarvest,
            performanceFee
        );
    }

    function _assertStrategyParams(
        StrategyParams memory strategyParams,
        uint256 debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest,
        uint256 performanceFee
    ) internal {
        assertEq(strategyParams.performanceFee, performanceFee);
        assertEq(strategyParams.debtRatio, debtRatio);
        assertEq(strategyParams.minDebtPerHarvest, minDebtPerHarvest);
        assertEq(strategyParams.maxDebtPerHarvest, maxDebtPerHarvest);
    }

    function _removeStrategyFromQueueAndAssert()
        internal
        returns (Strategy strategy)
    {
        strategy = _addStrategy(50, 500, 1000, 2000);
        address addedStrategy = vault.withdrawalQueue(0);

        vault.removeStrategyFromQueue(address(strategy));

        emit log_named_address("Removed strategy", address(strategy));

        assertEq(addedStrategy, address(strategy));
        assertEq(vault.withdrawalQueue(0), address(0x0));
    }

    /* HELPERS */

    function swapAndGetBalances(uint256 _ethToSwap) internal {
        emit log_named_uint("ETH Balance", self().balance / 10**18);

        WETH.deposit{value: _ethToSwap * 10**18}();
        uint256 WETHBalance = WETH.balanceOf(self());
        WETH.approve(address(SwapRouter), WETHBalance);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(USDC),
                fee: 3000,
                recipient: self(),
                deadline: block.timestamp,
                amountIn: WETHBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        SwapRouter.exactInputSingle(params);

        emit log_named_uint(
            "USDC Balance",
            USDC.balanceOf(self()) / 10**USDC.decimals()
        );
    }

    function usdcBal() internal view returns (uint256) {
        return USDC.balanceOf(self());
    }

    function self() internal view returns (address) {
        return address(this);
    }
}
