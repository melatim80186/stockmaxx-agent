// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TokenizedStock
/// @notice ERC-20 testnet mirror of a Coinbase B20 tokenized stock.
/// @dev Mirrors the real B20 semantics that matter for an agent:
///      - 8 decimals (like real Coinbase tokenized equities, e.g. NVDAc)
///      - a `multiplier` (1e18 = 1.0) that scales token units to underlying
///        shares; changed only for corporate actions (split / dividend)
///      - `balanceOfUI` returns the share-equivalent balance (balance * multiplier)
///      - mint/burn restricted to the exchange (minter) contract
///      This is a TESTNET stand-in. It is NOT the real Coinbase token and
///      confers no claim on any underlying share. Real tokens on Base mainnet
///      are B20 precompiles (addresses start 0xb200...); see README.
contract TokenizedStock is ERC20, Ownable {
    /// @notice Ticker of the mirrored equity, e.g. "NVDA".
    string public ticker;
    /// @notice ISIN of the underlying stock, e.g. "US67066G1040" for NVDA.
    string public isin;
    /// @notice Multiplier scaled by 1e18. 1e18 = 1 token unit == 1 share.
    uint256 public multiplier;
    /// @notice Address allowed to mint/burn (the StockExchange).
    address public minter;

    event MultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, string reason);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    error OnlyMinter();
    error ZeroAddress();
    error InvalidMultiplier();

    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    constructor(string memory name_, string memory symbol_, string memory ticker_, string memory isin_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        ticker = ticker_;
        isin = isin_;
        multiplier = 1e18;
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /// @notice Share-equivalent balance (mirrors B20 `balanceOfUI`).
    function balanceOfUI(address account) external view returns (uint256) {
        return (balanceOf(account) * multiplier) / 1e18;
    }

    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert ZeroAddress();
        emit MinterUpdated(minter, newMinter);
        minter = newMinter;
    }

    /// @notice Adjust the multiplier for a corporate action (split/dividend).
    /// @dev Mirrors B20 behaviour: balances do not change, value scales.
    function setMultiplier(uint256 newMultiplier, string calldata reason) external onlyOwner {
        if (newMultiplier == 0) revert InvalidMultiplier();
        emit MultiplierUpdated(multiplier, newMultiplier, reason);
        multiplier = newMultiplier;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
