// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract ContractStore {
    
    using SafeMath for uint256;

    uint256 public approvedContractCount;
    uint256 public opposedContractCount;

    Contract[] private contracts;

    struct Contract {
        address auditor;
        address deployer;
        address contractHash;
        address creationHash;
        bool    approved;
        bool    destructed;
    }

    // Note for later, 0th index is used to check if it already exists
    mapping(address => uint256) private contractHash;
    mapping(address => uint256) private contractCreationHash;

    // Completed audits
    event NewContractRecord(
        address indexed _auditor, 
        address indexed _deployer, 
        address         _contract, 
        address         _hash, 
        bool    indexed _approved, 
        uint256         _contractIndex
    );

    event ContractDestructed(address indexed _sender, address _contract);

    constructor() internal {}

    function _saveContract(address _auditor, address _deployer, address _contract, address _hash, bool _approved) internal returns (uint256) {
        require(!_hasContractRecord(_contract), "Contract exists in the contracts mapping");
        require(!_hasCreationRecord(_hash), "Contract exists in the contract creation hash mapping");

        // Create a single struct for the contract data and then reference it via indexing instead of managing mulitple storage locations
        // TODO: can I omit the destructed argument since the default bool is false?        
        Contract _contractData = Contract({
            auditor:        _auditor,
            deployer:       _deployer,
            contractHash:   _contract,
            creationHash:   _hash
            approved:       _approved, 
            destructed:     false,
        });

        if (_approved) {
            approvedContractCount = approvedContractCount.add(1);
        } else {
            opposedContractCount = opposedContractCount.add(1);
        }

        // Start adding from the next position and thus have an empty 0th default value which indicates an error to the user
        contracts[contracts.length++] = _contractData;
        uint256 _contractIndex = contracts.length;

        // Add to mapping for easy lookup, note that 0th index will also be default which allows us to do some safety checks
        contractHash[_contract] = _contractIndex;
        contractCreationHash[_hash] = _contractIndex;

        emit NewContractRecord(_auditor, _deployer, _contract, _hash, _approved, _contractIndex);
        return _contractIndex;
    }

    function _contractDestructed(address _contract, address _initiator) internal {
        uint256 _index = _contractIndex(_contract);

        require(contracts[_index].auditor == _initiator || contracts[_index].deployer == _initiator, "Action restricted to contract Auditor or Deployer");
        require(!contracts[_index].destructed, "Contract already marked as destructed");

        contracts[_index].destructed = true;

        emit ContractDestructed(_initiator, _contract);
    }

    function _hasContractRecord(address _contractHash) internal view returns (bool) {
        return contractHash[_contractHash] != 0;
    }

    function _hasCreationRecord(address _creationHash) internal view returns (bool) {
        return contractCreationHash[_creationHash] != 0;
    }

    function _contractDetailsRecursiveSearch(address _contract, address _previousDataStore) internal view returns 
    (
        address _auditor,
        address _deployer, 
        address _contractHash,
        address _creationHash  
        bool    _approved, 
        bool    _destructed, 
    ) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        address _auditor;
        address _deployer;
        address _contractHash;
        address _creationHash;
        bool    _approved;
        bool    _destructed;

        uint256 _index;

        if (_hasContractRecord(_contract)) {
            _index = contractHash[_contract];
        } else if (_hasCreationRecord(_contract)) {
            _index = contractCreationHash[_contract];
        }

        if (_index != 0) {
            _auditor      = contracts[_index].auditor;
            _deployer     = contracts[_index].deployer;
            _contractHash = contracts[_index].contractHash;
            _creationHash = contracts[_index].creationHash;
            _approved     = contracts[_index].approved;
            _destructed   = contracts[_index].destructed;
        } else if (_previousDatastore != address(0)) {
            (bool success, bytes memory data) = _previousDatastore.staticcall(abi.encodeWithSignature("searchAllStoresForContractDetails(address)", _contract));
            require(success, "Unknown error when recursing in datastore");
            (_auditor, _deployer, _contractHash, _creationHash, _approved, _destructed) = abi.decode(data, (address, address, address, address, bool, bool));
        } else {
            revert("No contract record in any data store");
        }
    }

    function _contractDetails(address _contract) internal view returns (address, address, address, address, bool, bool) {
        require(0 < contracts.length, "No contracts have been added");
        uint256 _index = _contractIndex(_contract);
        require(_index <= contracts.length, "Record does not exist");

        return 
        (
            contracts[_index].auditor,
            contracts[_index].deployer,
            contracts[_index].contractHash,
            contracts[_index].creationHash
            contracts[_index].approved,
            contracts[_index].destructed,
        );
    }

    function _contractIndex(address _contract) private view returns (uint256 _index) {
        uint256 _index = contractHash[_contract];

        if (_index == 0) {
            _index = contractCreationHash[_contractHash];
        }

        require(_index != 0, "Contract has not been added");
    }

}
