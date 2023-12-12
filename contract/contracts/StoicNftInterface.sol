// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

interface StoicNftInterface {
    function safeMint(address to) external;

    function balanceOf(address owner) external view returns (uint256);
}
