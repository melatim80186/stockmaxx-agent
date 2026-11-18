// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockUSDC
/// @notice Testnet stand-in for USDC (6 decimals, like real USDC).
/// @dev On Base mainnet the agent uses real USDC (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913).
///      This contract exists ONLY for Base Sepolia demo / local testing.
contract MockUSDC is ERC20, Ownable {
    constructor() ERC20("Mock USDC", "mUSDC") Ownable(msg.sender) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint test USDC. Owner is the deployer; in demo the deployer
    /// funds the AgentVault with a fixed, documented amount.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
