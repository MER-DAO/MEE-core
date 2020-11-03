//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

interface ITokenVotorV1 {

    function delegates(address delegator) external view returns (address);

    function delegate(address delegatee) external;

    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) external;

    function getCurrentVotes(address account) external view returns (uint256);

    function getPriorVotes(address account, uint blockNumber) external view returns (uint256);

}
