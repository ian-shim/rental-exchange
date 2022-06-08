// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import {OrderTypes} from "../libraries/OrderTypes.sol";
import {IExecutionStrategy} from "../interfaces/IExecutionStrategy.sol";

/**
 * @title StrategyStandardSaleForFixedPrice
 * @notice Strategy that executes an order at a fixed price that
 * can be taken either by a bid or an ask.
 */
contract StrategyStandardSaleForFixedPrice is IExecutionStrategy {
    uint256 public immutable PROTOCOL_FEE;

    /**
     * @notice Constructor
     * @param _protocolFee protocol fee (200 --> 2%, 400 --> 4%)
     */
    constructor(uint256 _protocolFee) {
        PROTOCOL_FEE = _protocolFee;
    }

    /**
     * @notice Check whether a taker ask order can be executed against a maker bid
     * @param takerAsk taker ask order
     * @param makerBid maker bid order
     * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
     */
    function canExecuteTakerAsk(OrderTypes.TakerOrder calldata takerAsk, OrderTypes.MakerOrder calldata makerBid)
        external
        view
        override
        returns (
            bool,
            uint256,
            uint256
        )
    {
        OrderTypes.MakerRentConfig calldata rentConfig = makerBid.rentConfig;
        return (
            ((rentConfig.pricePerHour == takerAsk.pricePerHour) &&
                (rentConfig.target.tokenId == takerAsk.target.tokenId) &&
                (rentConfig.minHours <= takerAsk.numHours) &&
                (takerAsk.numHours <= rentConfig.maxHours) &&
                (makerBid.startTime <= block.timestamp) &&
                (makerBid.endTime >= block.timestamp)),
            rentConfig.target.tokenId,
            rentConfig.target.amount
        );
    }

    /**
     * @notice Check whether a taker bid order can be executed against a maker ask
     * @param takerBid taker bid order
     * @param makerAsk maker ask order
     * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
     */
    function canExecuteTakerBid(OrderTypes.TakerOrder calldata takerBid, OrderTypes.MakerOrder calldata makerAsk)
        external
        view
        override
        returns (
            bool,
            uint256,
            uint256
        )
    {
        OrderTypes.MakerRentConfig calldata rentConfig = makerAsk.rentConfig;
        return (
            ((rentConfig.pricePerHour == takerBid.pricePerHour) &&
                (rentConfig.target.tokenId == takerBid.target.tokenId) &&
                (rentConfig.minHours <= takerBid.numHours) &&
                (takerBid.numHours <= rentConfig.maxHours) &&
                (makerAsk.startTime <= block.timestamp) &&
                (makerAsk.endTime >= block.timestamp)),
            rentConfig.target.tokenId,
            rentConfig.target.amount
        );
    }

    /**
     * @notice Return protocol fee for this strategy
     * @return protocol fee
     */
    function viewProtocolFee() external view override returns (uint256) {
        return PROTOCOL_FEE;
    }
}
