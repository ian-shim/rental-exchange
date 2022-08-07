// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IReceiptToken is IERC721 {
    struct ReceiptData {
        address collection;
        uint256 borrowedTokenId;
        address borrower;
        uint256 expiration;
    }
    
    function mint(address owner, address borrower, address collection, uint256 tokenId, uint256 expiration) external returns (uint256);
    function redeem(uint256 receiptId) external;
    function getReceiptData(uint256 receiptId) external view returns (ReceiptData memory);
    function totalCount() external view returns (uint256);
}