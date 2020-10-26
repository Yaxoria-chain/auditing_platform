// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "./Ownable.sol";

contract Auditable is Ownable {

    address public auditor;
    address public platform;

    // Indicates whether the audit has been completed or is in progress
    bool public audited;
    // Indicates whether the audit has been approved (true) or opposed (false)
    bool public approved;

    // A deployed contract has a creation hash, store it so that you can access the code 
    // post self destruct from an external location
    string public contractCreationHash;

    modifier isApproved() {
        require(approved, "Functionality blocked until contract is approved");
        _;
    }

    event SetAuditor(   address indexed _sender, address indexed _auditor);
    event SetPlatform(  address indexed _sender, address indexed _platform);

    event ApprovedAudit(address _auditor);
    event OpposedAudit( address _auditor);

    event CreationHashSet(string _hash);

    constructor(address _auditor, address _platform) Ownable() internal {
        _setAuditor(_auditor);
        _setPlatform(_platform);
    }

    function setContractCreationHash(string memory _hash) external onlyOwner() {
        // Prevent the owner from setting the hash post audit for safety
        require(!audited, "Contract has already been audited");

        // We do not want the deployer to change this as the auditor is approving/opposing
        // Auditor can check that this has been set at the beginning and move on
        require(bytes(contractCreationHash).length == 0, "Hash has already been set");

        contractCreationHash = _hash;

        emit CreationHashSet(contractCreationHash);
    }

    function setAuditor(address _auditor) external {
        _setAuditor(_auditor);
    }

    function setPlatform(address _platform) external {
        _setPlatform(_platform);
    }

    function _setAuditor(address _auditor) private {
        // If auditor bails then owner can change
        // If auditor loses contact with owner and cannot complete the audit then they can change
        require(_msgSender() == auditor || _msgSender() == _owner(), "Auditor and Owner only");

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require(!audited, "Cannot change auditor post audit");

        auditor = _auditor;

        emit SetAuditor(_msgSender(), auditor);
    }

    function _setPlatform(address _platform) private {
        // If auditor bails then owner can change
        // If auditor loses contact with owner and cannot complete the audit then they can change
        require(_msgSender() == auditor || _msgSender() == _owner(), "Auditor and Owner only");

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require(!audited, "Cannot change platform post audit");

        platform = _platform;

        emit SetPlatform(_msgSender(), platform);
    }

    function approveAudit(string memory _hash) external {
        // Only the auditor should be able to approve
        require(_msgSender() == auditor, "Auditor only");

        // Make sure that the hash has been set and that they match
        require(bytes(contractCreationHash).length != 0, "Hash has not been set");
        require(keccak256(abi.encodePacked(_hash)) == keccak256(abi.encodePacked(contractCreationHash)), "Hashes do not match");
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require(!audited, "Contract has already been audited");

        // Switch to true to complete audit and approve
        audited = true;
        approved = true;

        // Delegate the call via the platform to complete the audit        
        (bool _success, ) = platform.delegatecall(abi.encodeWithSignature("completeAudit(address,bool,bytes)", address(this), approved, abi.encodePacked(_hash)));

        require(_success, "Unknown error, up the chain, when approving the audit");

        emit ApprovedAudit(_msgSender());
    }

    function opposeAudit(string memory _hash) external {
        // Only the auditor should be able to approve
        require(_msgSender() == auditor, "Auditor only");

        // Make sure that the hash has been set and that they match
        require(bytes(contractCreationHash).length != 0, "Hash has not been set");
        require(keccak256(abi.encodePacked(_hash)) == keccak256(abi.encodePacked(contractCreationHash)), "Hashes do not match");
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require(!audited, "Cannot oppose an audited contract");

        // Switch to true to complete the audit and explicitly set approved to false (default is false)
        audited = true;
        approved = false;

        // Delegate the call via the platform to complete the audit
        (bool _success, ) = platform.delegatecall(abi.encodeWithSignature("completeAudit(address,bool,bytes)", address(this), approved, abi.encodePacked(_hash)));

        require(_success, "Unknown error, up the chain, when opposing the audit");

        emit OpposedAudit(_msgSender());
    }

    function nuke() external {
        require(_msgSender() == auditor || _msgSender() == _owner(), "Auditor and Owner only");
        require(audited, "Cannot nuke an unaudited contract");
        require(!approved, "Cannot nuke an approved contract");
        selfdestruct(_owner());
    }
}