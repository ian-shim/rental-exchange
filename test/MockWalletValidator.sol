// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../src/interfaces/INFTNFTWalletValidator.sol";

contract MockWalletValidator is INFTNFTWalletValidator {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _approvedWallets;

    function addWallet(address proxy) external {
        require(proxy != address(0), "Invalid wallet address");
        _approvedWallets.add(proxy);
    }

    function removeWallet(address proxy) external {
        require(proxy != address(0), "Invalid wallet address");
        _approvedWallets.remove(proxy);
    }

    function isWalletApproved(address proxy) external view override returns (bytes4) {
        require(proxy != address(0), "Invalid wallet address");

        if (_approvedWallets.contains(proxy)) {
            return APPROVED_WALLET_MAGIC_VALUE;
        }

        return 0x0;
    }
}