// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/CarbonQueue.sol";

contract CarbonQueueTest is Test {
    CarbonQueue public queue;
    address public controller;
    address public user1;
    address public user2;

    function setUp() public {
        controller = makeAddr("controller");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        queue = new CarbonQueue(controller);
    }

    function test_Deployment() public {
        // Test controller access
        vm.prank(user1);
        vm.expectRevert("Only controller");
        queue._enqueueCredit(user1);
        
        // Controller should succeed
        vm.prank(controller);
        queue._enqueueCredit(user1);
    }

    function test_DeploymentWithZeroAddress() public {
        vm.expectRevert("Invalid controller");
        new CarbonQueue(address(0));
    }

    function test_EnqueueCredit() public {
        vm.startPrank(controller);
        
        queue._enqueueCredit(user1);
        (address holder, uint256 timestamp, bool isValid) = queue._getCreditDetails(0);
        
        assertEq(holder, user1);
        assertTrue(isValid);
        assertGt(timestamp, 0);
        
        vm.stopPrank();
    }

    function test_GetAvailableCredits() public {
        vm.startPrank(controller);
        
        assertEq(queue._getAvailableCredits(), 0);
        
        queue._enqueueCredit(user1);
        assertEq(queue._getAvailableCredits(), 1);
        
        queue._enqueueCredit(user2);
        assertEq(queue._getAvailableCredits(), 2);
        
        vm.stopPrank();
    }

    function test_DequeueFIFO() public {
        vm.startPrank(controller);
        
        queue._enqueueCredit(user1);
        queue._enqueueCredit(user2);
        
        address firstHolder = queue._dequeueCredit();
        assertEq(firstHolder, user1);
        
        address secondHolder = queue._dequeueCredit();
        assertEq(secondHolder, user2);
        
        vm.stopPrank();
    }

    function test_DequeueInvalidatesCredit() public {
        vm.startPrank(controller);
        
        queue._enqueueCredit(user1);
        queue._dequeueCredit();
        
        (,, bool isValid) = queue._getCreditDetails(0);
        assertFalse(isValid);
        
        vm.stopPrank();
    }

    function test_DequeueEmptyQueue() public {
        vm.prank(controller);
        vm.expectRevert("No credits available");
        queue._dequeueCredit();
    }

    function test_QueueStateAfterMultipleOperations() public {
        vm.startPrank(controller);
        
        // Enqueue multiple credits
        queue._enqueueCredit(user1);
        queue._enqueueCredit(user2);
        queue._enqueueCredit(user1);
        
        // Dequeue some
        queue._dequeueCredit();
        queue._dequeueCredit();
        
        assertEq(queue._getAvailableCredits(), 1);
        
        // Add more
        queue._enqueueCredit(user2);
        assertEq(queue._getAvailableCredits(), 2);
        
        vm.stopPrank();
    }

    function test_NonControllerCannotEnqueue() public {
        vm.prank(user1);
        vm.expectRevert("Only controller");
        queue._enqueueCredit(user1);
    }

    function test_NonControllerCannotDequeue() public {
        vm.prank(controller);
        queue._enqueueCredit(user1);
        
        vm.prank(user1);
        vm.expectRevert("Only controller");
        queue._dequeueCredit();
    }

    function test_ManyCreditsNoOverflow() public {
        vm.startPrank(controller);
        
        // Add 100 credits
        for(uint256 i = 0; i < 100; i++) {
            queue._enqueueCredit(user1);
        }
        assertEq(queue._getAvailableCredits(), 100);
        
        // Remove 50
        for(uint256 i = 0; i < 50; i++) {
            queue._dequeueCredit();
        }
        assertEq(queue._getAvailableCredits(), 50);
        
        vm.stopPrank();
    }

    function test_TimestampAccuracy() public {
        vm.prank(controller);
        queue._enqueueCredit(user1);
        
        (,uint256 timestamp,) = queue._getCreditDetails(0);
        assertGt(timestamp, 0);
        assertEq(timestamp, block.timestamp);
    }

    function testFuzz_EnqueueDequeue(address[] calldata holders) public {
        vm.assume(holders.length > 0);
        vm.startPrank(controller);
        
        // Enqueue all holders
        for(uint256 i = 0; i < holders.length; i++) {
            vm.assume(holders[i] != address(0));
            queue._enqueueCredit(holders[i]);
        }
        
        // Verify FIFO order by dequeuing
        for(uint256 i = 0; i < holders.length; i++) {
            address dequeuedHolder = queue._dequeueCredit();
            assertEq(dequeuedHolder, holders[i]);
        }
        
        vm.stopPrank();
    }
}