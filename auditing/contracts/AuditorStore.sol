// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract AuditorStore {
    
    using SafeMath for uint256;

    /**
     *  @param activeAuditorCount Represents the number of currently valid auditors who can write into the store
     */
    uint256 public activeAuditorCount;

    /**
     *  @param activeAuditorCount Represents the number of currently invalid auditors who have their write permissions suspended
     */
    uint256 public suspendedAuditorCount;

    /**
     *  @param auditor The address of the auditor used as a check for whether the auditor exists
     *  @param isAuditor Indicator of whether the auditor currently has write permissions
     *  @param approvedContracts Contains indexes of the contracts that the auditor has approved
     *  @param opposedContracts Contains indexes of the contracts that the auditor has opposed
     */
    struct Auditor {
        address    auditor;
        bool       isAuditor;
        uint256[]  approvedContracts;
        uint256[]  opposedContracts;
    }

    /**
     *  @notice Store data related to the auditors
     */
    mapping(address => Auditor) public auditors;

    /**
     *  @notice Add an auditor into the current data store for the first time
     *  @param _owner The platform that added the auditor
     *  @param _auditor The auditor who has been added
     */
    event AddedAuditor(address indexed _owner, address indexed _auditor);

    /**
     *  @notice Prevent the auditor from adding new records by suspending their access
     *  @param _owner The platform that suspended the auditor
     *  @param _auditor The auditor who has been suspended
     */
    event SuspendedAuditor(address indexed _owner, address indexed _auditor);
    
    /**
     *  @notice Allow the auditor to continue acting as a valid auditor which can add new records
     *  @param _owner The platform that reinstated the auditor
     *  @param _auditor The auditor who has been reinstated
     */
    event ReinstatedAuditor(address indexed _owner, address indexed _auditor);

    /**
     *  @notice If the auditor is currently a valid auditor then they can be migrated into the newer store
     *  @param _migrator Who attempted the migration (pre-access control it is the auditor themselves)
     *  @param _auditor The auditor who is being migrated
     */
    event AcceptedMigration(address indexed _migrator, address indexed _auditor);

    constructor() internal {}

    function _addAuditor(address _auditor) internal {
        require(!_hasAuditorRecord(_auditor), "Auditor record already exists");

        auditors[_auditor].isAuditor = true;
        auditors[_auditor].auditor = _auditor;

        activeAuditorCount = activeAuditorCount.add(1);

        // Which platform initiated the call on the _auditor
        // Since this is an internal call will the caller change to the data store?
        emit AddedAuditor(_msgSender(), _auditor);
    }

    function _suspendAuditor(address _auditor) internal {
        if (_hasAuditorRecord(_auditor)) {
            if (!_isAuditor(_auditor)) {
                revert("Auditor has already been suspended");
            }
            activeAuditorCount = activeAuditorCount.sub(1);
        } else {
            // If the previous store has been disabled when they were an auditor then write them into the (new) current store and disable
            // their permissions for writing into this store and onwards. They should not be able to write back into the previous store anyway
            auditors[_auditor].auditor = _auditor;
        }

        auditors[_auditor].isAuditor = false;        
        suspendedAuditorCount = suspendedAuditorCount.add(1);

        // Which platform initiated the call on the _auditor
        // Since this is an internal call will the caller change to the data store?
        emit SuspendedAuditor(_msgSender(), _auditor);
    }

    function _reinstateAuditor(address _auditor) internal {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(!_isAuditor(_auditor), "Auditor already has active status");

        auditors[_auditor].isAuditor = true;
        
        activeAuditorCount = activeAuditorCount.add(1);
        suspendedAuditorCount = suspendedAuditorCount.sub(1);

        // Which platform initiated the call on the _auditor
        // Since this is an internal call will the caller change to the data store?
        emit ReinstatedAuditor(_msgSender(), _auditor);
    }

    function _hasAuditorRecord(address _auditor) internal view returns (bool) {
        return auditors[_auditor].auditor != address(0);
    }

    /**
     *  @dev Returns false in both cases where an auditor has not been added into this datastore or if they have been added but suspended
     */
    function _isAuditor(address _auditor) internal view returns (bool) {
        return auditors[_auditor].isAuditor;
    }

    function _auditorDetails(address _auditor) internal view returns (bool, uint256, uint256) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");

        return 
        (
            auditors[_auditor].isAuditor, 
            auditors[_auditor].approvedContracts.length, 
            auditors[_auditor].opposedContracts.length
        );
    }

    function _auditorApprovedContract(address _auditor, uint256 _index) internal view returns (uint256) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].approvedContracts.length, "Approved list is empty");
        require(_index <= auditors[_auditor].approvedContracts.length, "Record does not exist");

        // Indexing from the number 0 therefore decrement if you must
        if (_index != 0) {
            _index = _index.sub(1);
        }

        return auditors[_auditor].approvedContracts[_index];
    }

    function _auditorOpposedContract(address _auditor, uint256 _index) internal view returns (uint256) {
        require(_hasAuditorRecord(_auditor), "No auditor record in the current store");
        require(0 < auditors[_auditor].opposedContracts.length, "Opposed list is empty");
        require(_index <= auditors[_auditor].opposedContracts.length, "Record does not exist");

        // Indexing from the number 0 therefore decrement if you must
        if (_index != 0) {
            _index = _index.sub(1);
        }

        return auditors[_auditor].opposedContracts[_index];
    }

    function _migrate(address _migrator, address _auditor) internal {
        // Auditor should not exist to mitigate event spamming or possible neglectful changes to 
        // _recursiveAuditorSearch(address) which may allow them to switch their suspended status to active
        require(!_hasAuditorRecord(_auditor), "Already in data store");
        
        bool isAnAuditor = _recursiveAuditorSearch(_auditor);

        if (isAnAuditor) {
            // Do not rewrite previous audits into each new datastore as that will eventually become too expensive
            auditors[_auditor].isAuditor = true;
            auditors[_auditor].auditor = _auditor;

            activeAuditorCount = activeAuditorCount.add(1);

            emit AcceptedMigration(_migrator, _auditor);
        } else {
            revert("Auditor is either suspended or has never been in the system");
        }
    }

    function _saveContractIndexForAuditor(bool _approved, uint256 _index) internal {
        if (_approved) {
            auditors[_auditor].approvedContracts.push(_index);
        } else {
            auditors[_auditor].opposedContracts.push(_index);
        }
    }

    function _recursiveIsAuditorSearch(address _auditor, address _previousDatastore) private view returns (bool) {
        bool isAnAuditor = false;

        if (_hasAuditorRecord(_auditor)) {
            if (_isAuditor(_auditor)) {
                isAnAuditor = true;
            }
        } else if (_previousDatastore != address(0)) {
            (bool success, bytes memory data) = _previousDatastore.staticcall(abi.encodeWithSignature("searchAllStoresForIsAuditor(address)", _auditor));
            require(success, "Unknown error when recursing in datastore");
            isAnAuditor = abi.decode(data, (bool));
        } else {
            revert("No auditor record in any data store");
        }

        return isAnAuditor;
    }

}
