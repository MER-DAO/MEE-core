//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

contract DevAward {
    // dev line release
    address public dev;
    uint256 public devStartBlock;
    uint256 public devAccAwards;
    uint256 public devPerBlock;
    uint256 public MaxAvailAwards;
    uint256 public claimedIncentives;
}
