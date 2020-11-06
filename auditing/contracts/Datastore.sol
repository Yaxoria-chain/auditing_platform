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
        address    auditor;
        bool       isAuditor;
        uint256[]  approvedContracts;
        uint256[]  opposedContracts;
    }

    struct Deployer {
        address    deployer;
        uint256[]  approvedContracts;
        uint256[]  opposedContracts;
    }

    struct Contract {
        address auditor;
        address contractHash;
        address deployer;
        bool    approved;
        bool    destructed;
        string  creationHash;
    }

    Contract[] public contracts;

    mapping(address => Auditor)  private auditors;
    mapping(address => Deployer) private deployers;

    // Note for later, 0th index is used to check if it already exists
    mapping(address => uint256) public contractHash;
    mapping(string => uint256)  public contractCreationHash;

    // State changes to auditors
    event AddedAuditor(     address indexed _owner, address indexed _auditor);
    event SuspendedAuditor( address indexed _owner, address indexed _auditor);
    event ReinstatedAuditor(address indexed _owner, address indexed _auditor);

    // Auditor migration
    event AcceptedMigration(address indexed _migrator, address indexed _auditor);

    // Completed audits
    event NewRecord(address indexed _auditor, address indexed _deployer, address _contract, string _hash, bool indexed _approved, uint256 _contractIndex);

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

    function auditorDetails(address _auditor) external view returns (bool, uint256, uint256) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");

        return 
        (
            auditors[_auditor].isAuditor, 
            auditors[_auditor].approvedContracts.length, 
            auditors[_auditor].opposedContracts.length
        );
    }

    function auditorApprovedContract(address _auditor, uint256 _index) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].approvedContracts.length, "Approved list is empty");
        require(_index <= auditors[_auditor].approvedContracts.length, "Record does not exist");

        if (_index != 0) {
            _index = _index.sub(1);
        }

        uint256 _contractIndex = auditors[_auditor].approvedContracts[_index];

        return _contractDetails(_contractIndex);
    }

    function auditorOpposedContract(address _auditor, uint256 _index) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].opposedContracts.length, "Opposed list is empty");
        require(_index <= auditors[_auditor].opposedContracts.length, "Record does not exist");

        if (_index != 0) {
            _index = _index.sub(1);
        }

        uint256 _contractIndex = auditors[_auditor].opposedContracts[_index];

        return _contractDetails(_contractIndex);
    }

    function hasContractRecord(address _contractHash) external view returns (bool) {
        return _hasContractRecord(_contractHash);
    }

    function hasContractCreationRecord(string memory _contract) external view returns (bool) {
        return _hasCreationRecord(_contract);
    }

    function contractDetails(address _contractHash) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasContractRecord(_contractHash), "No contract record in the current store");

        uint256 _contractIndex = contractHash[_contractHash];

        return _contractDetails(_contractIndex);
    }

    function contractCreationDetails(address _creationHash) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasCreationRecord(_creationHash), "No contract record in the current store");

        uint256 _contractIndex = creationHash[_contractHash];

        return _contractDetails(_contractIndex);
    }

    function hasDeployerRecord(address _deployer) external view returns (bool) {
        return _hasDeployerRecord(_deployer);
    }

    function deployerDetails(address _deployer) external view returns (uint256, uint256) {
        require(_hasDeployerRecord(_deployer), "No deployer record in the current store");

        return 
        (
            deployers[_deployer].approvedContracts.length, 
            deployers[_deployer].opposedContracts.length
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

        if (_hasAuditorRecord(_auditor)) {
            if (!_isAuditor(_auditor)) {
                revert("Auditor has already been suspended");
            }
            activeAuditorCount = activeAuditorCount.sub(1);
        } else {
            auditors[_auditor].auditor = _auditor;
        }

        auditors[_auditor].isAuditor = false;
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

    function completeAudit(address _auditor, address _deployer, address _contract, bool _approved, bytes calldata _txHash) external onlyOwner() whenNotPaused() {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(_isAuditor(_auditor), "Auditor has been suspended");

        require(contractHash[_contract] != 0, "Contract exists in the contracts mapping");

        string memory _hash = string(_txHash);

        require(contractCreationHash[_hash] != 0, "Contract exists in the contract creation hash mapping");

        // TODO: can I omit the destructed argument since the default bool is false?
        Contract _contractData = Contract({
            auditor:        _auditor,
            contractHash:   _contract,
            deployer:       _deployer,
            approved:       _approved, 
            destructed:     false,
            creationHash:   _hash
        });

        contracts[contracts.length++] = _contractData;
        uint256 _contractIndex = contracts.length;

        if (deployers[_deployer].deployer == address(0)) {
            deployers[_deployer].deployer = _deployer;
        }

        if (_approved) {
            auditors[_auditor].approvedContracts.push(_contractIndex);
            deployers[_deployer].approvedContracts.push(_contractIndex);

            approvedContractCount = approvedContractCount.add(1);
        } else {
            auditors[_auditor].opposedContracts.push(_contractIndex);
            deployers[_deployer].opposedContracts.push(_contractIndex);
            
            opposedContractCount = opposedContractCount.add(1);
        }

        contractHash[_contract] = _contractIndex;
        contractCreationHash[_hash] = _contractIndex;

        emit NewRecord(_auditor, _deployer, _contract, _hash, _approved, _contractIndex);
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
            revert("Auditor is either suspended or has never been in the system");
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

    function _hasDeployerRecord(address _deployer) private view returns (bool) {
        return deployers[_deployer].deployer != address(0);
    }

    function _hasContractRecord(address _contractHash) private view returns (bool) {
        return contractHash[_contractHash] != 0;
    }

    function _hasCreationRecord(address _creationHash) private view returns (bool) {
        return creationHash[_creationHash] != 0;
    }

    function isAuditorRecursiveSearch(address _auditor) external view returns (bool) {
        // Check in all previous stores if the latest record of them being an auditor is set to true/false
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveAuditorSearch(_auditor);
    }

    function contractDetailsRecursiveSearch(string memory _contract) external view returns (address, bool, bool, string memory) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveContractDetailsSearch(_contract, true);
    }

    function contractCreationDetailsRecursiveSearch(string memory _contract) external view returns (address, bool, bool, string memory) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveContractDetailsSearch(_contract, false);
    }

    function _recursiveContractDetailsSearch(string memory _contract, bool _contractHash) private view returns (address, bool, bool, string memory) {
        address _auditor;
        bool    _approved;
        bool    _destructed;
        string  _hash;

        if (_contractHash) {
            if (_hasContractRecord(_contract)) {
                _auditor    = contracts[_contract].data.auditor;
                _approved   = contracts[_contract].data.approved;
                _destructed = contracts[_contract].data.destructed;
                _hash       = contracts[_contract].creationHash;
            } else if (previousDatastore != address(0)) {
                (_auditor, _approved, _destructed, _hash) = _contractLookup("contractDetailsRecursiveSearch");
            } else {
                revert("No contract record in any data store");
            }
        } else {
            if (_hasCreationRecord(_contract)) {
                _auditor    = creationHash[_contract].data.auditor;
                _approved   = creationHash[_contract].data.approved;
                _destructed = creationHash[_contract].data.destructed;
                _hash       = creationHash[_contract].contractHash;
            } else if (previousDatastore != address(0)) {
                (_auditor, _approved, _destructed, _hash) = _contractLookup("contractCreationDetailsRecursiveSearch");
            } else {
                revert("No contract record in any data store");
            }
        }

        return (_auditor, _approved, _destructed, _hash);
    }

    function _contractLookup(string memory _function) private view returns returns (address, bool, bool, string memory) {
        string memory _signature = string(abi.encodePacked(_function, "(string)")
        (bool success, bytes memory data) = previousDatastore.staticcall(abi.encodeWithSignature(_signature, _contract));

        require(success, string(abi.encodePacked("Unknown error when recursing in datastore version: ", version)));
        
        (_auditor, _approved, _destructed, _creationHash) = abi.decode(data, (address, bool, bool, string));
        return (_auditor, _approved, _destructed, _creationHash);
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

    function _contractDetails(uint256 _index) private view returns (address, address, address, bool, bool, string memory) {
        require(0 < contracts.length, "No contracts have been added");
        require(_index <= contracts.length, "Record does not exist");

        return 
        (
            contracts[_index].auditor,
            contracts[_index].contractHash,
            contracts[_index].deployer,
            contracts[_index].approved,
            contracts[_index].destructed,
            contracts[_index].creationHash
        );
    }

    // TODO: take back ownership and then give it to the 0th address once you are changed to a newer version
    function linkDataStore(address _dataStore) external onlyOwner() {
        previousDatastore = _dataStore;
        emit LinkedDataStore(_msgSender(), previousDatastore);
    }
}
