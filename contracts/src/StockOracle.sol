// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title StockOracle
/// @notice Minimal Chainlink AggregatorV3-compatible price oracle for tokenized stocks.
/// @dev On Base mainnet each Coinbase tokenized equity has a real Chainlink
///      feed (24/5, holds last close outside market hours, freezes during
///      corporate actions). This contract mirrors that interface so the
///      exchange + vault code is IDENTICAL on mainnet — only the feed address
///      changes (see README "Mainnet path").
///      On testnet the agent (updater) posts prices fetched from the public
///      Bankr index API / Coinbase Tokenized Stocks API reference values.
///      Consumers must respect `maxAge` staleness bounds, exactly as the
///      Base docs advise for `nav_price_updated_at`.
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract StockOracle is Ownable, IAggregatorV3 {
    struct Feed {
        int256 price; // USD, 8 decimals (Chainlink convention)
        uint256 updatedAt;
        uint80 roundId;
        bool exists;
    }

    /// @notice Maximum age of a price before consumers must treat it as stale.
    uint256 public maxAge = 1 days;
    /// @notice Address allowed to post prices (the agent off-chain updater).
    address public updater;

    mapping(bytes32 => Feed) private _feeds;

    event PriceUpdated(bytes32 indexed symbol, int256 price, uint256 updatedAt, uint80 roundId);
    event UpdaterUpdated(address indexed oldUpdater, address indexed newUpdater);
    event MaxAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);

    error OnlyUpdater();
    error FeedNotFound();
    error StalePrice();
    error InvalidPrice();
    error ZeroAddress();

    modifier onlyUpdater() {
        if (msg.sender != updater) revert OnlyUpdater();
        _;
    }

    constructor(address updater_) Ownable(msg.sender) {
        if (updater_ == address(0)) revert ZeroAddress();
        updater = updater_;
    }

    function setUpdater(address newUpdater) external onlyOwner {
        if (newUpdater == address(0)) revert ZeroAddress();
        emit UpdaterUpdated(updater, newUpdater);
        updater = newUpdater;
    }

    function setMaxAge(uint256 newMaxAge) external onlyOwner {
        emit MaxAgeUpdated(maxAge, newMaxAge);
        maxAge = newMaxAge;
    }

    /// @notice Post a price for a symbol (ticker bytes32, e.g. bytes32("NVDA")).
    function updatePrice(bytes32 symbol, int256 price) external onlyUpdater {
        if (price <= 0) revert InvalidPrice();
        Feed storage f = _feeds[symbol];
        f.price = price;
        f.updatedAt = block.timestamp;
        f.roundId += 1;
        f.exists = true;
        emit PriceUpdated(symbol, price, block.timestamp, f.roundId);
    }

    /// @notice Post several prices in one tx (one agent cycle).
    function updatePrices(bytes32[] calldata symbols, int256[] calldata prices) external onlyUpdater {
        require(symbols.length == prices.length, "length mismatch");
        for (uint256 i = 0; i < symbols.length; i++) {
            if (prices[i] <= 0) revert InvalidPrice();
            Feed storage f = _feeds[symbols[i]];
            f.price = prices[i];
            f.updatedAt = block.timestamp;
            f.roundId += 1;
            f.exists = true;
            emit PriceUpdated(symbols[i], prices[i], block.timestamp, f.roundId);
        }
    }

    /// @notice Current price for a symbol, reverts if missing or stale.
    function getPrice(bytes32 symbol) external view returns (int256) {
        Feed storage f = _feeds[symbol];
        if (!f.exists) revert FeedNotFound();
        if (block.timestamp - f.updatedAt > maxAge) revert StalePrice();
        return f.price;
    }

    /// @notice Raw feed view (no staleness revert) for dashboards / monitoring.
    function getFeed(bytes32 symbol) external view returns (int256 price, uint256 updatedAt, uint80 roundId, bool exists) {
        Feed storage f = _feeds[symbol];
        return (f.price, f.updatedAt, f.roundId, f.exists);
    }

    // ---- IAggregatorV3 (single-feed view, kept for interface compat) ----
    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "StockMaxx testnet stock oracle (Chainlink-compatible)";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        revert("use getFeed(symbol)");
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        revert("use getFeed(symbol)");
    }
}
