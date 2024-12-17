// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/RewardsVault.sol";
import "./MockUSDC.sol";

contract RewardsVaultTest is Test {
    RewardsVault public vault;
    MockUSDC public usdc;
    address public controller;
    address public user1;
    address public user2;

    function setUp() public {
        controller = makeAddr("controller");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock USDC and get initial supply
        usdc = new MockUSDC();
        
        // Deploy rewards vault
        vault = new RewardsVault(address(usdc), controller);
        
        // Transfer USDC to vault
        usdc.transfer(address(vault), 1000000 * 10**6); // 1M USDC
    }

    function test_Deployment() public {
        // Test controller access
        vm.prank(user1);
        vm.expectRevert("Only controller");
        vault._addReward(user1, 100);
        
        // Controller should succeed
        vm.prank(controller);
        vault._addReward(user1, 100);
    }

    function test_DeploymentWithZeroAddresses() public {
        vm.expectRevert("Invalid USDC address");
        new RewardsVault(address(0), controller);
        
        vm.expectRevert("Invalid controller");
        new RewardsVault(address(usdc), address(0));
    }

    function test_AddReward() public {
        vm.startPrank(controller);
        
        vault._addReward(user1, 100);
        assertEq(vault._getPendingRewards(user1), 100);
        
        // Add more rewards
        vault._addReward(user1, 50);
        assertEq(vault._getPendingRewards(user1), 150);
        
        vm.stopPrank();
    }

    function test_WithdrawRewards() public {
        // Add rewards
        vm.prank(controller);
        vault._addReward(user1, 100);
        
        uint256 initialBalance = usdc.balanceOf(user1);
        
        // Withdraw
        vm.prank(controller);
        uint256 withdrawn = vault._withdrawRewards(user1);
        
        // Verify withdrawal
        assertEq(withdrawn, 100);
        assertEq(usdc.balanceOf(user1), initialBalance + 100);
        assertEq(vault._getPendingRewards(user1), 0);
    }

    function test_WithdrawZeroRewards() public {
        vm.prank(controller);
        uint256 withdrawn = vault._withdrawRewards(user1);
        assertEq(withdrawn, 0);
    }

    function test_MultipleUsersRewards() public {
        vm.startPrank(controller);
        
        // Add rewards for multiple users
        vault._addReward(user1, 100);
        vault._addReward(user2, 200);
        
        assertEq(vault._getPendingRewards(user1), 100);
        assertEq(vault._getPendingRewards(user2), 200);
        
        // Withdraw for one user
        vault._withdrawRewards(user1);
        
        // Check state
        assertEq(vault._getPendingRewards(user1), 0);
        assertEq(vault._getPendingRewards(user2), 200);
        
        vm.stopPrank();
    }

    function test_AccessControl() public {
        // Non-controller cannot add rewards
        vm.prank(user1);
        vm.expectRevert("Only controller");
        vault._addReward(user1, 100);
        
        // Non-controller cannot withdraw rewards
        vm.prank(user1);
        vm.expectRevert("Only controller");
        vault._withdrawRewards(user1);
        
        // Owner stays owner
        assertEq(vault.owner(), address(this));
    }

    function test_LargeRewards() public {
        vm.startPrank(controller);
        
        uint256 largeAmount = 500_000 * 10**6; // 500k USDC
        vault._addReward(user1, largeAmount);
        
        uint256 withdrawn = vault._withdrawRewards(user1);
        assertEq(withdrawn, largeAmount);
        assertEq(usdc.balanceOf(user1), largeAmount);
        
        vm.stopPrank();
    }

    // function testFuzz_AddWithdrawRewards(address user, uint256 amount) public {
    //     vm.assume(user != address(0));
    //     vm.assume(amount > 0 && amount <= 1000000 * 10**6); // Cap at 1M USDC
        
    //     vm.startPrank(controller);
        
    //     // Add rewards
    //     vault._addReward(user, amount);
    //     assertEq(vault._getPendingRewards(user), amount);
        
    //     // Withdraw rewards
    //     uint256 withdrawn = vault._withdrawRewards(user);
    //     assertEq(withdrawn, amount);
    //     assertEq(vault._getPendingRewards(user), 0);
    //     assertEq(usdc.balanceOf(user), amount);
        
    //     vm.stopPrank();
    // }

    function test_RewardsAccumulation() public {
        vm.startPrank(controller);
        
        // Add rewards in multiple transactions
        for(uint256 i = 1; i <= 5; i++) {
            vault._addReward(user1, 100 * i);
            assertEq(vault._getPendingRewards(user1), 100 * i * (i + 1) / 2);
        }
        
        // Final sum should be 100 + 200 + 300 + 400 + 500 = 1500
        assertEq(vault._getPendingRewards(user1), 1500);
        
        vm.stopPrank();
    }
}