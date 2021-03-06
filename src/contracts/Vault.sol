// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;
pragma abicoder v2;

import "./interfaces/IVault.sol";
import "./interfaces/IStrategy.sol";
import "./utils/ERC20.sol";
import "./utils/Math.sol";
import "./libraries/VaultTransaction.sol";

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract BrahmaVault is IVault, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    string public constant API_VERSION = "1.0.0";
    uint256 public constant MAX_BPS = 10000;
    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant SECS_PER_YEAR = 31556952;

    IERC20Metadata public override token;
    address public override governance;
    address public override pendingGovernance;
    address public override management;
    address public override guardian;

    mapping(address => StrategyParams) private strategies;
    uint256 public override strategiesCount;
    address[] public withdrawalQueue;

    bool public override emergencyShutdown;

    uint256 public override depositLimit;
    uint256 public override debtRatio;
    uint256 public override totalDebt;
    uint256 public override lastReport;
    uint256 public override activation;

    address public override rewards;
    uint256 public override managementFee;
    uint256 public override performanceFee;

    constructor(
        uint256 _depositLimit,
        address _token,
        address _governance,
        address _rewards,
        address _guardian,
        address _management,
        string memory _name,
        string memory _symbol,
        uint8 _decimal
    ) ERC20(_name, _symbol, _decimal) {
        _initialize(
            _depositLimit,
            _token,
            _governance,
            _rewards,
            _guardian,
            _management
        );
    }

    function apiVersion() external pure override returns (string memory) {
        return API_VERSION;
    }

    function getStrategy(address _strategyAddress)
        external
        view
        override
        returns (StrategyParams memory)
    {
        return strategies[_strategyAddress];
    }

    function setGovernance(address _governance)
        external
        override
        onlyGovernance
    {
        pendingGovernance = _governance;
    }

    function acceptGovernance() external override {
        _onlyPendingGovernance();
        governance = msg.sender;
    }

    function setManangement(address _management)
        external
        override
        onlyGovernance
    {
        management = _management;
    }

    function setRewards(address _rewards) external override onlyGovernance {
        require(rewards != address(this), "Invalid rewards");
        rewards = _rewards;
    }

    function setGuardian(address _guardian) external override {
        _onlyGovernanceGuardian();
        guardian = _guardian;
    }

    function setDepositLimit(uint256 _depositLimit)
        external
        override
        onlyGovernance
    {
        depositLimit = _depositLimit;
    }

    function setPerformanceFee(uint256 _performanceFee)
        external
        override
        onlyGovernance
    {
        require(_performanceFee <= MAX_BPS / 2, "fee too high");
        performanceFee = _performanceFee;
    }

    function setManagementFee(uint256 _managementFee)
        external
        override
        onlyGovernance
    {
        require(_managementFee <= MAX_BPS, "fee too high");
        managementFee = _managementFee;
    }

    function setEmergencyShutdown(bool _active) external override {
        if (_active) {
            _onlyGovernanceGuardian();
        } else {
            _onlyGovernance();
        }

        emergencyShutdown = _active;
    }

    function setWithdrawalQueue(address[] memory queue) external override {
        require(
            queue.length > 0 && queue.length <= strategiesCount,
            "Invalid withdrawal Queue"
        );

        for (uint256 i = 0; i < queue.length; i++) {
            require(strategies[queue[i]].activation > 0, "strategy not active");
            withdrawalQueue[i] = queue[i];
        }
        for (uint256 i = queue.length; i < withdrawalQueue.length; i++) {
            withdrawalQueue[i] = address(0x0);
        }
    }

    function _totalAssets() internal view returns (uint256) {
        return token.balanceOf(address(this)) + totalDebt;
    }

    function totalAssets() external view override returns (uint256) {
        return _totalAssets();
    }

    function _issueSharesForAmount(address to, uint256 amount)
        internal
        returns (uint256 shares)
    {
        if (totalSupply > 0) {
            shares = amount * (totalSupply / _totalAssets());
        } else {
            shares = amount;
        }

        _mint(to, shares);
    }

    function _depositHealthCheck() internal view {
        require(!emergencyShutdown, "deposits are locked");
        require(
            msg.sender != address(0x0) && msg.sender != address(this),
            "bad request"
        );
    }

    function deposit(uint256 _amount, address recepient)
        external
        override
        nonReentrant
        returns (uint256 sharesOut)
    {
        _depositHealthCheck();
        _nonZero(_amount, "zero amount");
        require(_totalAssets() + _amount <= depositLimit, "excess deposit");

        sharesOut = _issueSharesForAmount(recepient, _amount);
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function _shareValue(uint256 shares) internal view returns (uint256) {
        if (totalSupply == 0) {
            return shares;
        }

        return shares * (_totalAssets() / totalSupply);
    }

    function _sharesForAmount(uint256 amount) internal view returns (uint256) {
        uint256 freeFunds = _totalAssets();

        if (freeFunds <= 0) {
            return 0;
        }

        return amount * (totalSupply / freeFunds);
    }

    function maxAvailableShares()
        external
        view
        override
        returns (uint256 _maxAvailableShares)
    {
        _maxAvailableShares = _sharesForAmount(token.balanceOf(address(this)));

        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            if (withdrawalQueue[i] == address(0x0)) {
                break;
            }

            _maxAvailableShares += _sharesForAmount(
                strategies[withdrawalQueue[i]].totalDebt
            );
        }
    }

    function _withdraw(
        uint256 shares,
        address recepient,
        uint256 maxLoss
    ) internal returns (uint256) {
        require(maxLoss <= MAX_BPS, "loss too large");
        require(
            shares <= IERC20(address(this)).balanceOf(msg.sender),
            "insufficient balance"
        );
        _nonZero(shares, "zero shares");

        uint256 value = _shareValue(shares);

        if (value > token.balanceOf(address(this))) {
            uint256 totalLoss = 0;
            address strategy;

            for (uint256 i = 0; i < withdrawalQueue.length; i++) {
                strategy = withdrawalQueue[i];

                if (strategy == address(0x0)) {
                    break;
                }

                uint256 curVaultBalance = token.balanceOf(address(this));
                if (value < curVaultBalance) {
                    break;
                }

                uint256 amountNeeded = value - curVaultBalance;
                amountNeeded = Math.min(
                    amountNeeded,
                    strategies[strategy].totalDebt
                );
                if (amountNeeded == 0) {
                    continue;
                }

                uint256 loss = IStrategy(strategy).withdraw(amountNeeded);
                uint256 withdrawn = token.balanceOf(address(this)) -
                    curVaultBalance;
                if (loss > 0) {
                    value -= loss;
                    totalLoss += loss;
                }

                strategies[strategy].totalDebt -= withdrawn;
                totalDebt -= withdrawn;
            }

            uint256 vaultBalance = token.balanceOf(address(this));
            if (value > vaultBalance) {
                value = vaultBalance;
                shares = _sharesForAmount(value + totalLoss);
            }

            require(
                totalLoss <= maxLoss * ((value + totalLoss) / MAX_BPS),
                "loss protection"
            );
        }

        _burn(msg.sender, shares);
        token.safeTransfer(recepient, value);

        return value;
    }

    function withdraw(
        uint256 maxShares,
        address recepient,
        uint256 maxLoss
    ) external override nonReentrant returns (uint256) {
        return _withdraw(maxShares, recepient, maxLoss);
    }

    function pricePerShare() external view override returns (uint256) {
        return _shareValue(10**decimals);
    }

    function _organizeWithdrawalQueue() internal {
        uint256 offset = 0;

        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            address strategy = withdrawalQueue[i];
            if (strategy == address(0x0)) {
                offset += 1;
            } else if (offset > 0) {
                withdrawalQueue[i - offset] = strategy;
                withdrawalQueue[i] = address(0x0);
            }
        }
    }

    function addStrategy(
        address strategy,
        uint256 _debtRatio,
        uint256 _minDebtPerHarvest,
        uint256 _maxDebtPerHarvest,
        uint256 _performanceFee
    ) external override onlyGovernance {
        require(!emergencyShutdown, "vault is shutdown");
        require(strategy != address(0x0), "invalid strategy address");
        require(
            strategies[strategy].activation == 0,
            "strategy already activated"
        );
        require(
            IStrategy(strategy).vault() == address(this),
            "strategy-vault mismatch"
        );
        require(
            IStrategy(strategy).want() == address(token),
            "strategy-want mismatch"
        );
        require(debtRatio + _debtRatio <= MAX_BPS, "debtRatio exceeded");
        require(
            _minDebtPerHarvest <= _maxDebtPerHarvest,
            "invalid debt per harvest config"
        );
        require(performanceFee <= MAX_BPS / 2, "performance fee too high");

        strategies[strategy] = StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            debtRatio: _debtRatio,
            minDebtPerHarvest: _minDebtPerHarvest,
            maxDebtPerHarvest: _maxDebtPerHarvest,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });

        debtRatio += _debtRatio;

        withdrawalQueue.push(strategy);
        _organizeWithdrawalQueue();
    }

    function updateStrategyDebtRatio(address strategy, uint256 _debtRatio)
        external
        override
        validStrategyUpdation(strategy)
    {
        require(debtRatio + _debtRatio <= MAX_BPS, "debtRatio exceeded");
        debtRatio = debtRatio - strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = _debtRatio;
        debtRatio = debtRatio + _debtRatio;
    }

    function updateStrategyMinDebtPerHarvest(
        address strategy,
        uint256 _minDebtPerHarvest
    ) external override validStrategyUpdation(strategy) {
        require(
            strategies[strategy].maxDebtPerHarvest >= _minDebtPerHarvest,
            "minDebtPerHarvest too high"
        );
        strategies[strategy].minDebtPerHarvest = _minDebtPerHarvest;
    }

    function updateStrategyMaxDebtPerHarvest(
        address strategy,
        uint256 _maxDebtPerHarvest
    ) external override validStrategyUpdation(strategy) {
        require(
            strategies[strategy].minDebtPerHarvest <= _maxDebtPerHarvest,
            "maxDebtPerHarvest too low"
        );
        strategies[strategy].maxDebtPerHarvest = _maxDebtPerHarvest;
    }

    function updateStrategyPerformanceFee(
        address strategy,
        uint256 _performanceFee
    ) external override validStrategyUpdation(strategy) {
        require(performanceFee <= MAX_BPS / 2, "performance fee too high");
        _nonZero(performanceFee, "low performanceFee");
        strategies[strategy].performanceFee = _performanceFee;
    }

    function _revokeStrategy(address strategy) internal {
        debtRatio -= strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = 0;
    }

    function revokeStrategy(address strategy) external override {
        require(
            msg.sender == guardian || msg.sender == governance,
            "access restricted"
        );

        if (strategies[strategy].debtRatio == 0) return;
        _revokeStrategy(strategy);
    }

    function migrateStrategy(address oldVersion, address newVersion)
        external
        override
        onlyGovernance
    {
        require(newVersion != address(0x0), "invalid new version address");
        require(
            strategies[newVersion].activation == 0,
            "new version already activated"
        );
        _nonZero(strategies[oldVersion].activation, "unactivated version");

        StrategyParams memory strategy = strategies[oldVersion];
        _revokeStrategy(oldVersion);

        debtRatio += strategy.debtRatio;
        strategies[oldVersion].totalDebt = 0;

        strategies[newVersion] = StrategyParams({
            performanceFee: strategy.performanceFee,
            activation: strategy.lastReport,
            debtRatio: strategy.debtRatio,
            minDebtPerHarvest: strategy.minDebtPerHarvest,
            maxDebtPerHarvest: strategy.maxDebtPerHarvest,
            lastReport: strategy.lastReport,
            totalDebt: strategy.totalDebt,
            totalGain: 0,
            totalLoss: 0
        });

        IStrategy(oldVersion).migrate(newVersion);
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            if (withdrawalQueue[i] == oldVersion) {
                withdrawalQueue[i] = newVersion;
            }
        }
    }

    function addStrategyToQueue(address strategy)
        external
        override
        validStrategyUpdation(strategy)
    {
        require(strategy != address(0x0), "strategy cannot be zero address");
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            require(withdrawalQueue[i] != strategy, "strategy already queued");
        }

        withdrawalQueue.push(strategy);
        _organizeWithdrawalQueue();
    }

    function removeStrategyFromQueue(address strategy) external override {
        require(
            msg.sender == guardian || msg.sender == governance,
            "access restricted"
        );

        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            if (withdrawalQueue[i] == strategy) {
                withdrawalQueue[i] = address(0x0);
                _organizeWithdrawalQueue();
                return;
            }
        }

        require(false, "strategy not found");
    }

    function _debtOutstanding(address strategy)
        internal
        view
        returns (uint256)
    {
        if (debtRatio == 0) {
            return strategies[strategy].totalDebt;
        }

        uint256 strategyDebtLimit = strategies[strategy].debtRatio *
            (_totalAssets() / MAX_BPS);
        uint256 strategyTotalDebt = strategies[strategy].totalDebt;

        if (emergencyShutdown) {
            return strategyTotalDebt;
        } else if (strategyTotalDebt == strategyDebtLimit) {
            return 0;
        } else {
            return strategyTotalDebt - strategyDebtLimit;
        }
    }

    function debtOutstanding(address strategy)
        external
        view
        override
        returns (uint256)
    {
        return _debtOutstanding(strategy);
    }

    function _creditAvailable(address strategy)
        internal
        view
        returns (uint256)
    {
        if (emergencyShutdown) {
            return 0;
        }

        uint256 vaultTotalAssets = _totalAssets();
        uint256 vaultDebtLimit = debtRatio * (vaultTotalAssets / MAX_BPS);
        uint256 strategyDebtLimit = strategies[strategy].debtRatio *
            (vaultTotalAssets / MAX_BPS);
        uint256 strategyTotalDebt = strategies[strategy].totalDebt;
        uint256 strategyMinDebtPerHarvest = strategies[strategy]
            .minDebtPerHarvest;
        uint256 strategyMaxDebtPerHarvest = strategies[strategy]
            .maxDebtPerHarvest;

        if (
            strategyDebtLimit <= strategyTotalDebt ||
            vaultDebtLimit <= totalDebt
        ) {
            return 0;
        }

        uint256 available = strategyDebtLimit - strategyTotalDebt;
        available = Math.min(available, vaultDebtLimit - totalDebt);
        available = Math.min(available, token.balanceOf(address(this)));

        if (available < strategyMinDebtPerHarvest) {
            return 0;
        } else {
            return Math.min(available, strategyMaxDebtPerHarvest);
        }
    }

    function creditAvailable(address strategy)
        external
        view
        override
        returns (uint256)
    {
        return _creditAvailable(strategy);
    }

    function availableDepositLimit() external view override returns (uint256) {
        if (depositLimit > _totalAssets()) {
            return depositLimit - _totalAssets();
        } else {
            return 0;
        }
    }

    function _expectedReturn(address strategy) internal view returns (uint256) {
        uint256 strategyLastReport = strategies[strategy].lastReport;
        uint256 timeSinceLastHarvest = block.timestamp - strategyLastReport;
        uint256 totalHarvestTime = strategyLastReport -
            strategies[strategy].activation;

        if (
            timeSinceLastHarvest > 0 &&
            totalHarvestTime > 0 &&
            IStrategy(strategy).isActive()
        ) {
            return
                strategies[strategy].totalGain *
                (timeSinceLastHarvest / totalHarvestTime);
        } else {
            return 0;
        }
    }

    function expectedReturn(address strategy)
        external
        view
        override
        returns (uint256)
    {
        return _expectedReturn(strategy);
    }

    function _calcTotalFeeAndDisburseShares(
        uint256 duration,
        uint256 gain,
        address strategy
    ) internal returns (uint256 totalFee) {
        uint256 _managementFee = ((strategies[strategy].totalDebt -
            IStrategy(strategy).delegatedAssets()) *
            duration *
            managementFee) /
            MAX_BPS /
            SECS_PER_YEAR;
        uint256 _strategistFee = gain *
            (strategies[strategy].performanceFee / MAX_BPS);
        uint256 _performanceFee = gain * (performanceFee / MAX_BPS);

        totalFee = _managementFee + _strategistFee + _performanceFee;

        if (totalFee > gain) {
            totalFee = gain;
        }
        if (totalFee > 0) {
            uint256 reward = _issueSharesForAmount(address(this), totalFee);

            if (_strategistFee > 0) {
                uint256 strategistReward = _strategistFee * (reward / totalFee);
                IERC20Metadata(address(this)).safeTransfer(
                    strategy,
                    strategistReward
                );
            }

            if (IERC20Metadata(address(this)).balanceOf(address(this)) > 0) {
                IERC20Metadata(address(this)).safeTransfer(
                    rewards,
                    IERC20Metadata(address(this)).balanceOf(address(this))
                );
            }
        }
    }

    function _assessFees(address strategy, uint256 gain)
        internal
        returns (uint256)
    {
        if (strategies[strategy].activation == block.timestamp) {
            return 0;
        }

        uint256 duration = block.timestamp - strategies[strategy].lastReport;
        _nonZero(duration, "zero duration");

        if (gain == 0) {
            return 0;
        }

        uint256 totalFee = _calcTotalFeeAndDisburseShares(
            duration,
            gain,
            strategy
        );

        return totalFee;
    }

    function _reportLoss(address strategy, uint256 loss) internal {
        require(strategies[strategy].totalDebt >= loss, "lose exceeded debt");

        strategies[strategy].totalLoss += loss;
        strategies[strategy].totalDebt += strategies[strategy].totalDebt - loss;
        totalDebt = totalDebt - loss;
    }

    function report(
        uint256 gain,
        uint256 loss,
        uint256 _debtPayment
    ) external override returns (uint256 debt) {
        _nonZero(strategies[msg.sender].activation, "inactive strategy");
        require(
            token.balanceOf(msg.sender) >= gain + _debtPayment,
            "insufficient funds"
        );

        if (loss > 0) {
            _reportLoss(msg.sender, loss);
        }

        _assessFees(msg.sender, gain);
        uint256 credit = _creditAvailable(msg.sender);

        strategies[msg.sender].totalGain += gain;

        debt = _debtOutstanding(msg.sender);
        uint256 debtPayment = Math.min(_debtPayment, debt);

        if (debtPayment > 0) {
            strategies[msg.sender].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }

        if (credit > 0) {
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        }

        uint256 totalAvail = gain + debtPayment;
        if (totalAvail < credit) {
            token.safeTransfer(msg.sender, credit - totalAvail);
        } else if (totalAvail > credit) {
            token.safeTransferFrom(
                msg.sender,
                address(this),
                totalAvail - credit
            );
        }

        strategies[msg.sender].lastReport = block.timestamp;
        lastReport = block.timestamp;

        if (strategies[msg.sender].debtRatio == 0 || emergencyShutdown) {
            return IStrategy(msg.sender).estimatedTotalAssets();
        } else {
            return debt;
        }
    }

    function sweep(address _token, uint256 amount)
        external
        override
        onlyGovernance
    {
        _wantToken(_token);
        IERC20Metadata(_token).safeTransfer(governance, amount);
    }

    function _initialize(
        uint256 _depositLimit,
        address _token,
        address _governance,
        address _rewards,
        address _guardian,
        address _management
    ) internal {
        depositLimit = _depositLimit;
        token = IERC20Metadata(_token);

        governance = _governance;
        rewards = _rewards;
        guardian = _guardian;
        management = _management;

        performanceFee = 1000;
        managementFee = 200;

        lastReport = block.timestamp;
        activation = block.timestamp;
    }

    function _onlyGovernance() internal view {
        require(msg.sender == governance, "access :: Governance");
    }

    function _onlyGuardian() internal view {
        require(msg.sender == guardian, "access :: Guardian");
    }

    function _onlyManagement() internal view {
        require(msg.sender == management, "access :: Management");
    }

    function _onlyPendingGovernance() internal view {
        require(msg.sender == pendingGovernance, "access :: pendingGovernance");
    }

    function _onlyGovernanceGuardian() internal view {
        require(
            msg.sender == guardian || msg.sender == governance,
            "access restricted"
        );
    }

    function _nonZero(uint256 value, string memory message) internal pure {
        require(value > 0, message);
    }

    function _wantToken(address _token) internal view {
        require(_token != address(token), "cannot be want token");
    }

    function _validStrategyUpdation(address strategy) internal view {
        require(
            msg.sender == governance || msg.sender == management,
            "access restricted"
        );
        require(strategies[strategy].activation > 0, "strategy not activated");
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    modifier onlyGuardian() {
        _onlyGuardian();
        _;
    }

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    modifier validStrategyUpdation(address strategy) {
        _validStrategyUpdation(strategy);
        _;
    }
}
