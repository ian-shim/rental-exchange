// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/IReceiptToken.sol";
import "./interfaces/INFTNFTWallet.sol";

contract ReceiptToken is ERC721, IReceiptToken, Ownable {
    using Counters for Counters.Counter;

    // mapping from receiptId to ReceiptData
    mapping(uint256 => ReceiptData) private _receiptData;

    Counters.Counter private _receiptId;
    address public exchange;

    event ReceiptMinted(
        address indexed owner,
        address indexed collection,
        uint256 receiptId,
        address borrower,
        uint256 borrowedTokenId,
        uint256 expiration
    );
    event ReceiptBurned(uint256 indexed receiptId);

    constructor() ERC721("NFTRentReceipt", "RCPT") {
    }

    /**
        Throughout this contract, `onlyOwner` modifier restricts the methods to
        be called from the exchange, *not* the owner of the receipt NFT.
     */

    function mint(
        address lender,
        address borrower,
        address collection,
        uint256 borrowedTokenId,
        uint256 expiration
    ) external onlyOwner returns (uint256) {
        uint256 currentReceiptId = _receiptId.current();
        _safeMint(lender, currentReceiptId);
        _setReceiptData(currentReceiptId, collection, borrowedTokenId, borrower, expiration);
        emit ReceiptMinted(lender, collection, currentReceiptId, borrower, borrowedTokenId, expiration);
        _receiptId.increment();
        
        return currentReceiptId;
    }

    function _burn(uint256 receiptId) internal override {
        super._burn(receiptId);
        
        if (_receiptData[receiptId].collection != address(0)) {
            delete _receiptData[receiptId];
        }
        emit ReceiptBurned(receiptId);
    }

    function redeem(uint256 receiptId) external {
        require(_isApprovedOrOwner(msg.sender, receiptId), "Not approved or the owner of the receipt");
        ReceiptData memory receiptData = _receiptData[receiptId];
        require(receiptData.expiration < block.timestamp, "Borrow period has not expired yet");
        INFTNFTWallet(receiptData.borrower).returnBorrowedNFT(receiptData.collection, receiptData.borrowedTokenId, ownerOf(receiptId));
        _burn(receiptId);
    }

    function totalCount() external view returns (uint256) {
        return _receiptId.current();
    }

    function tokenURI(uint256 receiptId) public view override(ERC721) returns (string memory) {
        ReceiptData memory receiptData = _receiptData[receiptId];
        return formatTokenURI(receiptData.collection, receiptData.borrowedTokenId, receiptData.borrower, receiptData.expiration);
    }

    function getReceiptData(uint256 receiptId) public view returns (ReceiptData memory) {
        require(_exists(receiptId), "Receipt does not exist");
        return _receiptData[receiptId];
    }

    function formatTokenURI(address collection, uint256 tokenId, address borrower, uint256 expiration) internal pure returns (string memory) {
        return string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            string.concat(
                                '{"name":"NFT Rent Receipt",',
                                 '"description":"Receipt for an NFT rental",',
                                 '"attributes": [',
                                    '{"trait_type":"collection","value":"', Strings.toHexString(collection),'"},',
                                    '{"trait_type":"tokenId","value":"', Strings.toString(tokenId),'"},',
                                    '{"trait_type":"borrower","value":"', Strings.toHexString(borrower),'"},',
                                    '{"trait_type":"expiration","value":"', Strings.toString(expiration),'"}',
                                 ']}'
                            )
                        )
                    )
                )
            );
    }

    function _setReceiptData(
        uint256 receiptId,
        address collection,
        uint256 borrowedTokenId,
        address borrower,
        uint256 expiration
    ) private {
        require(_exists(receiptId), "Cannot set data of nonexistent receipt");
        ReceiptData memory receiptData = ReceiptData(
            collection, borrowedTokenId, borrower, expiration
        );
        _receiptData[receiptId] = receiptData;
    }
}