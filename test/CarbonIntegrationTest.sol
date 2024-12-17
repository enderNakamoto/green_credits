// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Controller.sol";
import "../test/MockUSDC.sol";

contract CarbonIntegrationTest is Test {
   Controller public controller;
   MockUSDC public usdc;
   address public owner;
   address public priceOracle;
   address public odometerProcessor;
   address public tesla1;
   address public tesla2;
   address public buyer;

   function setUp() public {
       // Create addresses
       owner = makeAddr("owner");
       priceOracle = makeAddr("priceOracle");
       odometerProcessor = makeAddr("odometerProcessor");
       tesla1 = makeAddr("tesla1");
       tesla2 = makeAddr("tesla2");
       buyer = makeAddr("buyer");

       vm.startPrank(owner);
       
       // Deploy system
       usdc = new MockUSDC();
       controller = new Controller(address(usdc), priceOracle, odometerProcessor);
       
       // Fund buyer with USDC
       usdc.transfer(buyer, 10000 * 10**6); // 10k USDC
       
       vm.stopPrank();
   }

   function test_CompleteFlow() public {
       // Step 2: Process odometer readings - Add Queue verification
       vm.startPrank(odometerProcessor);

       assertEq(controller.totalCreditsMinted(), 0, "Total credits minted should be 0");
         assertEq(controller.totalCreditsBurned(), 0, "Total credits burned should be 0");
       
       // Tesla1 drives 350 miles (3 credits)
       controller.registerVehicle(tesla1, "TESLA2023_1");
       controller.processOdometerReading(tesla1, 350);
       assertEq(controller.carbonQueue()._getAvailableCredits(), 3, "Queue should have 3 credits after Tesla1");
       
       // Tesla2 drives 250 miles (2 credits)
       controller.registerVehicle(tesla2, "TESLA2023_2");
       controller.processOdometerReading(tesla2, 250);
       assertEq(controller.carbonQueue()._getAvailableCredits(), 5, "Queue should have 5 total credits");
       
       // Verify the first credit in queue belongs to Tesla1
       (address queueFirstHolder,, bool isValid) = controller.carbonQueue()._getCreditDetails(0);
       assertEq(queueFirstHolder, tesla1, "First credit should belong to Tesla1");
       assertTrue(isValid, "First credit should be valid");
       
       // Verify a later credit belongs to Tesla2
       (address queueLaterHolder,,) = controller.carbonQueue()._getCreditDetails(3);
       assertEq(queueLaterHolder, tesla2, "Fourth credit should belong to Tesla2");
       
       vm.stopPrank();

       // Step 3: Buyer purchases 4 credits - Add Queue verification
       vm.startPrank(buyer);
       usdc.approve(address(controller), 1000 * 10**6);
       controller.burnCredit(4);
       
       // Verify Queue state after burning
       assertEq(controller.carbonQueue()._getAvailableCredits(), 1, "Queue should have 1 credit left");
       
       // Verify first 4 credits are now invalid
       (,, bool isValidAfterBurn) = controller.carbonQueue()._getCreditDetails(0);
       assertFalse(isValidAfterBurn, "First credit should be invalid after burn");
       
       // Verify the remaining credit belongs to Tesla2 and is still valid
       (address remainingHolder,, bool remainingValid) = controller.carbonQueue()._getCreditDetails(4);
       assertEq(remainingHolder, tesla2, "Remaining credit should belong to Tesla2");
       assertTrue(remainingValid, "Remaining credit should be valid");
       
       vm.stopPrank();
       
       // Step 4: Both Tesla owners withdraw their rewards
       uint256 tesla1InitialBalance = usdc.balanceOf(tesla1);
       uint256 tesla2InitialBalance = usdc.balanceOf(tesla2);
       
       vm.prank(tesla1);
       controller.withdrawRewards();
       
       vm.prank(tesla2);
       controller.withdrawRewards();
       
       // Verify final states
       assertEq(
           usdc.balanceOf(tesla1), 
           tesla1InitialBalance + (3 * 100 * 10**6), 
           "Tesla1 should have received 300 USDC"
       );
       assertEq(
           usdc.balanceOf(tesla2), 
           tesla2InitialBalance + (1 * 100 * 10**6), 
           "Tesla2 should have received 100 USDC"
       );

         // Verify total credits minted and burned
        assertEq(controller.totalCreditsMinted(), 5, "Total credits minted should be 5");
        assertEq(controller.totalCreditsBurned(), 4, "Total credits burned should be 4");

        // veriify total credit balance
        assertEq(controller.availableCredits(), 1, "System should have 1 credit left");
   }
}