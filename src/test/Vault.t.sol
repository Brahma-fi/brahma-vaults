// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../contracts/Vault.sol";
import "./utils/IWETH9.sol";
import "./utils/ISwapRouter.sol";

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
