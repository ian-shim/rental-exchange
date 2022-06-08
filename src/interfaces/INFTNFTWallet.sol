// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface INFTNFTWallet {
    function returnBorrowedNFT(address collection, uint256 tokenId, address to) external;
}