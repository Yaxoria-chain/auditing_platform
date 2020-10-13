// SPDX-License-Identifier: MIT

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Note: that using (Private / Internal) and External is a cheaper combination than Public which must copy data

contract AuditableDataStore is Ownable, Pausable {

    // Daisy chain the data stores backwards and forwards to allow recursive backwards search.
    // The steps to migrate to a newer data store are as follows:
    //      Deploy the new data store (lets call that version X)
    //      Look at version X-1 and if it exists then set previousDataStore in version X to version X-1
    //      Transfer ownership of version X to the current platform
    //      Transfer ownership of version X-1 (from the platform) to the void
    address private previousDataStore;

    string constant public version = "Demo: 1";

    struct Auditor {
        bool     isAuditor;
        address  auditor;
        string[] approvedContracts;
        string[] opposedContracts;
    }

    struct Contract {
        address auditor;
        bool    approved;
    }

    mapping(address => Auditor) private auditors;
    mapping(string => Contract) private contracts;

    // Any state change to an auditor is important
    event AddedAuditor(address indexed _owner, address indexed _auditor);
    event SuspendedAuditor(address indexed _owner, address indexed _auditor);
    event ReinstatedAuditor(address indexed _owner, address indexed _auditor);

    // Do we care who migrated them? Probably a nice to have
    event AcceptedMigration(address indexed _auditor);
    event RejectedMigration(address indexed _auditor);

    // Completed audits
    event NewRecord(address indexed _auditor, string indexed _hash, bool indexed _approved);
    
    constructor() Ownable() Pausable() public {}

    function pause() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _pause();
    }

    function unpause() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _unpause();
    }

    function isAuditor(address _auditor) external returns (bool) {
        return _isAuditor(_auditor);
    }

    function auditorDetails(address _auditor) external returns (bool, uint256, uint256) {
        require(_auditorExists(_auditor), "No auditor record in the current store");

        return 
        (
            auditors[_auditor].isAuditor, 
            auditors[_auditor].approvedContracts.length, 
            auditors[_auditor].opposedContracts.length
        );
    }

    // check the length, will it underflow?
    function auditorApprovedContract(address _auditor, uint256 _index) external returns (string memory) {
        require(_auditorExists(_auditor), "No auditor record in the current store");
        require(_index <= auditors[_auditor].approvedContracts.length - 1, "Index is too large, array out of bounds");

        return auditors[_auditor].approvedContracts[_index];
    }

    // check the length, will it underflow?
    function auditorOpposedContract(address _auditor, uint256 _index) external returns (string memory) {
        require(_auditorExists(_auditor), "No auditor record in the current store");
        require(_index <= auditors[_auditor].opposedContracts.length - 1, "Index is too large, array out of bounds");

        return auditors[_auditor].opposedContracts[_index];
    }

    function contractDetails(address _auditor) external returns (address, bool) {
        require(contracts[_auditor].auditor != address(0), "No contract record in the current store");

        return 
        (
            contracts[_auditor].auditor, 
            contracts[_auditor].approved 
        );
    }

    function isAuditorRecursiveSearch(address _auditor) external returns (bool) {
        return _recursiveAuditorSearch(_auditor);
    }

    function addAuditor(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        require(!paused(), "Addition of auditors is paused");

        // We are adding the auditor for the first time into this data store
        require(!_auditorExists(_auditor), "Auditor record already exists");

        auditors[_auditor].isAuditor = true;
        auditors[_auditor].auditor = _auditor;

        emit AddedAuditor(_msgSender(), _auditor);
    }

    function suspendAuditor(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        // Do not change previous stores. Setting to false in the current store should prevent actions
        // from future stores when recursively searching
        require(_auditorExists(_auditor), "No auditor record in the current store");
        require(_auditorIsActive(_auditor), "Auditor has already been suspended");

        auditors[_auditor].isAuditor = false;

        emit SuspendedAuditor(_msgSender(), _auditor);
    }

    function reinstateAuditor(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        require(!paused(), "Reinstation of auditors is paused");

        require(_auditorExists(_auditor), "No auditor record in the current store");
        require(!_auditorIsActive(_auditor), "Auditor already has active status");

        auditors[_auditor].isAuditor = true;

        emit ReinstatedAuditor(_msgSender(), _auditor);
    }

    function completeAudit(address _auditor, bool _approved, bytes calldata _txHash) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        require(!paused(), "Adding new audits is paused");

        require(_auditorExists(_auditor), "No auditor record in the current store");
        require(_auditorIsActive(_auditor), "Auditor has been suspended");

        // Using bytes, calldata and external is cheap however over time string conversions may add up
        // so just store the string instead ("pay up front")
        string memory _hash = string(_txHash);

        // Defensively code against everything
        require(contracts[_hash].auditor == address(0), "Contract has already been audited");

        if (_approved) {
            auditors[_auditor].approvedContracts.push(_hash);
        } else {
            auditors[_auditor].opposedContracts.push(_hash)
        }

        contracts[_hash].auditor = _auditor;
        contracts[_hash].approved = _approved;

        emit NewRecord(_auditor, _hash, _approved);
    }

    // anyone should be able to call this?
    function migrate(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        // Auditor should not exist to mitigate event spamming or possible neglectful changes to 
        // _recursiveAuditorSearch(address) which may allow them to switch their suspended status to active
        require(!_auditorExists(_auditor), "Already in data store");
        
        // Call the private method to begin the search
        // Also, do not shadow the function name
        bool isAnAuditor = _recursiveAuditorSearch(_auditor);

        // The latest found record indicates that the auditor is active / not been suspended
        if (isAnAuditor) {
            // We can migrate them to the current store
            // Do not rewrite previous audits into each new datastore as that will eventually become too expensive
            auditors[_auditor].isAuditor = true;
            auditors[_auditor].auditor = _auditor;

            emit AcceptedMigration(_auditor);
        } else {
            // Auditor has either never been in the system or have been suspended in the latest record
            emit RejectedMigration(_auditor);
        }
    }

    function _isAuditor(address _auditor) private returns (bool) {
        return _auditorExists(_auditor) && _auditorIsActive(_auditor);
    }

    function _auditorExists(address _auditor) private returns (bool) {
        return auditors[_auditor].auditor != address(0);
    }

    function _auditorIsActive(address _auditor) private returns (bool) {
        return auditors[_auditor].isAuditor;
    }

    function _recursiveAuditorSearch(address _auditor) private returns (bool) {
        // Technically not needed as default is set to false but lets be explicit
        // Also, do not shadow the function name
        bool isAnAuditor = false;

        // Use 2 checks instead of _isAuditor(address) because otherwise it will recurse past a possible False 
        // state until it finds an active (True) state
        if (_auditorExists(_auditor)) {
            if (_auditorIsActive(_auditor)) {
                isAnAuditor = true;
            }
        } else if (previousDataStore != address(0)) {
            isAnAuditor = previousDataStore.call(abi.encodeWithSignature("recursiveAuditorSearch(address)", _auditor));
        }

        return isAnAuditor;
    }

}
