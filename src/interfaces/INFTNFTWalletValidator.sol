// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract INFTNFTWalletValidatorConstants {
    // bytes4(keccak256("isWalletApproved(address)")
    bytes4 public constant APPROVED_WALLET_MAGIC_VALUE = 0x3657e851;
}

abstract contract INFTNFTWalletValidator is INFTNFTWalletValidatorConstants {
    function isWalletApproved(address proxy) external view virtual returns (bytes4);
}
