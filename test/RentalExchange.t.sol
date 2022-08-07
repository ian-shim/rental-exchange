// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../src/RentalExchange.sol";
import "../src/ReceiptToken.sol";
import "../src/CurrencyManager.sol";
import "../src/ExecutionManager.sol";
import "../src/transferManagers/TransferManagerERC721.sol";
import "../src/transferManagers/TransferManagerERC1155.sol";
import "../src/TransferSelectorNFT.sol";
import "../src/strategies/StrategyStandardSaleForFixedPrice.sol";
import "./MockWalletValidator.sol";
import "./MockWETH.sol";
import "./MockERC721.sol";

contract RentalExchangeTest is Test {
    using OrderTypes for OrderTypes.MakerOrder;

    uint256 PROTOCOL_FEE_RATE = 400;
    RentalExchange public exchange;
    ITransferManagerNFT public transferManagerERC721;
    ITransferManagerNFT public transferManagerERC1155;
    ReceiptToken public receiptToken;
    CurrencyManager public currencyManager = new CurrencyManager();
    ExecutionManager public executionManager = new ExecutionManager();
    INFTNFTWalletValidator public walletValidator = new MockWalletValidator();
    MockWETH public WETH = new MockWETH();
    address public protocolFeeRecipient = 0x891e3465fCD6A67D13762487D2E326e0bF55De2F;
    StrategyStandardSaleForFixedPrice fixedPriceStrategy = new StrategyStandardSaleForFixedPrice(PROTOCOL_FEE_RATE);
    MockERC721 public mockERC721 = new MockERC721();
    
    event Deposit(address indexed dst, uint wad);
    event Transfer(address indexed from, address indexed to, uint256 value);

    event MakerAskMatched(
        bytes32 orderHash, // bid hash of the maker order
        address indexed maker, // maker address of the initial bid order
        uint256 orderNonce, // user order nonce
        address strategy,
        address currency,
        address collection, // collection address
        uint256 tokenId, // tokenId transferred
        uint256 amount // amount of tokens transferred
    );

    event MatchingTakerBid(
        bytes32 orderHash, // bid hash of the maker order
        address indexed taker, // sender address for the taker ask order
        uint256 pricePerHour,
        uint256 numHours
    );

    event MakerBidMatched(
        bytes32 orderHash, // bid hash of the maker order
        address indexed maker, // maker address of the initial bid order
        uint256 orderNonce, // user order nonce
        address strategy,
        address currency,
        address collection, // collection address
        uint256 tokenId, // tokenId transferred
        uint256 amount // amount of tokens transferred
    );

    event MatchingTakerAsk(
        bytes32 orderHash, // bid hash of the maker order
        address indexed taker, // sender address for the taker ask order
        uint256 pricePerHour,
        uint256 numHours
    );

    function setUp() public {
        receiptToken = new ReceiptToken();
        exchange = new RentalExchange(
            address(currencyManager),
            address(executionManager),
            address(walletValidator),
            address(receiptToken),
            address(WETH),
            protocolFeeRecipient
        );
        receiptToken.transferOwnership(address(exchange));
        currencyManager.addCurrency(address(WETH));
        executionManager.addStrategy(address(fixedPriceStrategy));
        transferManagerERC721 = new TransferManagerERC721(address(exchange));
        transferManagerERC1155 = new TransferManagerERC1155(address(exchange));
        ITransferSelectorNFT transferSelectorNFT = new TransferSelectorNFT(
            address(transferManagerERC721),
            address(transferManagerERC1155)
        );
        exchange.updateTransferSelectorNFT(address(transferSelectorNFT));
    }

    function testApprovedWalletOnly(
        address maker,
        address taker
    ) public {
        vm.assume(maker != address(0));
        vm.assume(taker != address(0));
        OrderTypes.Target memory target = OrderTypes.Target(
            address(mockERC721),
            0,
            1
        );
        uint pricePerHour = 0.01 ether;
        OrderTypes.MakerOrder memory makerAsk = getMakerOrder(true, maker, target, pricePerHour);
        OrderTypes.TakerOrder memory takerBid = OrderTypes.TakerOrder(
            false,
            taker,
            pricePerHour,
            3 hours,
            target
        );

        vm.expectRevert("Order: Wallet not approved");
        exchange.matchAskWithTakerBid(takerBid, makerAsk);

        vm.expectRevert("Order: Wallet not approved");
        exchange.matchAskWithTakerBidUsingETHAndWETH(takerBid, makerAsk);

        OrderTypes.MakerOrder memory makerBid = getMakerOrder(false, maker, target, pricePerHour);
        OrderTypes.TakerOrder memory takerAsk = OrderTypes.TakerOrder(
            true,
            taker,
            pricePerHour,
            3 hours,
            target
        );
        vm.expectRevert("Order: Wallet not approved");
        exchange.matchBidWithTakerAsk(takerAsk, makerBid);
    }

    function testMatchAskWithTakerBidUsingETHAndWETH() public {
        address borrower = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
        uint256 pricePerHour = 0.01 ether;
        // 0. set things up
        MockWalletValidator(address(walletValidator)).addWallet(borrower);
        uint lenderPK = 123;
        address lender = vm.addr(lenderPK);
        uint256 tokenId = mockERC721.mintTo(lender);
        uint256 numHours = 3;
        OrderTypes.Target memory target = OrderTypes.Target(
            address(mockERC721),
            tokenId,
            1
        );

        // 1. give exchange the approval & create a maker order
        vm.prank(lender);
        mockERC721.setApprovalForAll(address(transferManagerERC721), true);
        OrderTypes.MakerOrder memory makerAsk = getMakerOrder(true, lender, target, pricePerHour);

        bytes32 digest = ECDSA.toTypedDataHash(exchange.DOMAIN_SEPARATOR(), OrderTypes.hash(makerAsk));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(lenderPK, digest);
        bytes memory signature = bytes.concat(r,s,abi.encodePacked(v));
        makerAsk.signature = signature;
        assertTrue(SignatureChecker.isValidSignatureNow(lender, digest, signature));

        // 2. give exchange the approval & create a taker order
        vm.deal(borrower, pricePerHour * numHours);

        OrderTypes.TakerOrder memory takerBid = OrderTypes.TakerOrder(
            false,
            borrower,
            pricePerHour,
            numHours,
            target
        );
        vm.prank(borrower);
        exchange.matchAskWithTakerBidUsingETHAndWETH{value: 0.03 ether}(takerBid, makerAsk);
        assertEq(mockERC721.ownerOf(tokenId), borrower);
        assertEq(WETH.balanceOf(protocolFeeRecipient), 0.03 ether * PROTOCOL_FEE_RATE / 10000);
        assertEq(WETH.balanceOf(lender), 0.03 ether * ( 10000 - PROTOCOL_FEE_RATE ) / 10000);
        assertEq(receiptToken.ownerOf(0), lender);
    }

    function testSignature() public {
        bytes memory signature = hex"69513a2a19b271e5f91c55c6f7b0fbfb724b24ee44d9d58e40825ed4aabfd33c0a2346427e26fcea5ae48a29a21022978e9a7bf8b7e0b8a08ed04cb65fe82f611c";
        OrderTypes.Target memory target = OrderTypes.Target(
            0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b,
            839705,
            1
        );

        OrderTypes.MakerRentConfig memory config = OrderTypes.MakerRentConfig(
            target,
            0.012 ether,
            0,
            12,
            0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7
        );
        
        OrderTypes.MakerOrder memory makerAsk = OrderTypes.MakerOrder(
            config,
            true,
            0x891e3465fCD6A67D13762487D2E326e0bF55De2F,
            0x1564F4667D64C8a02A6D65a22e24189bc5eB02AB,
            0,
            1654243036750,
            1657398710350,
            "",
            ""
        );
        bytes32 orderHash = makerAsk.hash();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x626af73bd36f97b6b0f094db8772850c4a6e2eaec1b1dc866a93994f3d5fc53a, // keccak256("RentalExchange")
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes("1")) for versionId = 1
                5,
                0xaF66072E7167014B72c2072A03d42387a4089EE4
            )
        );

        assertTrue(SignatureChecker.isValidSignatureNow(
            0x891e3465fCD6A67D13762487D2E326e0bF55De2F,
            ECDSA.toTypedDataHash(domainSeparator, orderHash),
            signature
        ));
    }

    function testSignature2() public {
        bytes memory signature = hex"c2e35e778f866a1c2d64cbd5dab61f359a17c9c991bec7b0b1a188585b7e73672452ee50002cab87b62007af7d91190862fd215689e5a0b2b3589b99cdbf02381b";
        OrderTypes.Target memory target = OrderTypes.Target(
            0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b,
            765318,
            1
        );

        OrderTypes.MakerRentConfig memory config = OrderTypes.MakerRentConfig(
            target,
            0.002 ether,
            1,
            4,
            0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7
        );
        emit log_uint(block.timestamp);
        OrderTypes.MakerOrder memory makerAsk = OrderTypes.MakerOrder(
            config,
            true,
            0x891e3465fCD6A67D13762487D2E326e0bF55De2F,
            0x21a215E51c496d63B0af33FE268fc1E909de4126,
            1657822389,
            1657822389,
            1687822389,
            "",
            ""
        );
        bytes32 orderHash = makerAsk.hash();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x626af73bd36f97b6b0f094db8772850c4a6e2eaec1b1dc866a93994f3d5fc53a, // keccak256("RentalExchange")
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes("1")) for versionId = 1
                5,
                0x1302727142cEfebDf3d781646bd29EDb4401Af25
            )
        );

        assertTrue(SignatureChecker.isValidSignatureNow(
            0x891e3465fCD6A67D13762487D2E326e0bF55De2F,
            ECDSA.toTypedDataHash(domainSeparator, orderHash),
            signature
        ));
    }

    function getMakerOrder(
        bool isAsk,
        address lender,
        OrderTypes.Target memory target,
        uint256 pricePerHour
    ) internal view returns (OrderTypes.MakerOrder memory) {
        return OrderTypes.MakerOrder(
            OrderTypes.MakerRentConfig(
                target,
                pricePerHour,
                1,
                4,
                address(WETH)
            ),
            isAsk,
            lender,
            address(fixedPriceStrategy),
            0,
            block.timestamp,
            block.timestamp + 1 hours,
            "",
            ""
        );
    }
}
