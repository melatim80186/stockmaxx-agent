// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {TokenizedStock} from "../src/TokenizedStock.sol";
import {StockOracle} from "../src/StockOracle.sol";
import {StockExchange} from "../src/StockExchange.sol";
import {AgentVault} from "../src/AgentVault.sol";

/// @notice Deploy the full StockMaxx stack.
/// @dev Env vars:
///      OPERATOR  - agent EOA (operator of the vault + oracle updater). Default: deployer.
///      VAULT_USDC - test USDC minted to the vault (6 dec). Default: 1000.
///      PRICE_NVDA / PRICE_AAPL / PRICE_TSLA / PRICE_MSFT / PRICE_AMZN - initial
///      oracle prices in USD * 1e8. Defaults are Yahoo Finance closes
///      recorded 2026-11-18; the agent overwrites them from live data on its
///      first cycle.
///      Writes deployments/<chainid>.json for the agent to consume.
contract Deploy is Script {
    function run() external {
        address operator = vm.envOr("OPERATOR", msg.sender);
        uint256 vaultUsdc = vm.envOr("VAULT_USDC", uint256(1_000 * 1e6));

        vm.startBroadcast();

        MockUSDC usdc = new MockUSDC();
        // Oracle updater starts as the deployer so this script can seed the
        // initial prices, then the role is handed to the agent operator.
        StockOracle oracle = new StockOracle(msg.sender);
        StockExchange exchange = new StockExchange(address(usdc), address(oracle), msg.sender);
        AgentVault vault = new AgentVault(address(usdc), address(exchange), operator);

        (bytes32[] memory symbols, int256[] memory prices, address[] memory tokens) = _deployStocks(exchange, vault);

        oracle.updatePrices(symbols, prices);
        usdc.mint(address(vault), vaultUsdc);
        // Sell-side liquidity reserve for the exchange. Buys leave USDC in
        // the exchange, but a sell pays USDC out of its balance — without a
        // reserve, back-to-back sells can revert (ERC20InsufficientBalance)
        // once fees + earlier sells drain the till. Mainnet path: real DEX
        // pools (Aerodrome/Uniswap) hold the liquidity instead.
        usdc.mint(address(exchange), 100_000 * 1e6);
        oracle.setUpdater(operator);

        vm.stopBroadcast();

        console.log("USDC", address(usdc));
        console.log("ORACLE", address(oracle));
        console.log("EXCHANGE", address(exchange));
        console.log("VAULT", address(vault));
        console.log("OPERATOR", operator);
        console.log("VAULT_USDC", vaultUsdc);
        _writeManifest(usdc, oracle, exchange, vault, operator, tokens);
    }

    function _deployStocks(StockExchange exchange, AgentVault vault)
        internal
        returns (bytes32[] memory symbols, int256[] memory prices, address[] memory tokens)
    {
        symbols = new bytes32[](5);
        prices = new int256[](5);
        tokens = new address[](5);

        (symbols[0], prices[0], tokens[0]) = _one(
            exchange, vault, "NVDA", "NVIDIA Tokenized Stock (testnet mirror)", "US67066G1040", vm.envOr("PRICE_NVDA", int256(15533_000000))
        );
        (symbols[1], prices[1], tokens[1]) = _one(
            exchange, vault, "AAPL", "Apple Tokenized Stock (testnet mirror)", "US0378331005", vm.envOr("PRICE_AAPL", int256(35418_000000))
        );
        (symbols[2], prices[2], tokens[2]) = _one(
            exchange, vault, "TSLA", "Tesla Tokenized Stock (testnet mirror)", "US88160R1014", vm.envOr("PRICE_TSLA", int256(38473_500000))
        );
        (symbols[3], prices[3], tokens[3]) = _one(
            exchange, vault, "MSFT", "Microsoft Tokenized Stock (testnet mirror)", "US5949181045", vm.envOr("PRICE_MSFT", int256(50692_500000))
        );
        (symbols[4], prices[4], tokens[4]) = _one(
            exchange, vault, "AMZN", "Amazon Tokenized Stock (testnet mirror)", "US0231351067", vm.envOr("PRICE_AMZN", int256(26416_500000))
        );
    }

    function _one(StockExchange exchange, AgentVault vault, string memory ticker, string memory name, string memory isin, int256 price)
        internal
        returns (bytes32 symbol, int256 p, address tokenAddr)
    {
        symbol = bytes32(bytes(ticker));
        p = price;
        TokenizedStock token = new TokenizedStock(name, string.concat(ticker, "c"), ticker, isin);
        token.setMinter(address(exchange));
        exchange.listStock(symbol, address(token));
        vault.setSymbolAllowed(symbol, true);
        tokenAddr = address(token);
        console.log("STOCK", ticker, tokenAddr);
    }

    function _writeManifest(MockUSDC usdc, StockOracle oracle, StockExchange exchange, AgentVault vault, address operator, address[] memory tokens)
        internal
    {
        string memory stocksJson = string.concat(
            '{"NVDA":"', vm.toString(tokens[0]), '","AAPL":"', vm.toString(tokens[1]), '","TSLA":"', vm.toString(tokens[2]),
            '","MSFT":"', vm.toString(tokens[3]), '","AMZN":"', vm.toString(tokens[4]), '"}'
        );
        string memory json = string.concat(
            '{"chainId":', vm.toString(block.chainid),
            ',"usdc":"', vm.toString(address(usdc)),
            '","oracle":"', vm.toString(address(oracle)),
            '","exchange":"', vm.toString(address(exchange)),
            '","vault":"', vm.toString(address(vault)),
            '","operator":"', vm.toString(operator),
            '","stocks":', stocksJson, '}'
        );
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeFile(path, json);
        console.log("MANIFEST", path);
    }
}
