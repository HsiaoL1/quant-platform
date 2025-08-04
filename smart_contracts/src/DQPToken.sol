// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DQPToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * 10**18; // 20%
    uint256 public constant COMMUNITY_ALLOCATION = 400_000_000 * 10**18; // 40%
    uint256 public constant ECOSYSTEM_ALLOCATION = 300_000_000 * 10**18; // 30%
    uint256 public constant TREASURY_ALLOCATION = 100_000_000 * 10**18; // 10%
    
    constructor(
        address teamWallet,
        address communityWallet,
        address ecosystemWallet,
        address treasuryWallet
    ) 
        ERC20("DeFi Quant Platform Token", "DQP") 
        ERC20Permit("DeFi Quant Platform Token") 
        Ownable(msg.sender) 
    {
        require(teamWallet != address(0), "Team wallet cannot be zero address");
        require(communityWallet != address(0), "Community wallet cannot be zero address");
        require(ecosystemWallet != address(0), "Ecosystem wallet cannot be zero address");
        require(treasuryWallet != address(0), "Treasury wallet cannot be zero address");
        
        _mint(teamWallet, TEAM_ALLOCATION);
        _mint(communityWallet, COMMUNITY_ALLOCATION);
        _mint(ecosystemWallet, ECOSYSTEM_ALLOCATION);
        _mint(treasuryWallet, TREASURY_ALLOCATION);
    }
    
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }
    
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }
    
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}