//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IERC20Token.sol";
import "./DevAward.sol";
import "./AwardInfo.sol";

contract AwardContract is DevAward, AwardInfo, Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20Token;

    // platform token
    IERC20Token public platformToken;
    mapping(address => bool) public governors;
    modifier onlyGovernor{
        require(governors[_msgSender()], "AwardContract: caller is not the governor");
        _;
    }

    event AddFreeAward(address user, uint256 amount);
    event AddAward(address user, uint256 amount);
    event Withdraw(address user, uint256 amount, uint256 tax);

    constructor(
        IERC20Token _platformToken,
        uint256 _taxEpoch,
        address _treasury,
        address _dev,
        uint256 _devStartBlock,
        uint256 _devPerBlock
    ) public {
        require(_taxEpoch > 0, "AwardContract: taxEpoch invalid");
        require(_dev != address(0), "AwardContract: dev invalid");
        require(address(_platformToken) != address(0), "AwardContract: platform token invalid");
        require(_devStartBlock != 0, "AwardContract: dev start block invalid");

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
            while (true) {
                amount = amount.add(info.taxList[cursor].amount);
                cursor = cursor.add(1).mod(taxEpoch);
                if (cursor == info.taxTail) {
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
            while (info.taxList[cursor].epoch <= rebaseEp) {
                amount = amount.add(info.taxList[cursor].amount);
                cursor = cursor.add(1).mod(taxEpoch);
                if (cursor == info.taxTail) {
                    break;
                }
            }
        }
        return amount;
    }

    // get available awards
    function getUserAvailAwards(address user) view public returns (uint256){
        uint256 current = getCurrEpoch();
        uint256 rebaseEp = current.sub(taxEpoch);
        UserInfo memory info = userInfo[user];
        uint256 amount = info.freeAmount;
        if (info.notEmpty) {
            uint256 _ep = taxEpoch.add(1);
            uint256 cursor = info.taxHead;
            while (true) {
                if (info.taxList[cursor].epoch > rebaseEp) {
                    uint rate = current.sub(info.taxList[cursor].epoch).add(1).mul(1e12).div(_ep);
                    uint256 available = info.taxList[cursor].amount.mul(rate).div(1e12);
                    amount = amount.add(available);
                } else {
                    amount = amount.add(info.taxList[cursor].amount);
                }
                cursor = cursor.add(1).mod(taxEpoch);
                if (cursor == info.taxTail) {
                    break;
                }
            }
        }
        return amount;
    }

    // estimate gas
    function estimateTax(uint256 _amount) view external returns (uint256){
        uint256 _current = getCurrEpoch();
        uint256 tax = 0;
        UserInfo memory user = userInfo[msg.sender];
        if (user.freeAmount >= _amount) {
            return 0;
        }
        else {
            uint256 current = _current;
            uint256 arrears = _amount.sub(user.freeAmount);
            uint256 _head = user.taxHead;
            uint256 _ep = taxEpoch.add(1);
            while (user.notEmpty) {
                // non-levied tax rate
                TaxInfo memory taxInfo = user.taxList[_head];
                uint rate = current.sub(taxInfo.epoch).add(1).mul(1e12).div(_ep);
                if (rate > 1e12) {
                    rate = 1e12;
                }
                uint256 available = taxInfo.amount.mul(rate).div(1e12);
                if (available >= arrears) {
                    uint256 newAmount = arrears.mul(1e12).div(rate);
                    tax = tax.add(newAmount.sub(arrears));
                    arrears = 0;
                    break;
                }
                else {
                    arrears = arrears.sub(available);
                    tax = tax.add(taxInfo.amount.sub(available));
                    _head = _head.add(1).mod(taxEpoch);
                    if (_head == user.taxTail) {
                        break;
                    }
                }
            }
            require(arrears == 0, "AwardContract: Insufficient Balance");
            return tax;
        }
    }

    // add governor
    function addGovernor(address governor) onlyOwner external {
        governors[governor] = true;
    }

    // remove governor
    function removeGovernor(address governor) onlyOwner external {
        governors[governor] = false;
    }

    // dev get rewards
    function claimDevAwards() external {
        require(msg.sender == dev, "AwardContract: only dev can receive awards");
        require(devAccAwards < MaxAvailAwards, "AwardContract: dev awards exceed permitted amount");
        uint256 amount = block.number.sub(devStartBlock).mul(devPerBlock);
        uint256 rewards = amount.sub(devAccAwards);
        if (amount > MaxAvailAwards) {
            rewards = MaxAvailAwards.sub(devAccAwards);
        }
        safeIssue(dev, rewards, "AwardContract: dev claim awards failed");
        devAccAwards = devAccAwards.add(rewards);
    }

    // add free amount
    function addFreeAward(address _user, uint256 _amount) onlyGovernor external {
        UserInfo storage user = userInfo[_user];
        user.freeAmount = user.freeAmount.add(_amount);
        emit AddFreeAward(_user, _amount);
    }

    // add award
    function addAward(address _user, uint256 _amount) onlyGovernor public {
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
            // taxList not full
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
                if (user.taxList.length < taxEpoch) {
                    user.taxList.push(TaxInfo({
                    epoch : current,
                    amount : _amount
                    }));
                } else {
                    user.taxList[user.taxTail].epoch = current;
                    user.taxList[user.taxTail].amount = _amount;
                }
                user.taxTail = user.taxTail.add(1).mod(taxEpoch);
                user.notEmpty = true;
            }
        }
        emit AddAward(_user, _amount);
    }

    // batch add awards
    function batchAddAwards(address[] memory _users, uint256[] memory _amounts) onlyGovernor external {
        require(_users.length == _amounts.length, "AwardContract: params invalid");
        for (uint i = 0; i < _users.length; i++) {
            addAward(_users[i], _amounts[i]);
        }
    }

    function withdraw(uint256 _amount) external {
        uint256 current = getCurrEpoch();
        uint256 _destroy = 0;
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
                    _destroy = _destroy.add(newAmount.sub(arrears));
                    arrears = 0;
                    break;
                }
                else {
                    arrears = arrears.sub(available);
                    _destroy = _destroy.add(user.taxList[_head].amount.sub(available));
                    _head = _head.add(1).mod(taxEpoch);
                    if (_head == user.taxTail) {
                        user.notEmpty = false;
                    }
                }
            }
            user.taxHead = _head;
            require(arrears == 0, "AwardContract: Insufficient Balance");
            safeIssue(treasury, _destroy, "AwardContract: levy tax failed");
        }
        safeIssue(msg.sender, _amount, "AwardContract: claim awards failed");
        emit Withdraw(msg.sender, _amount, _destroy);
    }

    function pendingIncentives() view public returns (uint256){
        uint256 startBlock = devStartBlock.sub(411075); //adjust incentive startBlock(equal to LPStaking startBlock), devStartBlock delays 9 weeks(411075)
        if (block.number <= startBlock) return 0;

        uint256 maxIncent = 745000 * 10 ** 18;
        uint256 incents = block.number.sub(startBlock).mul(15 * 10 ** 16);
        if (incents > maxIncent) {
            return maxIncent.sub(claimedIncentives);
        } else {
            return incents.sub(claimedIncentives);
        }
    }

    function claimIncentives(address to, uint256 amount) external {
        require(msg.sender == dev, "AwardContract: unauthorized");
        require(to != dev, "AwardContract: dev so greedy");
        uint256 pending = pendingIncentives();
        require(amount <= pending, "AwardContract: incentives exceed");
        safeIssue(to, amount, "AwardContract: claim incentives err");
        claimedIncentives = claimedIncentives.add(amount);
    }

    function destroy(uint256 amount) onlyGovernor external {
        safeIssue(treasury, amount, "AwardContract: levy tax failed");
    }

    function getCurrEpoch() internal view returns (uint256) {
        return now.div(epUnit);
    }

    function safeIssue(address user, uint256 amount, string memory err) internal {
        if (amount > 0) {
            require(amount.add(platformToken.totalSupply()) <= platformToken.maxSupply(), "AwardContract: awards exceeds maxSupply");
            require(platformToken.issue(user, amount), err);
        }
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