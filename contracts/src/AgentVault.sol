// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {StockExchange} from "./StockExchange.sol";

/// @title AgentVault
/// @notice The autonomous agent's on-chain wallet + decision journal.
/// @dev The agent is an off-chain program holding ONE EOA key (the operator).
///      That key can ONLY:
///        - log decisions (signal + action + price + confidence + reason hash)
///        - execute trades through the StockExchange, bounded by guardrails
///      It can NEVER withdraw funds, change limits, pause, or touch the owner.
///      The owner (user) can pause, withdraw everything, rotate the operator,
///      and tighten/loosen limits at any time. This is the "walk away" safety
///      model: worst case for a compromised/buggy agent is bounded trading
///      inside the guardrails, never loss of custody.
///      Every decision — including HOLD — is emitted on-chain, which is the
///      verifiable on-chain traction trail for the hackathon judges:
///      decisions and trades are queryable from the vault's events alone.
contract AgentVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Action {
        HOLD,
        BUY,
        SELL
    }

    IERC20 public immutable usdc;
    StockExchange public immutable exchange;

    /// @notice The agent's EOA. Only this address may trade / log decisions.
    address public operator;

    /// @notice Max notional (USDC, 6 dec) of a single trade.
    uint256 public maxTradeUsd = 100 * 1e6;
    /// @notice Max number of trades per UTC day (anti-runaway).
    uint256 public maxTradesPerDay = 10;
    /// @notice Max position value (USDC, 6 dec) the vault may hold in one symbol.
    uint256 public maxPositionUsd = 400 * 1e6;

    mapping(bytes32 => bool) public allowedSymbols;
    mapping(bytes32 => uint256) public positionUsd; // tracked notional per symbol (6 dec)
    mapping(uint256 => uint256) public tradesPerDay; // day number => count

    event DecisionLogged(
        address indexed operator,
        bytes32 indexed symbol,
        Action action,
        int256 price,
        uint256 confidenceBps,
        bytes32 reasonHash,
        uint256 timestamp
    );
    event TradeExecuted(
        address indexed operator, bytes32 indexed symbol, Action action, uint256 usdcAmount, uint256 stockAmount, int256 price
    );
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event LimitsUpdated(uint256 maxTradeUsd, uint256 maxTradesPerDay, uint256 maxPositionUsd);
    event SymbolAllowlisted(bytes32 indexed symbol, bool allowed);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    error OnlyOperator();
    error SymbolNotAllowed();
    error TradeTooLarge();
    error PositionTooLarge();
    error DailyTradeCapReached();
    error ZeroAmount();
    error ZeroAddress();

    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    constructor(address usdc_, address exchange_, address operator_) Ownable(msg.sender) {
        if (usdc_ == address(0) || exchange_ == address(0) || operator_ == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
        exchange = StockExchange(exchange_);
        operator = operator_;
        // The vault pre-approves the exchange to pull USDC for buys.
        // Sell-side needs no approval: the exchange burns stock directly as minter.
        IERC20(usdc_).approve(exchange_, type(uint256).max);
    }

    // ---- owner controls ----

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        emit OperatorUpdated(operator, newOperator);
        operator = newOperator;
    }

    function setLimits(uint256 newMaxTradeUsd, uint256 newMaxTradesPerDay, uint256 newMaxPositionUsd) external onlyOwner {
        maxTradeUsd = newMaxTradeUsd;
        maxTradesPerDay = newMaxTradesPerDay;
        maxPositionUsd = newMaxPositionUsd;
        emit LimitsUpdated(newMaxTradeUsd, newMaxTradesPerDay, newMaxPositionUsd);
    }

    function setSymbolAllowed(bytes32 symbol, bool allowed) external onlyOwner {
        allowedSymbols[symbol] = allowed;
        emit SymbolAllowlisted(symbol, allowed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Owner-only rescue: withdraw any token (USDC or stock) to any address.
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    // ---- agent (operator) actions ----

    /// @notice Log one decision on-chain. Called every agent cycle, even for HOLD,
    ///         so the full reasoning trail is verifiable without trusting the agent's logs.
    function logDecision(bytes32 symbol, Action action, int256 price, uint256 confidenceBps, bytes32 reasonHash)
        external
        onlyOperator
        whenNotPaused
    {
        emit DecisionLogged(msg.sender, symbol, action, price, confidenceBps, reasonHash, block.timestamp);
    }

    /// @notice Batch-log one cycle's decisions in a single tx (cheaper + fewer
    ///         sequential nonces than one tx per symbol).
    function logDecisions(
        bytes32[] calldata symbols,
        Action[] calldata actions,
        int256[] calldata prices,
        uint256[] calldata confidencesBps,
        bytes32[] calldata reasonHashes
    ) external onlyOperator whenNotPaused {
        uint256 n = symbols.length;
        require(
            actions.length == n && prices.length == n && confidencesBps.length == n && reasonHashes.length == n,
            "length mismatch"
        );
        for (uint256 i = 0; i < n; i++) {
            emit DecisionLogged(msg.sender, symbols[i], actions[i], prices[i], confidencesBps[i], reasonHashes[i], block.timestamp);
        }
    }

    /// @notice Execute a BUY through the exchange, inside the guardrails.
    /// @param usdcAmount USDC to spend (6 dec). Vault must hold it + have approved the exchange.
    function executeBuy(bytes32 symbol, uint256 usdcAmount) external onlyOperator nonReentrant whenNotPaused {
        if (!allowedSymbols[symbol]) revert SymbolNotAllowed();
        if (usdcAmount == 0) revert ZeroAmount();
        if (usdcAmount > maxTradeUsd) revert TradeTooLarge();
        if (positionUsd[symbol] + usdcAmount > maxPositionUsd) revert PositionTooLarge();
        _checkDailyCap();
        uint256 stockOut = exchange.buy(symbol, usdcAmount);
        positionUsd[symbol] += usdcAmount;
        emit TradeExecuted(msg.sender, symbol, Action.BUY, usdcAmount, stockOut, _price(symbol));
    }

    /// @notice Execute a SELL through the exchange, inside the guardrails.
    /// @param stockAmount Stock tokens to sell (8 dec).
    function executeSell(bytes32 symbol, uint256 stockAmount) external onlyOperator nonReentrant whenNotPaused {
        if (!allowedSymbols[symbol]) revert SymbolNotAllowed();
        if (stockAmount == 0) revert ZeroAmount();
        (uint256 usdcOut,) = exchange.quoteSell(symbol, stockAmount);
        if (usdcOut > maxTradeUsd) revert TradeTooLarge();
        _checkDailyCap();
        uint256 got = exchange.sell(symbol, stockAmount);
        if (positionUsd[symbol] >= got) positionUsd[symbol] -= got;
        else positionUsd[symbol] = 0;
        emit TradeExecuted(msg.sender, symbol, Action.SELL, got, stockAmount, _price(symbol));
    }

    // ---- views ----

    /// @notice Current UTC-day trade count (for dashboards).
    function tradesToday() external view returns (uint256) {
        return tradesPerDay[block.timestamp / 1 days];
    }

    function _checkDailyCap() internal {
        uint256 day = block.timestamp / 1 days;
        if (tradesPerDay[day] >= maxTradesPerDay) revert DailyTradeCapReached();
        tradesPerDay[day] += 1;
    }

    function _price(bytes32 symbol) internal view returns (int256) {
        return exchange.oracle().getPrice(symbol);
    }
}
