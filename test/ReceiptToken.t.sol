// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ReceiptToken.sol";
import "../src/RentalExchange.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./MockERC721.sol";
import "./MockNFTNFTWallet.sol";

contract ReceiptReceiver is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ReceiptTokenTest is Test {
    ReceiptToken public receiptToken;
    ReceiptReceiver public contractLender = new ReceiptReceiver();
    address public eoaLender = 0x34cF7A8Cbe01d440c957033891Bb705c966e56D5;
    MockERC721 public mockERC721 = new MockERC721();

    event ReceiptMinted(
        address indexed owner,
        address indexed collection,
        uint256 receiptId,
        address borrower,
        uint256 tokenId,
        uint256 expiration
    );
    event ReceiptBurned(uint256 indexed receiptId);
    address public contractOwner;
    
    function setUp() public {
        receiptToken = new ReceiptToken();
        contractOwner = receiptToken.owner();
    }

    function testNameAndSymbol() public {
        assertEq(receiptToken.name(), "NFTRentReceipt");
        assertEq(receiptToken.symbol(), "RCPT");
    }

    function testMint(
        address notOwner, 
        address borrower, 
        address collection, 
        uint256 tokenId, 
        uint256 expiration
    ) public {
        vm.assume(notOwner != address(contractOwner));
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        receiptToken.mint(address(contractLender), borrower, collection, tokenId, expiration);

        vm.prank(contractOwner);
        vm.expectEmit(true, true, false, true);
        emit ReceiptMinted(address(contractLender), collection, 0, borrower, tokenId, expiration);
        uint256 receiptId = receiptToken.mint(address(contractLender), borrower, collection, tokenId, expiration);
        assertEq(receiptToken.ownerOf(receiptId), address(contractLender));
        assertEq(receiptToken.getReceiptData(receiptId).collection, collection);
        assertEq(receiptToken.getReceiptData(receiptId).borrowedTokenId, tokenId);
        assertEq(receiptToken.getReceiptData(receiptId).borrower, borrower);
        assertEq(receiptToken.getReceiptData(receiptId).expiration, expiration);
        assertEq(receiptToken.totalCount(), 1);

        vm.prank(contractOwner);
        vm.expectEmit(true, true, false, true);
        emit ReceiptMinted(eoaLender, collection, 1, borrower, tokenId, expiration);
        uint256 nextReceiptId = receiptToken.mint(eoaLender, borrower, collection, tokenId, expiration);
        assertEq(nextReceiptId, receiptId + 1);
        assertEq(receiptToken.ownerOf(nextReceiptId), eoaLender);
        assertEq(receiptToken.getReceiptData(nextReceiptId).collection, collection);
        assertEq(receiptToken.getReceiptData(nextReceiptId).borrowedTokenId, tokenId);
        assertEq(receiptToken.getReceiptData(nextReceiptId).borrower, borrower);
        assertEq(receiptToken.getReceiptData(nextReceiptId).expiration, expiration);
        assertEq(receiptToken.totalCount(), 2);
    }

    function testTokenURI() public {
        address collection = 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;
        uint256 tokenId = 1234;
        address borrower = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
        uint256 expiration = 1657398710350;
        vm.prank(contractOwner);
        uint256 receiptId = receiptToken.mint(eoaLender, borrower, collection, tokenId, expiration);
        assertEq(
            receiptToken.tokenURI(receiptId),
            "data:application/json;base64,eyJuYW1lIjoiTkZUIFJlbnQgUmVjZWlwdCIsImRlc2NyaXB0aW9uIjoiUmVjZWlwdCBmb3IgYW4gTkZUIHJlbnRhbCIsImF0dHJpYnV0ZXMiOiJbeyJ0cmFpdF90eXBlIjoiY29sbGVjdGlvbiIsInZhbHVlIjoiMHhjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIn17InRyYWl0X3R5cGUiOiJ0b2tlbklkIiwidmFsdWUiOiIxMjM0In17InRyYWl0X3R5cGUiOiJib3Jyb3dlciIsInZhbHVlIjoiMHhkZWFkYmVlZmRlYWRiZWVmZGVhZGJlZWZkZWFkYmVlZmRlYWRiZWVmIn17InRyYWl0X3R5cGUiOiJleHBpcmF0aW9uIiwidmFsdWUiOiIxNjU3Mzk4NzEwMzUwIn1dIn0="
        );
    }

    function testRedeem() public {
        MockNFTNFTWallet borrower = new MockNFTNFTWallet();
        uint256 tokenId = mockERC721.mintTo(address(borrower));
        uint256 expiration = block.timestamp + 12 days;

        vm.prank(contractOwner);
        uint256 receiptId = receiptToken.mint(
            eoaLender,
            address(borrower),
            address(mockERC721),
            tokenId,
            expiration
        );

        vm.prank(address(borrower));
        vm.expectRevert("Not approved or the owner of the receipt");
        receiptToken.redeem(receiptId);

        vm.prank(eoaLender);
        vm.expectRevert("Borrow period has not expired yet");
        receiptToken.redeem(receiptId);

        vm.warp(block.timestamp + 13 days);
        vm.prank(eoaLender);
        vm.expectEmit(true, false, false, true);
        emit ReceiptBurned(receiptId);
        receiptToken.redeem(receiptId);

        assertEq(mockERC721.ownerOf(tokenId), eoaLender);
        vm.expectRevert("ERC721: owner query for nonexistent token");
        receiptToken.ownerOf(receiptId);

        vm.expectRevert("Receipt does not exist");
        receiptToken.getReceiptData(receiptId);
    }
}
