// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Donations is Ownable, Pausable {

    // The non-fungible, non-transferable token can be updated over time as newer versions are released
    address public NFT;

    // value used as a start/stop mechanic for donating
    bool public paused;

    event Donated(address indexed _donator, uint256 _value);
    event ChangedNFT(address indexed _NFT);
    event SelfDestructed(address _self);

    constructor(address _NFT) Ownable() Pausable() public {
        // Launch the NFT with the platform
        setNFT(_NFT);

        // Pause donations at the start until we are ready
        _pause();
    }

    function donate() external payable {
        require(!paused(), "Donations are currently paused");

        // Accept any donation (including 0) but ...
        // if donation >= 0.1 ether then mint the non-fungible token as a collectible / thank you
        if (msg.value >= 100000000000000000) 
        {
            // Call the mint function of the current NFT contract
            // keep in mind that you can keep donating but you will only ever receive ONE
            // NFT in total (per NFT type). This should not mint additional tokens
            NFT.call(abi.encodeWithSignature("mint(address)", _msgSender()));
        }

        // Transfer the value to the owner
        owner.transfer(msg.value);

        emit Donated(_msgSender(), msg.value);
    }

    function pause() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _pause();
    }

    function unpause() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _unpause();
    }

    function setNFT(address _NFT) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        // Over time new iterations of (collectibles) NFTs shall be issued.

        // For user convenience it would be better to inform the user instead of just changing
        // the NFT. Exmaples include minimum time locks, total number of donations or a fund goal
        NFT = _NFT;

        emit ChangedNFT(NFT);
    }

    function destroyContract() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        emit SelfDestructed(address(this));        
        selfdestruct(owner);
    }
}