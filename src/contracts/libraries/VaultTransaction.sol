// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../utils/Math.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";

import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

library VaultTransaction {
    using SafeERC20 for IERC20Metadata;
    uint256 public constant MAX_BPS = 10000;

    function _withdraw(
        uint256 shares,
        address recepient,
        uint256 maxLoss,
        uint256 _shareValue,
        uint256 totalDebt,
        address vault,
        IERC20Metadata token,
        address[] memory withdrawalQueue,
        mapping(address => StrategyParams) storage strategies
    )
        internal
        returns (
            uint256,
            uint256,
            uint256,
            bool calcSharesForAmount
        )
    {
        require(maxLoss <= MAX_BPS, "loss too large");
        require(
            shares <= IERC20(vault).balanceOf(msg.sender),
            "insufficient balance"
        );
        require(shares != 0, "zero shares");

        uint256 totalLoss = 0;

        if (_shareValue > token.balanceOf(vault)) {
            address strategy;

            for (uint256 i = 0; i < withdrawalQueue.length; i++) {
                strategy = withdrawalQueue[i];

                if (strategy == address(0x0)) {
                    break;
                }

                uint256 curVaultBalance = token.balanceOf(vault);
                if (_shareValue < curVaultBalance) {
                    break;
                }

                uint256 amountNeeded = _shareValue - curVaultBalance;
                amountNeeded = Math.min(
                    amountNeeded,
                    strategies[strategy].totalDebt
                );
                if (amountNeeded == 0) {
                    continue;
                }

                uint256 loss = IStrategy(strategy).withdraw(amountNeeded);
                if (loss > 0) {
                    _shareValue -= loss;
                    totalLoss += loss;
                }

                strategies[strategy].totalDebt -= (token.balanceOf(vault) -
                    curVaultBalance);
                totalDebt -= (token.balanceOf(vault) - curVaultBalance);
            }

            uint256 vaultBalance = token.balanceOf(vault);
            if (_shareValue > vaultBalance) {
                _shareValue = vaultBalance;
                calcSharesForAmount = true;
            }

            require(
                totalLoss <= maxLoss * ((_shareValue + totalLoss) / MAX_BPS),
                "loss protection"
            );
        }

        token.safeTransfer(recepient, _shareValue);

        return (_shareValue, totalDebt, totalLoss, calcSharesForAmount);
    }
}
