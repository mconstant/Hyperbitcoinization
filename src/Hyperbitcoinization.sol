// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

/// ============ Imports ============

import { IERC20 } from "./interfaces/IERC20.sol"; // ERC20 minified interface
import { AggregatorV3Interface } from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol"; // Chainlink pricefeed

/// @title Hyperbitcoinization
/// @author Anish Agnihotri
/// @notice Simple 1M USDC vs 1 wBTC 90-day bet cleared by Chainlink
contract Hyperbitcoinization {

    /// ============ Structs ============

    /// @notice Bet terms
    struct Bet {
        /// @notice Settled bet?
        bool settled;
        /// @notice USDC-providing party sent funds
        bool USDCSent;
        /// @notice wBTC-providing party sent funds
        bool WBTCSent;
        /// @notice USDC-providing party
        address partyUSDC;
        /// @notice wBTC-providing party
        address partyWBTC;
        /// @notice Bet starting timestamp
        uint256 startTimestamp;
    }

    /// ============ Constants ============

    /// @notice 90 days
    uint256 constant BET_DURATION = 7776000; // 60 * 60 * 24 * 90
    /// @notice USDC amount
    uint256 constant USDC_AMOUNT = 1_000_000e6;
    /// @notice wBTC amount
    uint256 constant WBTC_AMOUNT = 1e8;
    /// @notice winning BTC/USD price
    uint256 constant WINNING_BTC_PRICE = 1_000_000;

    /// ============ Immutable storage ============

    /// @notice USDC token
    IERC20 public immutable USDC_TOKEN;
    /// @notice WBTC token
    IERC20 public immutable WBTC_TOKEN;
    /// @notice BTC/USD price feed (Chainlink)
    AggregatorV3Interface public immutable BTCUSD_PRICEFEED;

    /// ============ Mutable storage ============

    /// @notice ID of current bet (next = curr + 1)
    uint256 public currentBetId = 0;
    /// @notice Mapping of bet id => bet
    mapping(uint256 => Bet) public bets;

    /// ============ Constructor ============

    /// @notice Creates a new Hyperbitcoinization contract
    /// @param _USDC_TOKEN address of USDC token
    /// @param _WBTC_TOKEN address of WBTC token
    /// @param _WBTC_PRICEFEED address of pricefeed for BTC/USD
    constructor(address _USDC_TOKEN, address _WBTC_TOKEN, address _BTCUSD_PRICEFEED) {
        USDC_TOKEN = IERC20(_USDC_TOKEN);
        WBTC_TOKEN = IERC20(_WBTC_TOKEN);
        BTCUSD_PRICEFEED = AggregatorV3Interface(_BTCUSD_PRICEFEED);
    }

    /// ============ Functions ============

    /// @notice Creates a new bet between two parties
    /// @param partyUSDC providing USDC
    /// @param partyWBTC providing wBTC
    function createBet(address partyUSDC, address partyWBTC) external returns (uint256) {
        currentBetId++;
        bets[currentBetId] = Bet({
            settled: false,
            USDCSent: false,
            WBTCSent: false,
            partyUSDC: partyUSDC,
            partyWBTC: partyWBTC,
            startTimestamp: 0
        });
        return currentBetId;
    }

    /// @notice Allows partyUSDC to add USDC to a bet.
    /// @dev Requires user to approve contract.
    /// @param betId to add funds to
    function addUSDC(uint256 betId) external {
        Bet memory bet = bets[betId];
        require(!bet.USDCSent, "USDC already added");
        require(msg.sender == bet.partyUSDC, "User not part of bet");

        // Transfer USDC
        USDC_TOKEN.transferFrom(
            msg.sender,
            address(this),
            USDC_AMOUNT
        );

        // Toggle USDC sent
        bet.USDCSent = true;

        // Start bet if both parties sent
        if (bet.WBTCSent) bet.startTimestamp = block.timestamp;
    }

    /// @notice Allows partyWBTC to add wBTC to a bet.
    /// @dev Requires user to approve contract.
    /// @param betId to add funds to
    function addWBTC(uint256 betId) external {
        Bet memory bet = bets[betId];
        require(!bet.WBTCSent, "wBTC already added");
        require(msg.sender == bet.partyWBTC, "User not part of bet");

        // Transfer WBTC
        WBTC_TOKEN.transferFrom(
            msg.sender,
            address(this),
            WBTC_AMOUNT
        );

        // Toggle wBTC sent
        bet.WBTCSent = true;

        // Start bet if both parties sent
        if (bet.USDCSent) bet.startTimestamp = block.timestamp;
    }

    /// @notice Collect BTC/USD price from Chainlink
    function getBTCPrice() public view returns (uint256) {
        // Collect BTC price
        (,int price,,) = BTCUSD_PRICEFEED.latestRoundData();
        return uint256(price) / 10 ** BTCUSD_PRICEFEED.decimals();
    }

    /// @notice Allows anyone to settle an existing bet
    /// @param betId to settle
    function settleBet(uint256 betId) external {
        Bet memory bet = bets[betId];
        require(!bet.settled, "Bet already settled");
        require(bet.startTimestamp + BET_DURATION >= block.timestamp, "Bet still pending");

        // Mark bet settled
        bet.settled = true;

        // Collect BTC price
        uint256 btcPrice = getBTCPrice();

        // Check for winner
        address winner = btcPrice > WINNING_BTC_PRICE ? bet.partyWBTC : bet.partyUSDC;

        // Send funds to winner
        USDC.transferFrom(address(this), winner, 1_000_000e6);
        WBTC.transferFrom(address(this), winner, 1e8);
    }

    /// @notice Allows any bet party to withdraw funds while bet is pending
    /// @param betId to withdraw
    function withdrawStale(uint256 betId) external {
        Bet memory bet = bets[betId];
        require(bet.startTimestamp == 0, "Bet already started");
        require(msg.sender == bet.partyUSDC || msg.sender == bet.partyWBTC, "Not bet participant");

        // If USDC received, return
        if (bet.USDCSent) {
            bet.USDCSent = false;
            USDC_TOKEN.transferFrom(address(this), bet.partyUSDC, USDC_AMOUNT);
        }
        // Else, return wBTC
        if (bet.WBTCSent) {
            bet.WBTCSent = false;
            WBTC_TOKEN.transferFrom(address(this), bet.partyWBTC, WBTC_AMOUNT);
        }
    }
}