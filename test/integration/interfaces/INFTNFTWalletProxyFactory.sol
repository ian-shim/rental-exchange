// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./INFTNFTWalletProxy.sol";

interface INFTNFTWalletProxyFactory {
    function createProxyWithNonce(
        uint256 saltNonce
    ) external returns (INFTNFTWalletProxy proxy);
}