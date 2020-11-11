// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";

// TODO: Ban list for deploying addresses? Address list linking one address to others since you can easily create a new wallet
contract DeployerStore {
    
    using SafeMath for uint256;

    /**
     *  @param activeDeployerCount Represents the number of currently valid deployers
     */
    uint256 public activeDeployerCount;

    /**
     *  @param blacklistedDeployerCount Represents the number of invalid deployers who have been banned
     */
    uint256 public blacklistedDeployerCount;

    /**
     *  @param deployer The address of the deployer used as a check for whether the deployer exists
     *  @param blacklisted Indicator of whether the deployer has been banned
     *  @param approvedContracts Contains indexes of the contracts that the deployer has had approved
     *  @param opposedContracts Contains indexes of the contracts that the deployer has had opposed
     */
    struct Deployer {
        address    deployer;
        bool       blacklisted;
        uint256[]  approvedContracts;
        uint256[]  opposedContracts;
    }

    /**
     *  @notice Store data related to the deployers
     */
    mapping(address => Deployer) public deployers;

    /**
     *  @notice Add a deployer into the current data store for the first time
     *  @param _owner The platform that added the deployer
     *  @param _deployer The deployer who has been added
     */
    event AddedDeployer(address indexed _owner, address indexed _deployer);

    /**
     *  @notice Prevent the deployer from adding new contracts by suspending their access
     *  @param _owner The platform that suspended the deployer
     *  @param _deployer The deployer who has been suspended
     */
    event SuspendedDeployer(address indexed _owner, address indexed _deployer);
    
    /**
     *  @notice Allow the deployer to continue acting as a valid deployer which can have their contracts added
     *  @param _owner The platform that reinstated the deployer
     *  @param _deployer The deployer who has been reinstated
     */
    event ReinstatedDeployer(address indexed _owner, address indexed _deployer);

    constructor() internal {}

    function _addDeployer(address _deployer) internal {
        // If this is a new deployer address then write them into the store
        if (!_hasDeployerRecord(_deployer)) {
            deployers[_deployer].deployer = _deployer;

            activeDeployerCount = activeDeployerCount.add(1);

            // Which platform initiated the call on the _deployer
            // Since this is an internal call will the caller change to the data store?
            emit AddedDeployer(_msgSender(), _deployer);
        }
    }

    function _suspendDeployer(address _deployer) internal {
        if (_hasDeployerRecord(_deployer)) {
            if (!_isBlacklisted(_deployer)) {
                revert("Deployer has already been blacklisted");
            }
            activeDeployerCount = activeDeployerCount.sub(1);
        } else {
            // If the previous store has been disabled when they were an auditor then write them into the (new) current store and disable
            // their permissions for writing into this store and onwards. They should not be able to write back into the previous store anyway
            deployers[_deployer].deployer = _deployer;
        }

        deployers[_deployer].blacklisted = true;
        blacklistedDeployerCount = blacklistedDeployerCount.add(1);

        // Which platform initiated the call on the _deployer
        // Since this is an internal call will the caller change to the data store?
        emit SuspendedDeployer(_msgSender(), _deployer);
    }

    function _reinstateDeployer(address _deployer) internal {
        require(_hasDeployerRecord(_deployer), "No deployer record in the current store");
        require(!_isBlacklisted(_deployer), "Deployer already has active status");

        deployers[_deployer].blacklisted = false;
        
        activeDeployerCount = activeDeployerCount.add(1);
        blacklistedDeployerCount = blacklistedDeployerCount.sub(1);

        // Which platform initiated the call on the _deployer
        // Since this is an internal call will the caller change to the data store?
        emit ReinstatedDeployer(_msgSender(), _deployer);
    }

    function _hasDeployerRecord(address _deployer) private view returns (bool) {
        return deployers[_deployer].deployer != address(0);
    }

    /**
     *  @dev Returns false in both cases where an deployer has not been added into this datastore or if they have been added but blacklisted
     */
    function _isBlacklisted(address _deployer) internal view returns (bool) {
        return deployers[_deployer].blacklisted;
    }

    function _deployerDetails(address _deployer) internal view returns (bool, uint256, uint256) {
        require(_hasDeployerRecord(_deployer), "No deployer record in the current store");

        return 
        (
            deployers[_deployer].blacklisted, 
            deployers[_deployer].approvedContracts.length, 
            deployers[_deployer].opposedContracts.length
        );
    }

    function _deployerApprovedContract(address _deployer, uint256 _index) internal view returns (uint256) {
        require(_hasDeployerRecord(_deployer), "No deployer record in the current store");
        require(0 < deployers[_deployer].approvedContracts.length, "Approved list is empty");
        require(_index <= deployers[_deployer].approvedContracts.length, "Record does not exist");

        // Indexing from the number 0 therefore decrement if you must
        if (_index != 0) {
            _index = _index.sub(1);
        }

        return deployers[_deployer].approvedContracts[_index];
    }

    function _deployerOpposedContract(address _auditor, uint256 _index) external view returns (uint256) {
        require(_hasDeployerRecord(_deployer), "No deployer record in the current store");
        require(0 < deployers[_deployer].opposedContracts.length, "Opposed list is empty");
        require(_index <= deployers[_deployer].opposedContracts.length, "Record does not exist");

        // Indexing from the number 0 therefore decrement if you must
        if (_index != 0) {
            _index = _index.sub(1);
        }

        return deployers[_deployer].opposedContracts[_index];
    }

    function _saveContractIndexForDeplyer(bool _approved, uint256 _index) internal {
        if (_approved) {
            deployers[_deployer].approvedContracts.push(_index);
        } else {
            deployers[_deployer].opposedContracts.push(_index);
        }
    }
}
