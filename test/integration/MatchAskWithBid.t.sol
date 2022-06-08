// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/RentalExchange.sol";
import "../../src/ExecutionManager.sol";
import "../../src/TransferSelectorNFT.sol";
import "../../src/libraries/OrderTypes.sol";
import "../../src/strategies/StrategyStandardSaleForFixedPrice.sol";
import "../MockERC721.sol";
import "./interfaces/INFTNFTWalletProxyFactory.sol";
import "../../src/ReceiptToken.sol";

contract MatchAskWithBid is Test {
    address constant public EXCHANGE = 0x1302727142cEfebDf3d781646bd29EDb4401Af25;
    address constant public WALLET_FACTORY = 0xf3B203294eE4EeB6eea4059dE61E1c9206D4d3B9;
    address constant public FIXED_PRICE_STRATEGY = 0x21a215E51c496d63B0af33FE268fc1E909de4126;
    IWETH constant public WETH = IWETH(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7);

    uint constant LENDER_PK = 123;
    address constant public BORROWER = 0x34cF7A8Cbe01d440c957033891Bb705c966e56D5;

    RentalExchange exchange = RentalExchange(EXCHANGE);
    INFTNFTWalletProxyFactory proxyFactory = INFTNFTWalletProxyFactory(WALLET_FACTORY);
    MockERC721 collection = new MockERC721();
    IReceiptToken receiptToken;
    uint protocol_fee_rate;
    address public protocol_fee_recipient;
    address public lender;
    OrderTypes.Target public target;

    function setUp() public {
        receiptToken = exchange.receiptToken();
        protocol_fee_rate = IExecutionStrategy(FIXED_PRICE_STRATEGY).viewProtocolFee();
        protocol_fee_recipient = exchange.protocolFeeRecipient();
        lender = vm.addr(LENDER_PK);
        uint256 tokenId = collection.mintTo(lender);
        target = OrderTypes.Target(
            address(collection),
            tokenId,
            1
        );
        address transferManager = TransferSelectorNFT(address(exchange.transferSelectorNFT())).TRANSFER_MANAGER_ERC721();
        vm.prank(lender);
        collection.setApprovalForAll(transferManager, true);
    }

    function testMatchAskWithTakerBidUsingETHAndWETH() public {
        OrderTypes.MakerOrder memory ask = createMakerAskOrder(
            0.012 ether, 0, 4
        );

        INFTNFTWalletProxy appWallet = issueAppWallet();
        uint numHours = 3;
        OrderTypes.TakerOrder memory bid = OrderTypes.TakerOrder(
            false,
            address(appWallet),
            0.012 ether,
            numHours,
            target
        );
        assertEq(collection.ownerOf(target.tokenId), lender);
        uint256 priorProtocolBalance = WETH.balanceOf(protocol_fee_recipient);
        vm.prank(BORROWER);
        appWallet.execTransaction{ value: 0.012 ether * numHours }(
            EXCHANGE,
            0.012 ether * numHours,
            abi.encodeWithSelector(
                exchange.matchAskWithTakerBidUsingETHAndWETH.selector,
                bid,
                ask
            )
        );
        assertEq(collection.ownerOf(target.tokenId), address(appWallet));
        assertEq(
            WETH.balanceOf(protocol_fee_recipient) - priorProtocolBalance,
            0.012 ether * numHours * protocol_fee_rate / 10000
        );
        assertEq(
            WETH.balanceOf(lender),
            0.012 ether * numHours * (10000 - protocol_fee_rate) / 10000
        );
        assertEq(receiptToken.ownerOf(0), lender);

        IReceiptToken.ReceiptData memory receiptData = IReceiptToken.ReceiptData(
            address(collection),
            target.tokenId,
            address(appWallet),
            block.timestamp + numHours * 1 hours
        );
        assertEq(abi.encode(receiptToken.getReceiptData(0)), abi.encode(receiptData));

        vm.prank(lender);
        vm.expectRevert("Borrow period has not expired yet");
        receiptToken.redeem(0);

        vm.warp(block.timestamp + 1 days);
        vm.prank(BORROWER);
        vm.expectRevert("Not approved or the owner of the receipt");
        receiptToken.redeem(0);

        vm.prank(lender);
        receiptToken.redeem(0);

        assertEq(collection.ownerOf(target.tokenId), lender);
        vm.expectRevert("Receipt does not exist");
        receiptToken.getReceiptData(0);
    }

    function issueAppWallet() public returns (INFTNFTWalletProxy) {
        vm.prank(BORROWER);
        return proxyFactory.createProxyWithNonce(block.timestamp);
    }

    function createMakerAskOrder(
        uint pricePerHour,
        uint minHours,
        uint maxHours
    ) public returns (OrderTypes.MakerOrder memory) {
        OrderTypes.MakerRentConfig memory rentConfig = OrderTypes.MakerRentConfig(
            target,
            pricePerHour,
            minHours,
            maxHours,
            address(WETH)
        );
        OrderTypes.MakerOrder memory order = OrderTypes.MakerOrder(
            rentConfig,
            true,
            lender,
            FIXED_PRICE_STRATEGY,
            0,
            block.timestamp,
            block.timestamp + 3 days,
            "",
            ""
        );
        bytes32 digest = ECDSA.toTypedDataHash(exchange.DOMAIN_SEPARATOR(), OrderTypes.hash(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LENDER_PK, digest);
        bytes memory signature = bytes.concat(r,s,abi.encodePacked(v));
        order.signature = signature;
        return order;
    }
}
