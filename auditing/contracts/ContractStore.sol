// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract ContractStore {
    
    using SafeMath for uint256;

    uint256 public approvedContractCount;
    uint256 public opposedContractCount;

    Contract[] internal contracts;

    struct Contract {
        address auditor;
        address contractHash;
        address deployer;
        bool    approved;
        bool    destructed;
        string  creationHash;
    }

    // Note for later, 0th index is used to check if it already exists
    mapping(address => uint256) internal contractHash;
    mapping(string => uint256)  internal contractCreationHash;

    // Completed audits
    event NewRecord(address indexed _auditor, address indexed _deployer, address _contract, string _hash, bool indexed _approved, uint256 _contractIndex);
    event ContractDestructed(address indexed _sender, address _contract);

    constructor() internal {}

    function _contractDestructed(address _contract, address _initiator) internal {
        uint256 _index = _contractIndex(_contract);

        require(contracts[_index].auditor == _initiator || contracts[_index].deployer == _initiator, "Action restricted to contract Auditor or Deployer");
        require(!contracts[_index].destructed, "Contract already marked as destructed");

        contracts[_index].destructed = true;

        emit ContractDestructed(_contract, _initiator);
    }

    function _hasContractRecord(address _contractHash) internal view returns (bool) {
        return contractHash[_contractHash] != 0;
    }

    function _hasCreationRecord(address _creationHash) internal view returns (bool) {
        return contractCreationHash[_creationHash] != 0;
    }

    function _contractDetailsRecursiveSearch(address _contract, address _previousDataStore) internal view returns (address, address, address, bool, bool, string memory) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually
        address _auditor;
        address _contractHash;
        address _deployer;
        bool    _approved;
        bool    _destructed;
        string  _creationHash;

        uint256 _index;

        if (_hasContractRecord(_contract)) {
            _index = contractHash[_contract];
        } else if (_hasCreationRecord(_contract)) {
            _index = contractCreationHash[_contract];
        }

        if (_index != 0) {
            _auditor      = contracts[_index].auditor;
            _contractHash = contracts[_index].contractHash;
            _deployer     = contracts[_index].deployer;
            _approved     = contracts[_index].approved;
            _destructed   = contracts[_index].destructed;
            _hash         = contracts[_index].creationHash;
        } else if (previousDatastore != address(0)) {
            (bool success, bytes memory data) = previousDatastore.staticcall(abi.encodeWithSignature("searchAllStoresForContractDetails(address)", _contract));
            require(success, "Unknown error when recursing in datastore");
            (_auditor, _contractHash, _deployer, _approved, _destructed, _creationHash) = abi.decode(data, (address, address, address, bool, bool, string));
        } else {
            revert("No contract record in any data store");
        }

        return (_auditor, _contractHash, _deployer, _approved, _destructed, _creationHash);
    }

    function _contractDetails(address _contract) internal view returns (address, address, address, bool, bool, string memory) {
        require(0 < contracts.length, "No contracts have been added");
        uint256 _index = _contractIndex(_contract);
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

    function _contractIndex(address _contract) private view returns (uint256 _index) {
        uint256 _index = contractHash[_contract];

        if (_index == 0) {
            // TODO: Convert address to string since mapping is string
            _index = contractCreationHash[_contractHash];
        }

        require(_index != 0, "Contract has not been added");
    }

}
