// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./interfaces/IVault.sol";

import "../../lib/openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../lib/openzeppelin/contracts/utils/math/Math.sol";

abstract contract Vault is IVault, ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Metadata;

    string public constant API_VERSION = "1.0.0";
    uint256 public constant MAX_BPS = 10000;
    uint256 private constant MAX_UINT256 = type(uint256).max;

    IERC20Metadata public token;
    address public governance;
    address public pendingGovernance;
    address public management;
    address public guardian;

    mapping(address => StrategyParams) public strategies;
    uint256 public strategiesCount;
    address[] public withdrawalQueue;

    bool public emergencyShutdown;

    uint256 public depositLimit;
    uint256 public debtRatio;
    uint256 public totalDebt;
    uint256 public lastReport;
    uint256 public activation;

    address public rewards;
    uint256 public managementFee;
    uint256 public performanceFee;

    constructor(
        address _token,
        address _governance,
        address _rewards,
        address _guardian,
        address _management,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _initialize(_token, _governance, _rewards, _guardian, _management);
    }

    function apiVersion() external pure override returns (string memory) {
        return API_VERSION;
    }

    function setGovernance(address _governance) external onlyGovernance {
        pendingGovernance = _governance;
    }

    function acceptGovernance() external {
        require(
            msg.sender == pendingGovernance,
            "access :: only pendingGovernance"
        );
        governance = msg.sender;
    }

    function setManangement(address _management) external onlyGovernance {
        management = _management;
    }

    function setRewards(address _rewards) external onlyGovernance {
        require(
            _rewards != address(0x0) && rewards != address(this),
            "Invalid rewards address"
        );
        rewards = _rewards;
    }

    function setGuardian(address _guardian) external {
        require(
            msg.sender == guardian || msg.sender == governance,
            "only guardian|governance"
        );
        guardian = _guardian;
    }

    function setDepositLimit(uint256 _depositLimit) external onlyGovernance {
        depositLimit = _depositLimit;
    }

    function setPerformanceFee(uint256 _performanceFee)
        external
        onlyGovernance
    {
        require(_performanceFee <= MAX_BPS / 2, "fee too high");
        performanceFee = _performanceFee;
    }

    function setManagementFee(uint256 _managementFee) external onlyGovernance {
        require(_managementFee <= MAX_BPS, "fee too high");
        managementFee = _managementFee;
    }

    function setEmergencyShutdown(bool _active) external {
        if (_active) {
            require(
                msg.sender == guardian || msg.sender == governance,
                "only guardian|governance"
            );
        } else {
            require(msg.sender == governance, "access: onlyGovernance");
        }

        emergencyShutdown = _active;
    }

    function setWithdrawalQueue(address[] memory queue) external override {
        require(
            queue.length > 0 && queue.length <= strategiesCount,
            "Invalid withdrawal Queue"
        );

        for (uint256 i = 0; i < queue.length; i++) {
            withdrawalQueue[i] = queue[i];
        }
        for (uint256 i = queue.length; i < withdrawalQueue.length; i++) {
            withdrawalQueue[i] = address(0x0);
        }
    }

    function _totalAssets() internal view returns (uint256) {
        return token.balanceOf(address(this)) + totalDebt;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    function _issueSharesForAmount(address to, uint256 amount)
        internal
        returns (uint256 shares)
    {
        uint256 totalSupply = totalSupply();

        if (totalSupply > 0) {
            shares = amount.mul(totalSupply.div(_totalAssets()));
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
        returns (uint256 sharesOut)
    {
        _depositHealthCheck();
        require(_amount > 0, "amount cannot be zero");
        require(_totalAssets() + _amount <= depositLimit, "excess deposit");

        sharesOut = _issueSharesForAmount(recepient, _amount);
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function deposit(address recepient) external returns (uint256 sharesOut) {
        _depositHealthCheck();
        uint256 _amount = Math.min(
            depositLimit - _totalAssets(),
            token.balanceOf(msg.sender)
        );

        require(_amount > 0, "amount cannot be zero");

        sharesOut = _issueSharesForAmount(recepient, _amount);
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function _shareValue(uint256 shares) internal view returns (uint256) {
        if (totalSupply() == 0) {
            return shares;
        }

        return shares.mul(_totalAssets().div(totalSupply()));
    }

    function _sharesForAmount(uint256 amount) internal view returns (uint256) {
        uint256 freeFunds = _totalAssets();

        if (freeFunds <= 0) {
            return 0;
        }

        return amount.mul(totalSupply().div(freeFunds));
    }

    function maxAvailableShares()
        external
        view
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

    function _initialize(
        address _token,
        address _governance,
        address _rewards,
        address _guardian,
        address _management
    ) internal {
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

    modifier onlyGovernance() {
        require(msg.sender == governance, "access :: onlyGovernance");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "access :: onlyGuardian");
        _;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "access :: onlyManagement");
        _;
    }
}
