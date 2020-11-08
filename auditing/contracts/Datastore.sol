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

    bool public activeStore = true;

    Contract[] public contracts;

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

    mapping(address => Auditor)  public auditors;
    mapping(address => Deployer) public deployers;

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

    event ContractDestructed(address indexed _sender, address _contract);

    // Daisy chain stores
    event LinkedDataStore(address indexed _owner, address indexed _dataStore);
    
    constructor() Pausable() public {}

    /**
        @notice Check in the current data store if the _auditor address has ever been added
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @dev The check is for the record ever being added and not whether the _auditor address is currently a valid auditor
        @return Boolean value indicating if this address has ever been added as an auditor
    */
    function hasAuditorRecord(address _auditor) external view returns (bool) {
        return _hasAuditorRecord(_auditor);
    }

    /**
        @notice Check if the _auditor address is currently a valid auditor in this data store
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @dev This will return false in both occasions where an auditor is suspended or has never been added to this store
        @return Boolean value indicating if this address is currently a valid auditor
    */
    function isAuditor(address _auditor) external view returns (bool) {
        // Ambigious private call, call with caution or use with hasAuditorRecord()
        return _isAuditor(_auditor);
    }

    /**
        @notice Check the details on the _auditor in this current data store
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @dev Looping is a future problem therefore tell them the length and they can use the index to fetch the contract
        @return The current state of the auditor and the total number of approved contracts and the total number of opposed contracts
    */
    function auditorDetails(address _auditor) external view returns (bool, uint256, uint256) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");

        return 
        (
            auditors[_auditor].isAuditor, 
            auditors[_auditor].approvedContracts.length, 
            auditors[_auditor].opposedContracts.length
        );
    }

    /**
        @notice Check the approved contract information for an auditor
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @param _index A number which should be less than or equal to the total number of approved contracts for the _auditor
        @return The audited contract information
    */
    function auditorApprovedContract(address _auditor, uint256 _index) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].approvedContracts.length, "Approved list is empty");
        require(_index <= auditors[_auditor].approvedContracts.length, "Record does not exist");

        // Indexing from the number 0 therefore decrement if you must
        if (_index != 0) {
            _index = _index.sub(1);
        }

        uint256 _contractIndex = auditors[_auditor].approvedContracts[_index];

        return _contractDetails(_contractIndex);
    }

    /**
        @notice Check the opposed contract information for an auditor
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @param _index A number which should be less than or equal to the total number of opposed contracts for the _auditor
        @return The audited contract information
    */
    function auditorOpposedContract(address _auditor, uint256 _index) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].opposedContracts.length, "Opposed list is empty");
        require(_index <= auditors[_auditor].opposedContracts.length, "Record does not exist");

        // Indexing from the number 0 therefore decrement if you must
        if (_index != 0) {
            _index = _index.sub(1);
        }

        uint256 _contractIndex = auditors[_auditor].opposedContracts[_index];

        return _contractDetails(_contractIndex);
    }

    /**
        @notice Check in the current data store if the _contractHash address has been added
        @param _contractHash The address, intented to be a contract
        @dev There are two hash values, contract creation transaction and the actual contract hash, this is the contract hash
        @return Boolean value indicating if this address has been addede to the store
    */
    function hasContractRecord(address _contractHash) external view returns (bool) {
        return _hasContractRecord(_contractHash);
    }

    /**
        @notice Check in the current data store if the _creationHash address has been added
        @param _creationHash The address, intented to be a contract
        @dev There are two hash values, contract creation transaction and the actual contract hash, this is the creation hash
        @return Boolean value indicating if this address has been addede to the store
    */
    function hasContractCreationRecord(string memory _creationHash) external view returns (bool) {
        return _hasCreationRecord(_creationHash);
    }

    /**
        @notice Check the contract details using the _contractHash
        @param _contractHash The hash used to search for the contract
        @return The data stored regarding the contract audit
    */
    function contractDetails(address _contractHash) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasContractRecord(_contractHash), "No contract record in the current store");

        uint256 _contractIndex = contractHash[_contractHash];

        return _contractDetails(_contractIndex);
    }

    /**
        @notice Check the contract details using the _creationHash
        @param _creationHash The hash depicting the transaction which created the contract
        @return The data stored regarding the contract audit
    */
    function contractCreationDetails(address _creationHash) external view returns (address, address, address, bool, bool, string memory) {
        require(_hasCreationRecord(_creationHash), "No contract record in the current store");

        uint256 _contractIndex = contractCreationHash[_contractHash];

        return _contractDetails(_contractIndex);
    }

    /**
        @notice Check in the current data store if the _deployer address has ever been added
        @param _deployer The address, intented to be a wallet (but may be a contract), which represents a deployer
        @return Boolean value indicating if this address has been added to the current store
    */
    function hasDeployerRecord(address _deployer) external view returns (bool) {
        return _hasDeployerRecord(_deployer);
    }

    /**
        @notice Check the details on the _deployer in this current data store
        @param _deployer The address, intented to be a wallet (but may be a contract), which represents a deployer
        @dev Looping is a future problem therefore tell them the length and they can use the index to fetch the contract
        @return The number of approved contracts and the total number of opposed contracts
    */
    function deployerDetails(address _deployer) external view returns (uint256, uint256) {
        require(_hasDeployerRecord(_deployer), "No deployer record in the current store");

        return 
        (
            deployers[_deployer].approvedContracts.length, 
            deployers[_deployer].opposedContracts.length
        );
    }

    /**
        @notice Add an auditor to the data store
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @dev Used to add a new address therefore should be used once per address. Intented as the initial save
    */
    function addAuditor(address _auditor) external onlyOwner() whenNotPaused() {
        require(activeStore, "Store has been deactivated");
        require(!_hasAuditorRecord(_auditor), "Auditor record already exists");

        auditors[_auditor].isAuditor = true;
        auditors[_auditor].auditor = _auditor;
        
        // Nice-to-have statistics
        activeAuditorCount = activeAuditorCount.add(1);

        // Which platform initiated the call on the _auditor
        emit AddedAuditor(_msgSender(), _auditor);
    }

    /**
        @notice Revoke permissions from the auditor
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @dev After an auditor has been added one may decide that they are no longer fit and thus deactivate their audit writing permissions.
        Note that we are disabling them in the current store which prevents actions in the future stores therefore we never go back and change
        previous stores on the auditor
    */
    function suspendAuditor(address _auditor) external onlyOwner() {
        require(activeStore, "Store has been deactivated");

        if (_hasAuditorRecord(_auditor)) {
            if (!_isAuditor(_auditor)) {
                revert("Auditor has already been suspended");
            }
            // Nice-to-have statistics
            activeAuditorCount = activeAuditorCount.sub(1);
        } else {
            // If the previous store has been disabled when they were an auditor then write them into the (new) current store and disable
            // their permissions for writing into this store and onwards. They should not be able to write back into the previous store anyway
            auditors[_auditor].auditor = _auditor;
        }

        auditors[_auditor].isAuditor = false;
        
        // Nice-to-have statistics
        suspendedAuditorCount = suspendedAuditorCount.add(1);

        // Which platform initiated the call on the _auditor
        emit SuspendedAuditor(_msgSender(), _auditor);
    }

    /**
        @notice Reinstate the permissions for the auditor that is currently suspended
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @dev Similar to the addition of the auditor but instead flip the isAuditor boolean back to true
    */
    function reinstateAuditor(address _auditor) external onlyOwner() whenNotPaused() {
        require(activeStore, "Store has been deactivated");

        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(!_isAuditor(_auditor), "Auditor already has active status");

        auditors[_auditor].isAuditor = true;
        
        // Nice-to-have statistics
        activeAuditorCount = activeAuditorCount.add(1);
        suspendedAuditorCount = suspendedAuditorCount.sub(1);

        // Which platform initiated the call on the _auditor
        emit ReinstatedAuditor(_msgSender(), _auditor);
    }

    /**
        @notice Write a new completed audit into the data store
        @param _auditor The address, intented to be a wallet, which represents an auditor
        @param _deployer The address, intented to be a wallet (but may be a contract), which represents a deployer
        @param _contract The hash used to search for the contract
        @param _approved Boolean indicating whether the contract has passed or failed the audit
        @param _txHash The hash depicting the transaction which created the contract
    */
    function completeAudit(address _auditor, address _deployer, address _contract, bool _approved, bytes calldata _txHash) external onlyOwner() whenNotPaused() {
        require(activeStore, "Store has been deactivated");

        // Must be a valid auditor in the current store to be able to write to the current store
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(_isAuditor(_auditor), "Auditor has been suspended");

        // The contract should only be added once therefore if the index is 0 then it has not been added as the value lookup defaults to 0
        require(contractHash[_contract] == 0, "Contract exists in the contracts mapping");

        string memory _hash = string(_txHash);

        // Similar to the check above but for the transaction hash. Check both to prevent unintended consequences (if deployer and auditor collude
        // then this creation hash may be anything)
        require(contractCreationHash[_hash] == 0, "Contract exists in the contract creation hash mapping");

        // Create a single struct for the contract data and then reference it via indexing instead of changing multiple locations
        // TODO: can I omit the destructed argument since the default bool is false?
        Contract _contractData = Contract({
            auditor:        _auditor,
            contractHash:   _contract,
            deployer:       _deployer,
            approved:       _approved, 
            destructed:     false,
            creationHash:   _hash
        });

        // Start adding from the next position and thus have an empty 0th default value which indicates an error to the user
        contracts[contracts.length++] = _contractData;
        uint256 _contractIndex = contracts.length;

        // If this is a new deployer address then write them into the store
        if (!_hasDeployerRecord(_deployer)) {
            deployers[_deployer].deployer = _deployer;
        }

        if (_approved) {
            // Add the index of the contract, indicating the current position of this audit, to the arrays
            auditors[_auditor].approvedContracts.push(_contractIndex);
            deployers[_deployer].approvedContracts.push(_contractIndex);

            // Nice-to-have statistics
            approvedContractCount = approvedContractCount.add(1);
        } else {
            // Add the index of the contract, indicating the current position of this audit, to the arrays
            auditors[_auditor].opposedContracts.push(_contractIndex);
            deployers[_deployer].opposedContracts.push(_contractIndex);
            
            // Nice-to-have statistics
            opposedContractCount = opposedContractCount.add(1);
        }

        // Add to mapping for easy lookup, note that 0th index will also be default which allows us to do some safety checks
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

    function contractDestructed(address _contract, address _initiator) external onlyOwner() {
        require(_hasContractRecord(_contract), "No contract record in the current store");

        uint256 _contractIndex = contractHash[_contractHash];

        require(contracts[_contractIndex].auditor == _initiator || contracts[_contractIndex].deployer == _initiator, "Action restricted to contract Auditor or Deployer");
        require(!contracts[_contractIndex].destructed, "Contract already marked as destructed");

        contracts[_contractIndex].destructed = true;

        emit ContractDestructed(_contract, _initiator);
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
        return contractCreationHash[_creationHash] != 0;
    }

    function isAuditorRecursiveSearch(address _auditor) external view returns (bool) {
        // Check in all previous stores if the latest record of them being an auditor is set to true/false
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveAuditorSearch(_auditor);
    }

    function contractDetailsRecursiveSearch(string memory _contract) external view returns (address, address, address, bool, bool, string memory) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveContractDetailsSearch(_contract, true);
    }

    function contractCreationDetailsRecursiveSearch(string memory _contract) external view returns (address, address, address, bool, bool, string memory) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        return _recursiveContractDetailsSearch(_contract, false);
    }

    function _recursiveContractDetailsSearch(string memory _contract, bool _contractHash) private view returns (address, address, address, bool, bool, string memory) {
        address _auditor;
        address _contractHash;
        address _deployer;
        bool    _approved;
        bool    _destructed;
        string  _creationHash;

        if (_contractHash) {
            if (_hasContractRecord(_contract)) {
                uint256 _contractIndex = contractHash[_contract];

                _auditor      = contracts[_contractIndex].auditor;
                _contractHash = contracts[_contractIndex].contractHash;
                _deployer     = contracts[_contractIndex].deployer;
                _approved     = contracts[_contractIndex].approved;
                _destructed   = contracts[_contractIndex].destructed;
                _hash         = contracts[_contractIndex].creationHash;
            } else if (previousDatastore != address(0)) {
                (_auditor, _contractHash, _deployer, _approved, _destructed, _hash) = _contractLookup("contractDetailsRecursiveSearch");
            } else {
                revert("No contract record in any data store");
            }
        } else {
            if (_hasCreationRecord(_contract)) {
                uint256 _contractIndex = contractCreationHash[_contract];

                _auditor      = contracts[_contractIndex].auditor;
                _contractHash = contracts[_contractIndex].contractHash;
                _deployer     = contracts[_contractIndex].deployer;
                _approved     = contracts[_contractIndex].approved;
                _destructed   = contracts[_contractIndex].destructed;
                _hash         = contracts[_contractIndex].creationHash;
            } else if (previousDatastore != address(0)) {
                (_auditor, _contractHash, _deployer, _approved, _destructed, _hash) = _contractLookup("contractCreationDetailsRecursiveSearch");
            } else {
                revert("No contract record in any data store");
            }
        }

        return (_auditor, _contractHash, _deployer, _approved, _destructed, _hash);
    }

    function _contractLookup(string memory _function) private view returns returns (address, address, address, bool, bool, string memory) {
        string memory _signature = string(abi.encodePacked(_function, "(string)")
        (bool success, bytes memory data) = previousDatastore.staticcall(abi.encodeWithSignature(_signature, _contract));

        require(success, string(abi.encodePacked("Unknown error when recursing in datastore version: ", version)));
        
        (_auditor, _contractHash, _deployer, _approved, _destructed, _hash) = abi.decode(data, (address, address, address, bool, bool, string));
        return (_auditor, _contractHash, _deployer, _approved, _destructed, _hash);
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

    function linkDataStore(address _dataStore) external onlyOwner() {
        require(activeStore, "Store has been deactivated");
        
        activeStore = false;
        previousDatastore = _dataStore;

        emit LinkedDataStore(_msgSender(), previousDatastore);
    }
}
