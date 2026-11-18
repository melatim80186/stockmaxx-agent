// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TokenizedStock} from "./TokenizedStock.sol";
import {StockOracle} from "./StockOracle.sol";

/// @title StockExchange
/// @notice Primary buy/sell venue for testnet tokenized stocks vs USDC at the oracle price.
/// @dev Mirrors a primary issuance/redemption venue: buying mints stock tokens
///      against USDC at the oracle (NAV) price, selling burns them and returns
///      USDC. A small fee (bps) goes to the fee recipient. All amounts are
///      computed from the oracle price with explicit staleness enforcement in
///      the oracle itself, so a stale feed reverts the trade instead of
///      executing at a bad price.
///      Mainnet path: replace this venue with the real market (Aerodrome /
///      Uniswap pools for B20 tokens, or the issuer redemption flow) — the
///      AgentVault only depends on the `buy`/`sell` interface shape.
contract StockExchange is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc; // 6 decimals
    StockOracle public immutable oracle;

    /// @notice Fee in basis points (100 = 1%). Charged on both buy and sell.
    uint256 public feeBps = 10; // 0.10%
    address public feeRecipient;
    /// @notice Per-trade notional cap (USDC, 6 decimals) — venue-level guardrail.
    uint256 public maxTradeUsd = 10_000 * 1e6;

    mapping(bytes32 => address) public stockBySymbol;

    event StockListed(bytes32 indexed symbol, address indexed token);
    event Bought(address indexed buyer, bytes32 indexed symbol, uint256 usdcIn, uint256 stockOut, int256 price);
    event Sold(address indexed seller, bytes32 indexed symbol, uint256 stockIn, uint256 usdcOut, int256 price);
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event MaxTradeUpdated(uint256 oldMax, uint256 newMax);

    error UnknownSymbol();
    error ZeroAmount();
    error TradeTooLarge();
    error ZeroAddress();
    error FeeTooHigh();

    constructor(address usdc_, address oracle_, address feeRecipient_) Ownable(msg.sender) {
        if (usdc_ == address(0) || oracle_ == address(0) || feeRecipient_ == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
        oracle = StockOracle(oracle_);
        feeRecipient = feeRecipient_;
    }

    function listStock(bytes32 symbol, address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        stockBySymbol[symbol] = token;
        emit StockListed(symbol, token);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > 100) revert FeeTooHigh(); // max 1%
        emit FeeUpdated(feeBps, newFeeBps);
        feeBps = newFeeBps;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    function setMaxTradeUsd(uint256 newMax) external onlyOwner {
        emit MaxTradeUpdated(maxTradeUsd, newMax);
        maxTradeUsd = newMax;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Quote: how many stock tokens (8 dec) for `usdcAmount` (6 dec), net of fee.
    function quoteBuy(bytes32 symbol, uint256 usdcAmount) public view returns (uint256 stockOut, uint256 fee) {
        address token = stockBySymbol[symbol];
        if (token == address(0)) revert UnknownSymbol();
        int256 price = oracle.getPrice(symbol); // USD, 8 dec
        fee = (usdcAmount * feeBps) / 10_000;
        uint256 netUsdc = usdcAmount - fee;
        // stockOut (8 dec) = netUsdc (6 dec) * 1e8 / price (8 dec) * 1e6/1e6
        // usd value (8 dec) = netUsdc * 1e2 ; stock = usdValue * 1e8 / price
        stockOut = (netUsdc * 1e2 * 1e8) / uint256(price);
    }

    /// @notice Quote: how much USDC (6 dec) for `stockAmount` (8 dec), net of fee.
    function quoteSell(bytes32 symbol, uint256 stockAmount) public view returns (uint256 usdcOut, uint256 fee) {
        address token = stockBySymbol[symbol];
        if (token == address(0)) revert UnknownSymbol();
        int256 price = oracle.getPrice(symbol);
        uint256 grossUsdc = (stockAmount * uint256(price)) / 1e10; // 8dec * 8dec / 1e10 -> 6 dec
        fee = (grossUsdc * feeBps) / 10_000;
        usdcOut = grossUsdc - fee;
    }

    /// @notice Buy stock tokens with USDC. Caller must approve USDC first.
    function buy(bytes32 symbol, uint256 usdcAmount) external nonReentrant whenNotPaused returns (uint256 stockOut) {
        if (usdcAmount == 0) revert ZeroAmount();
        if (usdcAmount > maxTradeUsd) revert TradeTooLarge();
        address token = stockBySymbol[symbol];
        if (token == address(0)) revert UnknownSymbol();
        uint256 fee;
        (stockOut, fee) = quoteBuy(symbol, usdcAmount);
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        if (fee > 0) usdc.safeTransfer(feeRecipient, fee);
        TokenizedStock(token).mint(msg.sender, stockOut);
        emit Bought(msg.sender, symbol, usdcAmount, stockOut, oracle.getPrice(symbol));
    }

    /// @notice Sell stock tokens for USDC. Caller must approve the stock token first.
    function sell(bytes32 symbol, uint256 stockAmount) external nonReentrant whenNotPaused returns (uint256 usdcOut) {
        if (stockAmount == 0) revert ZeroAmount();
        address token = stockBySymbol[symbol];
        if (token == address(0)) revert UnknownSymbol();
        uint256 fee;
        (usdcOut, fee) = quoteSell(symbol, stockAmount);
        if (usdcOut > maxTradeUsd) revert TradeTooLarge();
        TokenizedStock(token).burn(msg.sender, stockAmount);
        usdc.safeTransfer(msg.sender, usdcOut);
        if (fee > 0) usdc.safeTransfer(feeRecipient, fee);
        emit Sold(msg.sender, symbol, stockAmount, usdcOut, oracle.getPrice(symbol));
    }
}
