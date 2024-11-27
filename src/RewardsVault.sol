// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardsVault is Ownable {
    IERC20 internal immutable usdc;
    mapping(address => uint256) internal pendingRewards;
    
    address internal controller;
    
    modifier onlyController() {
        require(msg.sender == controller, "Only controller");
        _;
    }
    
    constructor(address _usdc, address _controller) Ownable(msg.sender){
        require(_usdc != address(0), "Invalid USDC address");
        require(_controller != address(0), "Invalid controller");
        usdc = IERC20(_usdc);
        controller = _controller;
    }
    
    function _addReward(address holder, uint256 amount) internal onlyController {
        pendingRewards[holder] += amount;
    }
    
    function _withdrawRewards(address holder) internal onlyController returns (uint256) {
        uint256 amount = pendingRewards[holder];
        if (amount > 0) {
            pendingRewards[holder] = 0;
            require(usdc.transfer(holder, amount), "Transfer failed");
        }
        return amount;
    }
    
    function _getPendingRewards(address holder) internal view returns (uint256) {
        return pendingRewards[holder];
    }
}