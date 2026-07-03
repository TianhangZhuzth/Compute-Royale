// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlloyMeme} from "./AlloyMeme.sol";
import {
    INonfungiblePositionManager,
    ISwapRouter02
} from "./interfaces/IUniswap.sol";

/// @notice ALLOY — launchpad for dividend memecoins backed by real stocks.
///
///         launch() deploys a fixed-supply AlloyMeme, opens a Uniswap V3 pool
///         (1% tier) against USDG, seeds the ENTIRE supply as single-sided
///         liquidity, and locks the LP NFT forever inside this contract. The
///         coin trades from block one and its liquidity can never be pulled.
///
///         sweep() is permissionless: it collects the pool's trading fees and
///         routes them — the drip share BUYS the coin's backing stock and
///         distributes it to holders (who claim it to their wallets), the
///         creator share pays the launcher, and the protocol share buys back
///         $ALLOY. Just by holding, holders passively accumulate real equities.
contract AlloyLaunchpad is Ownable {
    using SafeERC20 for IERC20;

    uint24 public constant POOL_FEE = 10_000; // 1% tier, tick spacing 200
    int24 internal constant MAX_USABLE_TICK = 887_200;
    uint256 public constant SUPPLY = 1_000_000_000 ether; // 1B fixed supply
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter02 public immutable swapRouter;
    address public immutable usdg; // dollar quote asset (6 decimals)

    // Deterministic launch price boundary (precomputed for the USDG pair).
    int24 public immutable startTick;
    uint160 public immutable sqrtPriceLowX96; // getSqrtRatioAtTick(-startTick)
    uint160 public immutable sqrtPriceHighX96; // getSqrtRatioAtTick(+startTick)

    // Fee routing (basis points, must sum to 10_000).
    uint16 public dripBps = 7_000; // buys backing stock, dripped to holders
    uint16 public creatorBps = 2_000; // paid to the launcher
    uint16 public alloyBps = 1_000; // buys back $ALLOY (else reserved)

    uint256 public creationFee;
    address public treasury;

    // $ALLOY utility hooks.
    address public alloyToken; // 0 until $ALLOY is live
    uint24 public alloyFee = 10_000; // USDG/$ALLOY pool fee tier
    address public alloySink; // where bought-back $ALLOY goes (treasury/staking)
    uint256 public freeLaunchThreshold; // hold this much $ALLOY → launch free

    struct Meme {
        address creator;
        address pool;
        address reward; // the backing stock dripped to holders
        uint24 rewardFee; // USDG/reward pool fee tier
        uint256 lpId;
        uint64 createdAt;
    }

    mapping(address => Meme) public meme;
    address[] public allMemes;

    event MemeLaunched(
        address indexed token,
        address indexed creator,
        address pool,
        address indexed reward,
        uint256 lpId,
        string name,
        string symbol,
        string info
    );
    event Swept(
        address indexed token,
        uint256 stockBought,
        uint256 creatorPaid,
        uint256 alloyBoughtBack
    );

    constructor(
        address positionManager_,
        address swapRouter_,
        address usdg_,
        address treasury_,
        uint256 creationFee_,
        int24 startTick_,
        uint160 sqrtPriceLowX96_,
        uint160 sqrtPriceHighX96_
    ) Ownable(msg.sender) {
        require(startTick_ > 0 && startTick_ % 200 == 0 && startTick_ < MAX_USABLE_TICK, "tick");
        positionManager = INonfungiblePositionManager(positionManager_);
        swapRouter = ISwapRouter02(swapRouter_);
        usdg = usdg_;
        treasury = treasury_;
        creationFee = creationFee_;
        startTick = startTick_;
        sqrtPriceLowX96 = sqrtPriceLowX96_;
        sqrtPriceHighX96 = sqrtPriceHighX96_;
        alloySink = treasury_;
    }

    // --- launch ---

    /// @notice Launch a dividend memecoin backed by a real stock.
    /// @param reward    The tokenized stock dripped to holders.
    /// @param rewardFee The USDG/reward Uniswap fee tier (its pool must exist).
    /// @param info      Packed metadata (logo, links) stored on the token.
    /// @param salt      CREATE2 salt, mixed with msg.sender.
    function launch(
        string calldata name,
        string calldata symbol,
        string calldata info,
        address reward,
        uint24 rewardFee,
        bytes32 salt
    ) external payable returns (address token) {
        require(reward != address(0) && reward != usdg, "reward");

        bool free = freeLaunchThreshold > 0
            && alloyToken != address(0)
            && IERC20(alloyToken).balanceOf(msg.sender) >= freeLaunchThreshold;
        if (!free) require(msg.value >= creationFee, "fee");

        AlloyMeme t = new AlloyMeme{salt: keccak256(abi.encode(msg.sender, salt))}(
            name, symbol, info, SUPPLY, address(this), reward, msg.sender, address(this)
        );
        token = address(t);

        // The whole supply is minted here; exclude this + the future pool so
        // drips only ever reach real holders (never the pool or the launchpad).
        t.exclude(address(this));
        t.exclude(DEAD);

        (address pool, uint256 lpId) = _seed(t);

        uint256 dust = t.balanceOf(address(this));
        if (dust > 0) t.transfer(DEAD, dust);

        meme[token] = Meme({
            creator: msg.sender,
            pool: pool,
            reward: reward,
            rewardFee: rewardFee,
            lpId: lpId,
            createdAt: uint64(block.timestamp)
        });
        allMemes.push(token);

        emit MemeLaunched(token, msg.sender, pool, reward, lpId, name, symbol, info);

        if (!free && creationFee > 0) {
            (bool ok,) = treasury.call{value: creationFee}("");
            require(ok, "treasury");
            uint256 refund = msg.value - creationFee;
            if (refund > 0) {
                (ok,) = msg.sender.call{value: refund}("");
                require(ok, "refund");
            }
        } else if (msg.value > 0) {
            (bool ok,) = msg.sender.call{value: msg.value}("");
            require(ok, "refund");
        }
    }

    /// @dev Open the memecoin/USDG pool at the launch price and seed the whole
    ///      supply single-sided, then lock the LP here. Excludes the pool from
    ///      drips. Split out to keep launch()'s stack shallow.
    function _seed(AlloyMeme t) internal returns (address pool, uint256 lpId) {
        address token = address(t);
        INonfungiblePositionManager.MintParams memory p;
        uint160 sqrtPriceX96;
        if (token < usdg) {
            p.token0 = token;
            p.token1 = usdg;
            p.tickLower = -startTick;
            p.tickUpper = MAX_USABLE_TICK;
            p.amount0Desired = SUPPLY;
            sqrtPriceX96 = sqrtPriceLowX96;
        } else {
            p.token0 = usdg;
            p.token1 = token;
            p.tickLower = -MAX_USABLE_TICK;
            p.tickUpper = startTick;
            p.amount1Desired = SUPPLY;
            sqrtPriceX96 = sqrtPriceHighX96;
        }
        p.fee = POOL_FEE;
        p.recipient = address(this); // LP stays here, locked forever
        p.deadline = block.timestamp;

        pool = positionManager.createAndInitializePoolIfNecessary(
            p.token0, p.token1, POOL_FEE, sqrtPriceX96
        );
        t.exclude(pool);

        t.approve(address(positionManager), SUPPLY);
        (lpId,,,) = positionManager.mint(p);
    }

    // --- fee sweep (permissionless) ---

    /// @notice Collect a coin's trading fees and route them: buy its backing
    ///         stock and drip it to holders, pay the creator, buy back $ALLOY.
    ///         Anyone may call it; the more it trades, the fatter the drip.
    function sweep(address token) external {
        Meme storage m = meme[token];
        require(m.pool != address(0), "unknown");

        (uint256 a0, uint256 a1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: m.lpId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        bool tokenIs0 = token < usdg;
        uint256 usdgAmt = tokenIs0 ? a1 : a0;
        uint256 memeFee = tokenIs0 ? a0 : a1;
        // Convert the memecoin-side fees to USDG so everything routes in dollars.
        if (memeFee > 0) usdgAmt += _swap(token, usdg, POOL_FEE, memeFee, address(this));
        require(usdgAmt > 0, "nothing");

        _route(token, m.reward, m.rewardFee, m.creator, usdgAmt);
    }

    /// @dev Split `usdgAmt` of collected fees: buy the backing stock and drip
    ///      it to holders, pay the creator, buy back $ALLOY.
    function _route(
        address token,
        address reward,
        uint24 rewardFee,
        address creator,
        uint256 usdgAmt
    ) internal {
        uint256 dripUsdg = (usdgAmt * dripBps) / 10_000;
        uint256 alloyUsdg = (usdgAmt * alloyBps) / 10_000;

        uint256 stockBought;
        if (dripUsdg > 0) {
            // Drip only reaches real holders; before anyone holds, reserve it.
            if (AlloyMeme(token).eligibleSupply() > 0) {
                stockBought = _swap(usdg, reward, rewardFee, dripUsdg, token);
                AlloyMeme(token).distribute(stockBought);
            } else {
                IERC20(usdg).safeTransfer(treasury, dripUsdg);
            }
        }

        uint256 alloyBought;
        if (alloyUsdg > 0) {
            if (alloyToken != address(0)) {
                alloyBought = _swap(usdg, alloyToken, alloyFee, alloyUsdg, alloySink);
            } else {
                IERC20(usdg).safeTransfer(treasury, alloyUsdg); // reserve
            }
        }

        uint256 creatorUsdg = usdgAmt - dripUsdg - alloyUsdg;
        if (creatorUsdg > 0) IERC20(usdg).safeTransfer(creator, creatorUsdg);

        emit Swept(token, stockBought, creatorUsdg, alloyBought);
    }

    /// @dev exactInputSingle with no slippage guard (fee-sized amounts only).
    function _swap(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, address to)
        internal
        returns (uint256 out)
    {
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);
        out = swapRouter.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: to,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // --- views ---

    function totalMemes() external view returns (uint256) {
        return allMemes.length;
    }

    function getMemes(uint256 start, uint256 count)
        external
        view
        returns (address[] memory page)
    {
        uint256 len = allMemes.length;
        if (start >= len) return new address[](0);
        uint256 end = start + count;
        if (end > len) end = len;
        page = new address[](end - start);
        for (uint256 i = start; i < end; i++) page[i - start] = allMemes[i];
    }

    // --- admin ---

    function setFeeSplit(uint16 drip, uint16 creator, uint16 alloy) external onlyOwner {
        require(uint256(drip) + creator + alloy == 10_000, "bps");
        dripBps = drip;
        creatorBps = creator;
        alloyBps = alloy;
    }

    function setCreationFee(uint256 fee) external onlyOwner {
        creationFee = fee;
    }

    function setTreasury(address t) external onlyOwner {
        treasury = t;
    }

    function setAlloy(address token, uint24 fee, address sink, uint256 freeThreshold)
        external
        onlyOwner
    {
        alloyToken = token;
        alloyFee = fee;
        alloySink = sink == address(0) ? treasury : sink;
        freeLaunchThreshold = freeThreshold;
    }
}
