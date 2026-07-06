// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice A dividend-paying memecoin: holders continuously accrue a reward
///         token (a real tokenized stock) in proportion to their balance.
///         The keeper buys the stock from trading fees, sends it here, and
///         calls distribute(). Holders claim their share to their wallet.
///
///         Excluded addresses (the AMM pool, the LP locker) do not accrue —
///         drips only reach real holders. Exclusions are set once at launch,
///         before any distribution, so no accrued rewards are ever stranded.
contract AlloyMeme is ERC20 {
    using SafeERC20 for IERC20;

    uint256 private constant MAG = 2 ** 128;

    IERC20 public immutable reward; // the backing stock dripped to holders
    address public immutable factory;
    address public immutable creator;
    string public info; // packed metadata (logo, links) — JSON string

    uint256 public magPerShare; // magnified reward accrued per eligible share
    uint256 public eligibleSupply; // supply held by non-excluded addresses
    uint256 public totalDistributed;
    mapping(address => int256) private corrections;
    mapping(address => uint256) public withdrawn;
    mapping(address => bool) public excluded;

    event Distributed(uint256 amount, uint256 eligibleSupply);
    event Claimed(address indexed holder, uint256 amount);
    event Excluded(address indexed account);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory info_,
        uint256 supply,
        address mintTo,
        address reward_,
        address creator_,
        address factory_
    ) ERC20(name_, symbol_) {
        reward = IERC20(reward_);
        creator = creator_;
        factory = factory_;
        info = info_;
        _mint(mintTo, supply);
    }

    // --- exclusions (launch setup only) ---

    /// @notice Exclude an address (the pool / locker) from drips. Callable by
    ///         the factory, only before any distribution has happened.
    function exclude(address account) external {
        require(msg.sender == factory, "auth");
        require(magPerShare == 0, "started");
        if (excluded[account]) return;
        excluded[account] = true;
        uint256 b = balanceOf(account);
        if (b > 0) eligibleSupply -= b; // remove from the eligible pool
        emit Excluded(account);
    }

    // --- dividend accounting ---

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        bool fe = from == address(0) || excluded[from];
        bool te = to == address(0) || excluded[to];
        int256 mag = int256(magPerShare);
        if (!fe) {
            eligibleSupply -= value;
            corrections[from] += mag * int256(value);
        }
        if (!te) {
            eligibleSupply += value;
            corrections[to] -= mag * int256(value);
        }
    }

    /// @notice Distribute reward tokens already sent to this contract to all
    ///         eligible holders, pro-rata. Anyone (the keeper) may call it.
    function distribute(uint256 amount) external {
        require(eligibleSupply > 0, "no holders");
        require(amount > 0, "amount");
        magPerShare += (amount * MAG) / eligibleSupply;
        totalDistributed += amount;
        emit Distributed(amount, eligibleSupply);
    }

    /// @notice Total reward ever accrued to an account.
    function accrued(address a) public view returns (uint256) {
        if (excluded[a]) return 0;
        int256 total = int256(magPerShare * balanceOf(a)) + corrections[a];
        return total < 0 ? 0 : uint256(total) / MAG;
    }

    /// @notice Reward currently claimable by an account.
    function claimable(address a) public view returns (uint256) {
        return accrued(a) - withdrawn[a];
    }

    /// @notice Send an account's claimable reward to its wallet.
    function claim() external returns (uint256 amount) {
        amount = claimable(msg.sender);
        require(amount > 0, "nothing");
        withdrawn[msg.sender] += amount;
        reward.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }
}


