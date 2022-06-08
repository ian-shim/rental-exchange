// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MockERC721 is ERC721 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    constructor() ERC721("Mock", "MNFT") {}

    function mintTo(address owner) external returns (uint256) {
        uint256 newItemId = _tokenIds.current();
        _safeMint(owner, newItemId);
        _tokenIds.increment();
        return newItemId;
    }
}