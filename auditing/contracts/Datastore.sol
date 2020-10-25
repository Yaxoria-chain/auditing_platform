// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract Datastore is Pausable {
    
    using SafeMath for uint256;

    // Daisy chain the data stores backwards to allow recursive backwards search.
    address public previousDatastore;

    string constant public version = "Demo: 1";
    
    // Stats for auditors and contracts
    uint256 public activeAuditorCount;
    uint256 public suspendedAuditorCount;

    uint256 public approvedContractCount;
    uint256 public opposedContractCount;

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

    // State changes to auditors
    event AddedAuditor(     address indexed _owner, address indexed _auditor);
    event SuspendedAuditor( address indexed _owner, address indexed _auditor);
    event ReinstatedAuditor(address indexed _owner, address indexed _auditor);

    // Auditor migration
    event AcceptedMigration(address indexed _migrator, address indexed _auditor);
    event RejectedMigration(address indexed _migrator, address indexed _auditor);

    // Completed audits
    event NewRecord(address indexed _auditor, string indexed _hash, bool indexed _approved);

    // Daisy chain stores
    event LinkedDataStore(address indexed _owner, address indexed _dataStore);
    
    constructor() Pausable() public {}

    function hasAuditorRecord(address _auditor) external view returns (bool) {
        return _hasAuditorRecord(_auditor);
    }

    function isAuditor(address _auditor) external view returns (bool) {
        // Ambigious private call, call with caution or use with hasAuditorRecord()
        return _isAuditor(_auditor);
    }

    function hasContractRecord(string memory _contract) external view returns (bool) {
        return _hasContractRecord(_contract);
    }

    function auditorDetails(address _auditor) external view returns (bool, uint256, uint256) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");

        return 
        (
            auditors[_auditor].isAuditor, 
            auditors[_auditor].approvedContracts.length, 
            auditors[_auditor].opposedContracts.length
        );
    }

    function auditorApprovedContract(address _auditor, uint256 _index) external view returns (string memory) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].approvedContracts.length, "Approved list is empty");
        require(_index <= auditors[_auditor].approvedContracts.length, "Record does not exist");

        if (_index != 0) {
            _index = _index.sub(1);
        }

        return auditors[_auditor].approvedContracts[_index];
    }

    function auditorOpposedContract(address _auditor, uint256 _index) external view returns (string memory) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].opposedContracts.length, "Opposed list is empty");
        require(_index <= auditors[_auditor].opposedContracts.length, "Record does not exist");

        if (_index != 0) {
            _index = _index.sub(1);
        }

        return auditors[_auditor].opposedContracts[_index];
    }

    function contractDetails(string memory _contract) external view returns (address, bool) {
        require(_hasContractRecord(_contract), "No contract record in the current store");

        return 
        (
            contracts[_contract].auditor, 
            contracts[_contract].approved 
        );
    }

    function addAuditor(address _auditor) external onlyOwner() whenNotPaused() {
        // We are adding the auditor for the first time into this data store
        require(!_hasAuditorRecord(_auditor), "Auditor record already exists");

        auditors[_auditor].isAuditor = true;
        auditors[_auditor].auditor = _auditor;
        
        activeAuditorCount = activeAuditorCount.add(1);

        emit AddedAuditor(_msgSender(), _auditor);
    }

    function suspendAuditor(address _auditor) external onlyOwner() {
        // Do not change previous stores. Setting to false in the current store should prevent actions
        // from future stores when recursively searching
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(_isAuditor(_auditor), "Auditor has already been suspended");

        auditors[_auditor].isAuditor = false;
        
        activeAuditorCount = activeAuditorCount.sub(1);
        suspendedAuditorCount = suspendedAuditorCount.add(1);

        emit SuspendedAuditor(_msgSender(), _auditor);
    }

    function reinstateAuditor(address _auditor) external onlyOwner() whenNotPaused() {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(!_isAuditor(_auditor), "Auditor already has active status");

        auditors[_auditor].isAuditor = true;
        
        activeAuditorCount = activeAuditorCount.add(1);
        suspendedAuditorCount = suspendedAuditorCount.sub(1);

        emit ReinstatedAuditor(_msgSender(), _auditor);
    }

    function completeAudit(address _auditor, bool _approved, bytes calldata _txHash) external onlyOwner() whenNotPaused() {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(_isAuditor(_auditor), "Auditor has been suspended");

        // Using bytes, calldata and external is cheap however over time string conversions may add up
        // so just store the string instead ("pay up front")
        string memory _hash = string(_txHash);

        // Defensively code against everything
        require(contracts[_hash].auditor == address(0), "Contract has already been audited");

        if (_approved) {
            auditors[_auditor].approvedContracts.push(_hash);
            approvedContractCount = approvedContractCount.add(1);
        } else {
            auditors[_auditor].opposedContracts.push(_hash);
            opposedContractCount = opposedContractCount.add(1);
        }

        contracts[_hash].auditor = _auditor;
        contracts[_hash].approved = _approved;

        emit NewRecord(_auditor, _hash, _approved);
    }

    function migrate(address _migrator, address _auditor) external onlyOwner() {
        // Auditor should not exist to mitigate event spamming or possible neglectful changes to 
        // _recursiveAuditorSearch(address) which may allow them to switch their suspended status to active
        require(!_hasAuditorRecord(_auditor), "Already in data store");
        
        // Call the private method to begin the search
        // Also, do not shadow the function name
        bool isAnAuditor = _recursiveAuditorSearch(_auditor);

        // The latest found record indicates that the auditor is active / not been suspended
        if (isAnAuditor) {
            // We can migrate them to the current store
            // Do not rewrite previous audits into each new datastore as that will eventually become too expensive
            auditors[_auditor].isAuditor = true;
            auditors[_auditor].auditor = _auditor;

            activeAuditorCount = activeAuditorCount.add(1);

            emit AcceptedMigration(_migrator, _auditor);
        } else {
            // Auditor has either never been in the system or have been suspended in the latest record
            emit RejectedMigration(_migrator, _auditor);
        }
    }

    function _hasAuditorRecord(address _auditor) private view returns (bool) {
        return auditors[_auditor].auditor != address(0);
    }

    function _isAuditor(address _auditor) private view returns (bool) {
        // This will return false in both cases where an auditor has not been added into this datastore
        // or if they have been added but suspended
        return auditors[_auditor].isAuditor;
    }

    function _hasContractRecord(string memory _contract) private view returns (bool) {
        return contracts[_contract].auditor != address(0);
    }

    function isAuditorRecursiveSearch(address _auditor) external view returns (bool) {
        // Check in all previous stores if the latest record of them being an auditor is set to true/false
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveAuditorSearch(_auditor);
    }

    function contractDetailsRecursiveSearch(string memory _contract) external view returns (address, bool) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveContractDetailsSearch(_contract);
    }

    function _recursiveContractDetailsSearch(string memory _contract) private view returns (address, bool) {
        address _auditor;
        bool _approved;

        if (_hasContractRecord(_contract)) {
            _auditor = contracts[_contract].auditor;
            _approved = contracts[_contract].approved;            
        } else if (previousDatastore != address(0)) {
            (bool success, bytes memory data) = previousDatastore.staticcall(abi.encodeWithSignature("contractDetailsRecursiveSearch(address)", _contract));

            require(success, string(abi.encodePacked("Unknown error when recursing in datastore version: ", version)));
            
            (_auditor, _approved) = abi.decode(data, (address, bool));
        } else {
            revert("No contract record in any data store");
        }

        return (_auditor, _approved);
    }

    function _recursiveAuditorSearch(address _auditor) private view returns (bool) {
        // Technically not needed as default is set to false but lets be explicit
        // Also, do not shadow the function name
        bool isAnAuditor = false;

        if (_hasAuditorRecord(_auditor)) {
            if (_isAuditor(_auditor)) {
                isAnAuditor = true;
            }
        } else if (previousDatastore != address(0)) {
            (bool success, bytes memory data) = previousDatastore.staticcall(abi.encodeWithSignature("isAuditorRecursiveSearch(address)", _auditor));
            
            require(success, string(abi.encodePacked("Unknown error when recursing in datastore version: ", version)));

            isAnAuditor = abi.decode(data, (bool));
        } else {
            revert("No auditor record in any data store");
        }

        return isAnAuditor;
    }

    function linkDataStore(address _dataStore) external onlyOwner() {
        previousDatastore = _dataStore;
        emit LinkedDataStore(_msgSender(), previousDatastore);
    }
}
