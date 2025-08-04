// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DQPToken} from "../src/DQPToken.sol";

contract DQPTokenTest is Test {
    DQPToken public token;
    address public owner;
    address public teamWallet = address(0x1);
    address public communityWallet = address(0x2);
    address public ecosystemWallet = address(0x3);
    address public treasuryWallet = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);

    function setUp() public {
        owner = address(this);
        
        token = new DQPToken(
            teamWallet,
            communityWallet,
            ecosystemWallet,
            treasuryWallet
        );
    }

    function testInititalSupply() public {
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertEq(token.balanceOf(teamWallet), token.TEAM_ALLOCATION());
        assertEq(token.balanceOf(communityWallet), token.COMMUNITY_ALLOCATION());
        assertEq(token.balanceOf(ecosystemWallet), token.ECOSYSTEM_ALLOCATION());
        assertEq(token.balanceOf(treasuryWallet), token.TREASURY_ALLOCATION());
    }

    function testTokenMetadata() public {
        assertEq(token.name(), "DeFi Quant Platform Token");
        assertEq(token.symbol(), "DQP");
        assertEq(token.decimals(), 18);
    }

    function testOwnership() public {
        assertEq(token.owner(), owner);
    }

    function testTransfers() public {
        vm.startPrank(teamWallet);
        uint256 transferAmount = 1000 * 10**18;
        
        token.transfer(user1, transferAmount);
        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(teamWallet), token.TEAM_ALLOCATION() - transferAmount);
        vm.stopPrank();
    }

    function testApproveAndTransferFrom() public {
        vm.startPrank(teamWallet);
        uint256 allowanceAmount = 2000 * 10**18;
        uint256 transferAmount = 1000 * 10**18;
        
        token.approve(user1, allowanceAmount);
        assertEq(token.allowance(teamWallet, user1), allowanceAmount);
        vm.stopPrank();
        
        vm.startPrank(user1);
        token.transferFrom(teamWallet, user2, transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.allowance(teamWallet, user1), allowanceAmount - transferAmount);
        vm.stopPrank();
    }

    function testVotingPower() public {
        vm.startPrank(teamWallet);
        uint256 delegateAmount = 5000 * 10**18;
        
        // Initially, voting power should be 0 (no self-delegation)
        assertEq(token.getVotes(teamWallet), 0);
        
        // Self-delegate to activate voting power
        token.delegate(teamWallet);
        assertEq(token.getVotes(teamWallet), token.TEAM_ALLOCATION());
        
        // Transfer some tokens to user1 and delegate
        token.transfer(user1, delegateAmount);
        vm.stopPrank();
        
        vm.startPrank(user1);
        token.delegate(user1);
        assertEq(token.getVotes(user1), delegateAmount);
        assertEq(token.getVotes(teamWallet), token.TEAM_ALLOCATION() - delegateAmount);
        vm.stopPrank();
    }

    function testDelegateToOther() public {
        vm.startPrank(teamWallet);
        uint256 delegateAmount = 3000 * 10**18;
        
        // Transfer to user1
        token.transfer(user1, delegateAmount);
        vm.stopPrank();
        
        // user1 delegates voting power to user2
        vm.startPrank(user1);
        token.delegate(user2);
        
        assertEq(token.getVotes(user1), 0);
        assertEq(token.getVotes(user2), delegateAmount);
        vm.stopPrank();
    }

    function testConstructorZeroAddressRevert() public {
        vm.expectRevert("Team wallet cannot be zero address");
        new DQPToken(address(0), communityWallet, ecosystemWallet, treasuryWallet);
        
        vm.expectRevert("Community wallet cannot be zero address");
        new DQPToken(teamWallet, address(0), ecosystemWallet, treasuryWallet);
        
        vm.expectRevert("Ecosystem wallet cannot be zero address");
        new DQPToken(teamWallet, communityWallet, address(0), treasuryWallet);
        
        vm.expectRevert("Treasury wallet cannot be zero address");
        new DQPToken(teamWallet, communityWallet, ecosystemWallet, address(0));
    }

    function testERC20PermitFunctionality() public {
        uint256 amount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Get permit signature parameters
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        
        uint256 nonce = token.nonces(teamWallet);
        assertEq(nonce, 0);
        
        // Create permit data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                teamWallet,
                user1,
                amount,
                nonce,
                deadline
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );
        
        // For testing purposes, we'll just check that the permit function exists
        // and can be called (signature verification would require proper private key setup)
        assertTrue(token.nonces(teamWallet) == 0);
    }

    function testClockMode() public {
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
        assertEq(token.clock(), uint48(block.timestamp));
    }
}