// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {TokenizedStock} from "../src/TokenizedStock.sol";
import {StockOracle} from "../src/StockOracle.sol";
import {StockExchange} from "../src/StockExchange.sol";
import {AgentVault} from "../src/AgentVault.sol";

contract StockMaxxTest is Test {
    MockUSDC usdc;
    TokenizedStock nvda;
    TokenizedStock aapl;
    StockOracle oracle;
    StockExchange exchange;
    AgentVault vault;

    address owner = address(this);
    address operator = address(0xA6E77);
    address stranger = address(0xBEEF);

    bytes32 constant NVDA = bytes32("NVDA");
    bytes32 constant AAPL = bytes32("AAPL");

    // NVDA $185.42, AAPL $273.10 (8 decimals)
    int256 constant NVDA_PRICE = 18542_000000;
    int256 constant AAPL_PRICE = 27310_000000;

    function setUp() public {
        usdc = new MockUSDC();
        nvda = new TokenizedStock("NVIDIA Tokenized Stock (testnet mirror)", "NVDAc", "NVDA", "US67066G1040");
        aapl = new TokenizedStock("Apple Tokenized Stock (testnet mirror)", "AAPLc", "AAPL", "US0378331005");
        oracle = new StockOracle(owner);
        exchange = new StockExchange(address(usdc), address(oracle), owner);
        vault = new AgentVault(address(usdc), address(exchange), operator);

        exchange.listStock(NVDA, address(nvda));
        exchange.listStock(AAPL, address(aapl));
        nvda.setMinter(address(exchange));
        aapl.setMinter(address(exchange));

        vault.setSymbolAllowed(NVDA, true);
        vault.setSymbolAllowed(AAPL, true);

        oracle.updatePrice(NVDA, NVDA_PRICE);
        oracle.updatePrice(AAPL, AAPL_PRICE);

        // Fund the vault with 1,000 test USDC.
        usdc.mint(address(vault), 1_000 * 1e6);
    }

    // ---- oracle ----

    function test_OraclePriceAndStaleness() public {
        assertEq(oracle.getPrice(NVDA), NVDA_PRICE);
        // Fresh price is fine; warp past maxAge and it must revert.
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(StockOracle.StalePrice.selector);
        oracle.getPrice(NVDA);
    }

    function test_OracleOnlyUpdater() public {
        vm.prank(stranger);
        vm.expectRevert(StockOracle.OnlyUpdater.selector);
        oracle.updatePrice(NVDA, 100_000000);
    }

    function test_OracleRejectsBadPrice() public {
        vm.expectRevert(StockOracle.InvalidPrice.selector);
        oracle.updatePrice(NVDA, 0);
    }

    // ---- tokenized stock ----

    function test_StockDecimalsAndMultiplier() public {
        assertEq(nvda.decimals(), 8);
        assertEq(nvda.multiplier(), 1e18);
        assertEq(nvda.ticker(), "NVDA");
        assertEq(nvda.isin(), "US67066G1040");
    }

    function test_BalanceOfUIAfterSplit() public {
        // Simulate a 2:1 split: 1 token unit becomes 2 shares.
        usdc.mint(address(this), 100 * 1e6);
        usdc.approve(address(exchange), 100 * 1e6);
        exchange.buy(NVDA, 100 * 1e6);
        uint256 bal = nvda.balanceOf(address(this));
        assertEq(nvda.balanceOfUI(address(this)), bal); // multiplier 1.0
        nvda.setMultiplier(2e18, "2:1 split");
        assertEq(nvda.balanceOfUI(address(this)), bal * 2);
    }

    // ---- exchange quotes & trades ----

    function test_QuoteBuyMath() public {
        // $100 USDC at $185.42, fee 0.10% -> net $99.90 -> 99.90/185.42 tokens
        (uint256 stockOut, uint256 fee) = exchange.quoteBuy(NVDA, 100 * 1e6);
        assertEq(fee, 100_000); // 0.10 USDC
        uint256 expected = (99_900_000 * 1e2 * 1e8) / uint256(NVDA_PRICE);
        assertEq(stockOut, expected);
        assertGt(stockOut, 0);
    }

    function test_BuyMintsStockAndTakesFee() public {
        usdc.mint(address(this), 100 * 1e6);
        usdc.approve(address(exchange), 100 * 1e6);
        uint256 stockOut = exchange.buy(NVDA, 100 * 1e6);
        assertEq(nvda.balanceOf(address(this)), stockOut);
        assertEq(usdc.balanceOf(owner), 100_000); // fee to feeRecipient (owner)
    }

    function test_SellRoundTrip() public {
        usdc.mint(address(this), 100 * 1e6);
        usdc.approve(address(exchange), 100 * 1e6);
        uint256 stockOut = exchange.buy(NVDA, 100 * 1e6);
        uint256 usdcBefore = usdc.balanceOf(address(this));
        (uint256 expectedOut, uint256 expectedFee) = exchange.quoteSell(NVDA, stockOut);
        uint256 got = exchange.sell(NVDA, stockOut);
        // Round trip loses ~2x fee (0.10% each way): got is in (99.7, 100) USDC.
        assertEq(got, expectedOut);
        assertGt(got, 99_700_000);
        assertLt(got, 100 * 1e6);
        // This test contract is also the fee recipient, so it receives got + fee.
        assertEq(usdc.balanceOf(address(this)) - usdcBefore, got + expectedFee);
        assertEq(nvda.balanceOf(address(this)), 0);
    }

    function test_BuyRevertsOnStalePrice() public {
        vm.warp(block.timestamp + 2 days);
        usdc.mint(address(this), 10 * 1e6);
        usdc.approve(address(exchange), 10 * 1e6);
        vm.expectRevert(StockOracle.StalePrice.selector);
        exchange.buy(NVDA, 10 * 1e6);
    }

    function test_BuyRevertsAboveMaxTrade() public {
        usdc.mint(address(this), 20_000 * 1e6);
        usdc.approve(address(exchange), 20_000 * 1e6);
        vm.expectRevert(StockExchange.TradeTooLarge.selector);
        exchange.buy(NVDA, 20_000 * 1e6);
    }

    function test_ExchangePauseBlocksTrades() public {
        exchange.pause();
        usdc.mint(address(this), 10 * 1e6);
        usdc.approve(address(exchange), 10 * 1e6);
        vm.expectRevert();
        exchange.buy(NVDA, 10 * 1e6);
        exchange.unpause();
        exchange.buy(NVDA, 10 * 1e6); // works again
    }

    // ---- vault guardrails ----

    function test_VaultBuyWithinGuardrails() public {
        vm.prank(operator);
        vault.executeBuy(NVDA, 50 * 1e6);
        assertGt(nvda.balanceOf(address(vault)), 0);
        assertEq(vault.positionUsd(NVDA), 50 * 1e6);
        assertEq(vault.tradesToday(), 1);
    }

    function test_VaultBuyThenSell() public {
        vm.prank(operator);
        vault.executeBuy(NVDA, 50 * 1e6);
        uint256 stockBal = nvda.balanceOf(address(vault));
        uint256 usdcBefore = usdc.balanceOf(address(vault));
        vm.prank(operator);
        vault.executeSell(NVDA, stockBal);
        assertEq(nvda.balanceOf(address(vault)), 0);
        assertGt(usdc.balanceOf(address(vault)), usdcBefore);
        assertEq(vault.tradesToday(), 2);
    }

    function test_VaultRejectsNonOperatorTrade() public {
        vm.prank(stranger);
        vm.expectRevert(AgentVault.OnlyOperator.selector);
        vault.executeBuy(NVDA, 10 * 1e6);
    }

    function test_VaultRejectsOversizedTrade() public {
        vm.prank(operator);
        vm.expectRevert(AgentVault.TradeTooLarge.selector);
        vault.executeBuy(NVDA, 101 * 1e6); // maxTradeUsd = 100 USDC
    }

    function test_VaultRejectsUnlistedSymbol() public {
        bytes32 TSLA = bytes32("TSLA");
        vm.prank(operator);
        vm.expectRevert(AgentVault.SymbolNotAllowed.selector);
        vault.executeBuy(TSLA, 10 * 1e6);
    }

    function test_VaultRejectsPositionCap() public {
        // maxPositionUsd = 400: four 100-USDC buys OK, fifth must revert.
        vm.startPrank(operator);
        for (uint256 i = 0; i < 4; i++) {
            vault.executeBuy(NVDA, 100 * 1e6);
        }
        vm.expectRevert(AgentVault.PositionTooLarge.selector);
        vault.executeBuy(NVDA, 1 * 1e6);
        vm.stopPrank();
    }

    function test_VaultDailyCap() public {
        vault.setLimits(100 * 1e6, 2, 400 * 1e6);
        vm.startPrank(operator);
        vault.executeBuy(NVDA, 10 * 1e6);
        vault.executeBuy(AAPL, 10 * 1e6);
        vm.expectRevert(AgentVault.DailyTradeCapReached.selector);
        vault.executeBuy(NVDA, 10 * 1e6);
        vm.stopPrank();
        // Next day the cap resets.
        vm.warp(block.timestamp + 1 days);
        vm.prank(operator);
        vault.executeBuy(NVDA, 10 * 1e6);
    }

    function test_VaultPauseBlocksOperator() public {
        vault.pause();
        vm.prank(operator);
        vm.expectRevert();
        vault.executeBuy(NVDA, 10 * 1e6);
        vault.unpause();
        vm.prank(operator);
        vault.executeBuy(NVDA, 10 * 1e6);
    }

    function test_OwnerCanWithdrawButOperatorCannot() public {
        vm.prank(operator);
        vm.expectRevert();
        vault.withdraw(address(usdc), operator, 1 * 1e6);
        // Owner withdraws 10 USDC back.
        vault.withdraw(address(usdc), owner, 10 * 1e6);
        assertEq(usdc.balanceOf(owner), 10 * 1e6);
    }

    function test_DecisionLoggingEmitsEvent() public {
        vm.prank(operator);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.DecisionLogged(
            operator, NVDA, AgentVault.Action.BUY, NVDA_PRICE, 7_500, keccak256("test"), block.timestamp
        );
        vault.logDecision(NVDA, AgentVault.Action.BUY, NVDA_PRICE, 7_500, keccak256("test"));
    }

    function test_BatchDecisionLogging() public {
        bytes32[] memory symbols = new bytes32[](2);
        symbols[0] = NVDA;
        symbols[1] = AAPL;
        AgentVault.Action[] memory actions = new AgentVault.Action[](2);
        actions[0] = AgentVault.Action.BUY;
        actions[1] = AgentVault.Action.HOLD;
        int256[] memory prices = new int256[](2);
        prices[0] = NVDA_PRICE;
        prices[1] = AAPL_PRICE;
        uint256[] memory confs = new uint256[](2);
        confs[0] = 7_500;
        confs[1] = 5_000;
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = keccak256("buy nvda");
        hashes[1] = keccak256("hold aapl");
        vm.recordLogs();
        vm.prank(operator);
        vault.logDecisions(symbols, actions, prices, confs, hashes);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Exactly 2 DecisionLogged events.
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DecisionLogged(address,bytes32,uint8,int256,uint256,bytes32,uint256)")) count++;
        }
        assertEq(count, 2);
    }

    function test_MultiTradeSellLiquidity() public {
        // Regression: back-to-back sells reverted with ERC20InsufficientBalance
        // when the exchange held only buy proceeds minus fees. The deploy
        // script now funds the exchange with a sell-side reserve.
        usdc.mint(address(exchange), 100_000 * 1e6);
        vm.startPrank(operator);
        vault.executeBuy(NVDA, 50 * 1e6);
        vault.executeBuy(AAPL, 50 * 1e6);
        vault.executeSell(NVDA, nvda.balanceOf(address(vault)));
        vault.executeSell(AAPL, aapl.balanceOf(address(vault)));
        vm.stopPrank();
        assertEq(nvda.balanceOf(address(vault)), 0);
        assertEq(aapl.balanceOf(address(vault)), 0);
        assertGt(usdc.balanceOf(address(vault)), 990 * 1e6);
    }

    function test_OperatorRotation() public {
        address newOp = address(0xCAFE);
        vault.setOperator(newOp);
        assertEq(vault.operator(), newOp);
        vm.prank(operator);
        vm.expectRevert(AgentVault.OnlyOperator.selector);
        vault.executeBuy(NVDA, 10 * 1e6);
        vm.prank(newOp);
        vault.executeBuy(NVDA, 10 * 1e6);
    }
}
