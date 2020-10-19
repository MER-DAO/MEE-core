//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

contract AwardInfo {
    struct TaxInfo {
        uint256 epoch;
        uint256 amount;
    }

    struct UserInfo {
        uint256 freeAmount;
        uint256 taxHead;     // queue head element index
        uint256 taxTail;     // queue tail next element index
        bool notEmpty;       // whether taxList is empty where taxHead = taxTail
        TaxInfo[] taxList;
    }

    // tax epoch info
    uint256 public taxEpoch = 9;     // tax epoch and user taxlist max length
    uint256 public epUnit = 1 weeks;  // epoch unit => week

    // user info
    mapping(address => UserInfo) internal userInfo;

    // tax treasury address
    address public treasury;
}
