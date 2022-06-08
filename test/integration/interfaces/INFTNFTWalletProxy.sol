// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface INFTNFTWalletProxy {
    function execTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory);
}