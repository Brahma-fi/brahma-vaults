// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    function token() external view returns (IERC20Metadata);

    function apiVersion() external view returns (string memory _apiVersion);

    function governance() external view returns (address);

    function management() external view returns (address);

    function guardian() external view returns (address);

    function pendingGovernance() external view returns (address);

    function strategies(address _strategyAddress)
        external
        view
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

    function strategiesCount() external view returns (uint256);

    function withdrawalQueue() external view returns (address[] memory);

    function emergencyShutdown() external view returns (bool);

    function depositLimit() external view returns (uint256);

    function debtRatio() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function lastReport() external view returns (uint256);

    function activation() external view returns (uint256);

    function managementFee() external view returns (uint256);

    function performanceFee() external view returns (uint256);

    function rewards() external view returns (address);

    function setGovernance(address _governance) external;

    function acceptGovernance() external;

    function setManangement(address _management) external;

    function setGuardian(address _guardian) external;

    function setRewards(address _rewards) external;

    function setDepositLimit(uint256 _depositLimit) external;

    function setPerformanceFee(uint256 _performanceFee) external;

    function setManagementFee(uint256 _managementFee) external;

    function setEmergencyShutdown(bool _active) external;

    function setWithdrawalQueue(address[] memory queue) external;

    function totalAssets() external view returns (uint256);

    function deposit(uint256 _amount, address recepient)
        external
        returns (uint256 sharesOut);

    function deposit(address recepient) external returns (uint256 sharesOut);

    function maxAvailableShares()
        external
        view
        returns (uint256 _maxAvailableShares);

    function withdraw(address recepient, uint256 maxLoss)
        external
        returns (uint256);

    function withdraw(
        uint256 maxShares,
        address recepient,
        uint256 maxLoss
    ) external returns (uint256);

    function pricePerShare() external view returns (uint256);

    function addStrategy(
        address strategy,
        uint256 _debtRatio,
        uint256 _minDebtPerHarvent,
        uint256 _maxDebtPerHarvest,
        uint256 _performanceFee
    ) external;

    function updateStrategyDebtRatio(address strategy, uint256 _debtRatio)
        external;

    function updateStrategyMinDebtPerHarvest(
        address strategy,
        uint256 _minDebtPerHarvest
    ) external;

    function updateStrategyMaxDebtPerHarvest(
        address strategy,
        uint256 _maxDebtPerHarvest
    ) external;

    function updateStrategyPerformanceFee(
        address strategy,
        uint256 _performanceFee
    ) external;

    function migrateStrategy(address oldVersion, address newVersion) external;

    function revokeStrategy(address strategy) external;

    function addStrategyToQueue(address strategy) external;

    function removeStrategyFromQueue(address strategy) external;

    function debtOutstanding(address strategy) external view returns (uint256);

    function creditAvailable(address strategy) external view returns (uint256);

    function availableDepositLimit() external view returns (uint256);

    function expectedReturn(address strategy) external view returns (uint256);

    function report(
        uint256 gain,
        uint256 loss,
        uint256 _debtPayment
    ) external returns (uint256 debt);

    function sweep(address token, uint256 amount) external;

    function sweep(address token) external;
}
