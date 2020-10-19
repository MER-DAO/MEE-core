//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Token is IERC20 {

    function maxSupply() external view returns (uint256);

    function issue(address account, uint256 amount) external returns (bool);

    function burn(uint256 amount) external returns (bool);
}
