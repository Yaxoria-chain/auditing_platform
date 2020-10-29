// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "./Ownable.sol";

contract Auditable is Ownable {

    address public auditor;
    address public platform;

    /// @notice Indicates whether the audit has been completed or is in progress
    /// @dev Audit is completed when the bool is set to true otherwise the default is false (in progress)
    bool public audited;
    
    /// @notice Indicates whether the audit has been approved or opposed
    /// @dev Consider this bool only after "audited" is true. Approved is true and Opposed (default) if false
    bool public approved;

    /// @notice A deployed contract has a creation hash, store it so that you can access the code post self destruct
    /// @dev When a contract is deployed the first transaction is the contract creation - use that hash
    string public contractCreationHash;

    /// @notice Modifier used to block or allow method functionality based on the approval / opposition of the audit
    /// @dev Use this on every function
    modifier isApproved() {
        require(approved, "Functionality blocked until contract is approved");
        _;
    }

    /// @notice Event tracking who set the auditor and who the auditor is
    /// @dev Index the sender and the auditor for easier searching
    event SetAuditor(   address indexed _sender, address indexed _auditor);
    
    /// @notice Event tracking who set the platform and which platform was set
    /// @dev Index the sender and the platform for easier searching
    event SetPlatform(  address indexed _sender, address indexed _platform);
    
    /// @notice Event tracking the status of the audit and who the auditor is
    event ApprovedAudit(address _auditor);

    /// @notice Event tracking the status of the audit and who the auditor is    
    event OpposedAudit( address _auditor);
    
    /// @notice A contract has a transaction which is the contract creation.
    /// @dev The contract creation hash allows one to view the bytecode of the contract even after it has self destructed
    event CreationHashSet(string _hash);

    /// @notice The inheriting contract must tell us who the audit and platform are to be able to perform an audit
    /// @param _auditor an address of a person who may or may not actually be an auditor
    /// @param _platform an address of a contract which may or may not be a valid platform
    /// @dev Ownable() with our implementation to be cleaner and internal because it is not meant to be public, inherit the methods and variables
    constructor(address _auditor, address _platform) Ownable() internal {
        _setAuditor(_auditor);
        _setPlatform(_platform);
    }

    /// @notice Method used to set the contract creation has before the audit is completed
    /// @dev After deploying this is the first thing that must be done by the owner and the owner only gets 1 attempt to prevent race conditions with the auditor
    /// @param _hash The transaction hash representing the contract creation
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