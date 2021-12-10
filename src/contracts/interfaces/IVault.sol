// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../../../lib/openzeppelin/contracts/token/ERC20/IERC20.sol";

struct StrategyParams {
    uint256 performanceFee; // Strategist's fee (basis points)
    uint256 activation; // Activation block.timestamp
    uint256 debtRatio; // Maximum borrow amount (in BPS of total assets)
    uint256 minDebtPerHarvest; // Lower limit on the increase of debt since last harvest
    uint256 maxDebtPerHarvest; // Upper limit on the increase of debt since last harvest
    uint256 lastReport; // block.timestamp of the last time a report occured
    uint256 totalDebt; // Total outstanding debt that Strategy has
    uint256 totalGain; // Total returns that Strategy has realized for Vault
    uint256 totalLoss; // Total losses that Strategy has realized for Vault
}

interface IVault is IERC20 {
    function token() external view returns (IERC20);

    function apiVersion() external pure returns (string memory _apiVersion);

    function governance() external pure returns (address);

    function management() external pure returns (address);

    function guardian() external pure returns (address);

    function pendingGovernance() external pure returns (address);

    function strategies(address _strategyAddress)
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function withdrawalQueue() external pure returns (address[] memory);

    function emergencyShutdown() external pure returns (bool);

    function depositLimit() external pure returns (uint256);

    function debtRatio() external pure returns (uint256);

    function totalDebt() external pure returns (uint256);

    function lastReport() external pure returns (uint256);

    function activation() external pure returns (uint256);

    function managementFee() external pure returns (uint256);

    function performanceFee() external pure returns (uint256);

    function rewards() external pure returns (address);

    function initialize(
        address token,
        address governance,
        address rewards,
        string memory nameOverride,
        string memory symbolOverride,
        address guardian,
        address management
    ) external;

    function setName(string memory name) external;

    function setSymbol(string memory symbol) external;

    function setGovernance(address governance) external;

    function acceptGovernance() external;

    function setManangement(address management) external;

    function setGuardian(address guardian) external;

    function setRewards(address rewards) external;

    function setDepositLimit(uint256 depositLimit) external;

    function setPerformanceFee(uint256 depositLimit) external;

    function setManagementFee(uint256 depositLimit) external;

    function setWithdrawalQueue(address[] memory queue) external;

    function totalAssets() external view returns (uint256);

    function deposit(uint256 _amount, address recepient)
        external
        returns (uint256 sharesOut);

    function maxAvailableShares()
        external
        view
        returns (uint256 _maxAvailableShares);

    function withdraw(
        uint256 maxShares,
        address recepient,
        uint256 maxLoss
    ) external returns (uint256 amountOut);

    function pricePerShare() external returns (uint256);

    function addStrategy(
        address strategy,
        uint256 debtRatio,
        uint256 minDebtPerHarvent,
        uint256 maxDebtPerHarvest,
        uint256 performanceFee,
        uint256 profitLimitRatio,
        uint256 lossLimitRatio
    ) external;

    function updateStrategyDebtRatio(address strategy, uint256 debtRatio)
        external;

    function updateStrategyMinDebtPerHarvest(
        address strategy,
        uint256 minDebtPerHarvest
    ) external;

    function updateStrategyMaxDebtPerHarvest(
        address strategy,
        uint256 maxDebtPerHarvest
    ) external;

    function updateStrategyPerformanceFee(
        address strategy,
        uint256 performanceFee
    ) external;

    function migrateStrategy(address oldVersion, address newVersion) external;

    function revokeStrategy(address strategy) external;

    function addStrategyToQueue(address strategy) external;

    function removeStrategyFromQueue(address strategy) external;

    function debtOutstanding(address strategy) external view returns (uint256);

    function creditAvailable(address strategy) external view returns (uint256);

    function availableDepositLimit() external returns (uint256);

    function expectedReturn(address strategy) external returns (uint256);

    function report(
        uint256 gain,
        uint256 loss,
        uint256 _debtPayment
    ) external returns (uint256 debtOutstanding);

    function sweep(address token, uint256 amount) external;
}
