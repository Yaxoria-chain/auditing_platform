// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Auditable is Ownable {

    address public auditor;
    address public platform;

    // Indicates whether the audit has been completed and approved (true) or not (false)
    bool public audited;

    // A deployed contract has a creation hash, store it so that you can access the code 
    // post self destruct from an external location
    string public contractCreationHash;

    modifier isAudited() {
        require(audited, "Not audited");
        _;
    }

    event SetAuditor(address indexed _auditor);
    event SetPlatform(address indexed _platform);
    event ApprovedAudit(address _auditor);
    event OpposedAudit(address _auditor);
    event CreationHashSet(string _hash);

    constructor(address _auditor, address _platform) Ownable() internal {
        _setAuditor(_auditor);
        _setPlatform(_platform);
    }

    function setContractCreationHash(string memory _hash) external onlyOwner() {
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
        require(_msgSender() == auditor || _msgSender() == owner, "Auditor and Owner only");

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require(!audited, "Cannot change auditor post audit");

        auditor = _auditor;

        emit SetAuditor(auditor);
    }

    function _setPlatform(address _platform) private {
        // If auditor bails then owner can change
        // If auditor loses contact with owner and cannot complete the audit then they can change
        require(_msgSender() == auditor || _msgSender() == owner, "Auditor and Owner only");

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require(!audited, "Cannot change platform post audit");

        platform = _platform;

        emit SetPlatform(platform);
    }

    function approveAudit(string memory _hash) external {
        // Only the auditor should be able to approve
        require(_msgSender() == auditor, "Auditor only");

        // Make sure that the hash has been set and that they match
        require(bytes(contractCreationHash).length != 0, "Hash has not been set");
        require(keccak256(abi.encodePacked(_hash)) == keccak256(abi.encodePacked(contractCreationHash)), "Hashes do not match");
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require(!audited, "Contract has already been approved");

        // Switch to true to approve
        audited = true;

        // Delegate the call via the platform to complete the audit        
        platform.delegatecall(abi.encodeWithSignature("completeAudit(address, bool, bytes)", address(this), audited, abi.encodePacked(_hash)));

        emit ApprovedAudit(_msgSender());
    }

    function opposeAudit(string memory _hash) external {
        // Only the auditor should be able to approve
        require(_msgSender() == auditor, "Auditor only");

        // Make sure that the hash has been set and that they match
        require(bytes(contractCreationHash).length != 0, "Hash has not been set");
        require(keccak256(abi.encodePacked(_hash)) == keccak256(abi.encodePacked(contractCreationHash)), "Hashes do not match");
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require(!audited, "Cannot destroy an approved contract");

        // Explicitly set to false to be sure
        audited = false;

        // Delegate the call via the platform to complete the audit
        platform.delegatecall(abi.encodeWithSignature("completeAudit(address, bool, bytes)", address(this), audited, abi.encodePacked(_hash)));

        emit OpposedAudit(_msgSender());
    }
}




