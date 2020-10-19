//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IERC20Token.sol";
import "./DevAward.sol";
import "./AwardInfo.sol";

contract AwardContract is DevAward, AwardInfo, Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IErc20Token;

    // platform token
    IErc20Token public platformToken;
    mapping(address => bool) public governors;
    modifier onlyGovernor{
        require(governors[_msgSender()], "RewardContract: RewardContract:: caller is not the governor");
        _;
    }

    event AddFreeAward(address user, uint256 amount);
    event AddAward(address user, uint256 amount);
    event Withdraw(address user, uint256 amount, uint256 tax);

    constructor(
        IErc20Token _platformToken,
        uint256 _taxEpoch,
        address _treasury,
        address _dev,
        uint256 _devStartBlock,
        uint256 _devPerBlock
    ) public {
        require(_taxEpoch > 0, "RewardContract: RewardContract:: taxEpoch invalid");
        require(_dev != address(0), "RewardContract: dev invalid");
        require(address(_platformToken) != address(0), "RewardContract: platform token invalid");
        require(_devStartBlock != 0, "RewardContract: dev start block invalid");

        platformToken = _platformToken;
        taxEpoch = _taxEpoch;
        governors[_msgSender()] = true;

        // get tax fee
        treasury = _treasury;
        // dev info
        dev = _dev;
        // Dev can receive 10% of platformToken
        MaxAvailAwards = platformToken.maxSupply().mul(10).div(100);
        devPerBlock = _devPerBlock;
        devStartBlock = _devStartBlock;
    }



    // get user total rewards
    function getUserTotalAwards(address user) view public returns (uint256){
        UserInfo memory info = userInfo[user];
        uint256 amount = info.freeAmount;
        if (info.notEmpty) {
            uint256 cursor = info.taxHead;
            while(true){
                amount = amount.add(info.taxList[cursor].amount);
                cursor = cursor.add(1).mod(taxEpoch);
                if(cursor == info.taxTail){
                    break;
                }
            }
        }
        return amount;
    }

    // get user free rewards amount
    function getCurrentFreeAwards(address user) view public returns (uint256){
        uint256 rebaseEp = getCurrEpoch().sub(taxEpoch);
        UserInfo memory info = userInfo[user];
        uint256 amount = info.freeAmount;
        if (info.notEmpty) {
            uint256 cursor = info.taxHead;
            while(info.taxList[cursor].epoch <= rebaseEp){
                amount = amount.add(info.taxList[cursor].amount);
                cursor = cursor.add(1).mod(taxEpoch);
                if(cursor == info.taxTail){
                    break;
                }
            }
        }
        return amount;
    }

    //FIXME
    // get available awards
    function getUserAvailAwards(address user) view public returns (uint256){
        uint256 current = getCurrEpoch();
        uint256 rebaseEp = current.sub(taxEpoch);
        UserInfo memory info = userInfo[user];
        uint256 amount = info.freeAmount;
        if (info.notEmpty) {
            uint256 _ep = taxEpoch.add(1);
            uint256 cursor = info.taxHead;
            while(true){
                if (info.taxList[cursor].epoch > rebaseEp) {
                    uint rate = current.sub(info.taxList[cursor].epoch).add(1).mul(1e12).div(_ep);
                    uint256 available = info.taxList[cursor].amount.mul(rate).div(1e12);
                    amount = amount.add(available);
                } else {
                    amount = amount.add(info.taxList[cursor].amount);
                }
                cursor = cursor.add(1).mod(taxEpoch);
                if(cursor == info.taxTail){
                    break;
                }
            }
        }
        return amount;
    }

    // add governor
    function addGovernor(address governor) onlyOwner external {
        governors[governor] = true;
    }

    // remove governor
    function removeGovernor(address governor) onlyOwner external {
        governors[governor] = false;
    }

    //    // set dev start time
    //    function setDevMineBlock(uint256 blockNum) onlyGovernor external {
    //        require(devStartBlock == 0, "RewardContract: dev start block number already initialized");
    //        devStartBlock = blockNum;
    //    }

    // dev get rewards
    function claimDevAwards() external {
        require(msg.sender == dev, "RewardContract: only dev can receive awards");
        require(devAccAwards <= MaxAvailAwards, "RewardContract: dev awards exceed permitted amount");
        //        require(devStartBlock != 0, "RewardContract: dev awards not release");
        uint256 amount = block.number.sub(devStartBlock).mul(devPerBlock);
        uint256 rewards = amount.sub(devAccAwards);
        if (amount > MaxAvailAwards) {
            rewards = MaxAvailAwards.sub(devAccAwards);
        }
        require(platformToken.issue(dev, rewards), "RewardContract: get awards failed");
        devAccAwards = devAccAwards.add(rewards);
    }


    // add free amount
    function addFreeAward(address _user, uint256 _amount) onlyGovernor external {
        UserInfo storage user = userInfo[_user];
        user.freeAmount = user.freeAmount.add(_amount);
        emit AddFreeAward(_user, _amount);
    }

    // add awards
    function addAward(address _user, uint256 _amount) onlyGovernor external {
        uint256 current = getCurrEpoch();
        // get epoch
        UserInfo storage user = userInfo[_user];
        //
        if (user.taxList.length == 0) {
            user.taxList.push(TaxInfo({
                epoch : current,
                amount : _amount
                }));
            user.taxHead = 0;
            user.taxTail = 1;
            user.notEmpty = true;
        }
        else {
            // taxLIst not full
            if (user.notEmpty) {
                uint256 end;
                if (user.taxTail == 0) {
                    end = user.taxList.length - 1;
                } else {
                    end = user.taxTail.sub(1);
                }
                if (user.taxList[end].epoch >= current) {
                    user.taxList[end].amount = user.taxList[end].amount.add(_amount);
                } else {
                    if (user.taxList.length < taxEpoch) {
                        user.taxList.push(TaxInfo({
                            epoch : current,
                            amount : _amount
                            }));
                    } else {
                        if (user.taxHead == user.taxTail) {
                            rebase(user, current);
                        }
                        user.taxList[user.taxTail].epoch = current;
                        user.taxList[user.taxTail].amount = _amount;
                    }
                    user.taxTail = user.taxTail.add(1).mod(taxEpoch);
                }
            } else {// user.taxHead == user.taxTail
                user.taxList[user.taxTail].epoch = current;
                user.taxList[user.taxTail].amount = _amount;
                user.taxTail = user.taxTail.add(1).mod(taxEpoch);
                user.notEmpty = true;
            }
        }
        emit AddAward(_user, _amount);
    }

    function withdraw(uint256 _amount) external {
        uint256 current = getCurrEpoch();
        uint256 destroy = 0;
        // get base time
        UserInfo storage user = userInfo[msg.sender];
        // rebase
        rebase(user, current);

        if (user.freeAmount >= _amount) {
            user.freeAmount = user.freeAmount.sub(_amount);
        }
        else {
            uint256 arrears = _amount.sub(user.freeAmount);
            user.freeAmount = 0;
            uint256 _head = user.taxHead;
            uint256 _ep = taxEpoch.add(1);
            while (user.notEmpty) {
                // non-levied tax rate
                uint rate = current.sub(user.taxList[_head].epoch).add(1).mul(1e12).div(_ep);

                uint256 available = user.taxList[_head].amount.mul(rate).div(1e12);
                // available token
                if (available >= arrears) {
                    uint256 newAmount = arrears.mul(1e12).div(rate);
                    user.taxList[_head].amount = user.taxList[_head].amount.sub(newAmount);
                    destroy = destroy.add(newAmount.sub(arrears));
                    arrears = 0;
                    break;
                }
                else {
                    arrears = arrears.sub(available);
                    destroy = destroy.add(user.taxList[_head].amount.sub(available));
                    _head = _head.add(1).mod(taxEpoch);
                    if (_head == user.taxTail) {
                        user.notEmpty = true;
                    }
                }
            }
            user.taxHead = _head;
            require(arrears == 0, "RewardContract: Insufficient Balance");
            if (destroy > 0) {
                require(platformToken.issue(treasury, destroy), "RewardContract: levy tax failed");
            }
        }
        require(platformToken.issue(msg.sender, _amount), "RewardContract: get awards failed");
        emit Withdraw(msg.sender, _amount, destroy);
    }

    function destroy(uint256 amount) onlyGovernor external {
        if (amount > 0) {
            require(platformToken.issue(treasury, amount), "RewardContract: levy tax failed");
        }
    }

    function getCurrEpoch() internal view returns (uint256) {
        return now.div(epUnit);
    }

    function rebase(UserInfo storage _user, uint256 _current) internal {
        uint256 rebaseEp = _current.sub(taxEpoch);
        uint256 head = _user.taxHead;
        while (_user.notEmpty && _user.taxList[head].epoch <= rebaseEp) {
            _user.freeAmount = _user.freeAmount.add(_user.taxList[head].amount);
            head = head.add(1).mod(taxEpoch);
            if (head == _user.taxTail) {
                _user.notEmpty = false;
            }
        }
        _user.taxHead = head;
    }

}