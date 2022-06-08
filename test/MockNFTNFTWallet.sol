// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/interfaces/INFTNFTWallet.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockNFTNFTWallet is INFTNFTWallet, IERC721Receiver {
    function returnBorrowedNFT(address collection, uint256 tokenId, address to) external {
        IERC721(collection).safeTransferFrom(address(this), to, tokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}