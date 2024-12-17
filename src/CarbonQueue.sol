// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CarbonQueue is Ownable {

    /*
     STATE VARIABLES 
    */

    struct Credit {
        address holder;
        uint256 timestamp;
        bool isValid;
    }
    
    mapping(uint256 => Credit) internal credits;
    uint256 internal nextMintIndex;
    uint256 internal nextBurnIndex;
    
    address internal controller;


    /* 
     MODIFIERS 
    */
   
    modifier onlyController() {
        require(msg.sender == controller, "Only controller");
        _;
    }
    
    /*
     CONSTRUCTOR 
    */  
    constructor(address _controller) Ownable(msg.sender) {
        require(_controller != address(0), "Invalid controller");
        controller = _controller;
    }
    
    function _enqueueCredit(address holder) external onlyController returns (uint256) {
        uint256 creditIndex = nextMintIndex;
        credits[nextMintIndex] = Credit({
            holder: holder,
            timestamp: block.timestamp,
            isValid: true
        });
        nextMintIndex++;
        return creditIndex;
    }
    
    function _dequeueCredit() external onlyController returns (address) {
        require(nextMintIndex > nextBurnIndex, "No credits available");
        require(credits[nextBurnIndex].isValid, "Invalid credit");
        
        address holder = credits[nextBurnIndex].holder;
        credits[nextBurnIndex].isValid = false;
        nextBurnIndex++;
        
        return holder;
    }
    
    function _getAvailableCredits() external view returns (uint256) {
        return nextMintIndex - nextBurnIndex;
    }
    
    function _getCreditDetails(uint256 index) external view returns (
        address holder,
        uint256 timestamp,
        bool isValid
    ) {
        Credit memory credit = credits[index];
        return (credit.holder, credit.timestamp, credit.isValid);
    }
}
