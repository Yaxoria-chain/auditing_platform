// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.4;

import "./Ownable.sol";
import "./IAuditingPlatform.sol";

/**
 *  TODO: If we are also storing the current owner in the data store then we allow for more flexibility towards the deployer / devs
 *        In the interface call for completeAudit we may allow an additional parameter to indicate the owner (and deployer)
 *        Alternatively, create a function in Auditable to register the contract first and then only pass in the current owner
 *        (Need to make sure that destruct() works as intended because we do not want "pending" contracts that are registered but actually nuked)
 *        Furthermore, current owner helps with passing in the initiator of the destruct() call
 *        That requires a function that informs the store of the change of owner (by us)
 */

abstract contract Auditable is Ownable {

    /**
     *  @notice the address of the auditor who is auditing the contract that inherits from this contract
     */
    address public auditor;

    /**
     *  @notice the destination which the status of the audit is transmitted to
     */
    address public platform;

    /**
     *
     */
    address payable public immutable deployer;

    /**
     *  @notice Indicates whether the audit has been completed or is in progress
     *  @dev Audit is completed when the bool is set to true otherwise the default is false (in progress)
     */
    bool public audited;
    
    /**
     *  @notice Indicates whether the audit has been approved or opposed
     *  @dev Consider this bool only after "audited" is true. Approved is true and Opposed (default) if false
     */
    bool public approved;

    /**
     *  @notice Modifier used to block or allow method functionality based on the approval / opposition of the audit
     *  @dev Use this on every function
     */
    modifier isApproved() {
        require( approved, "Functionality blocked until contract is approved" );
        _;
    }

    /**
     *  @notice Event tracking who set the auditor and who the auditor is
     *  @dev Index the sender and the auditor for easier searching
     */
    event SetAuditor( address indexed sender, address indexed auditor );
    
    /**
     *  @notice Event tracking who set the platform and which platform was set
     *  @dev Index the sender and the platform for easier searching
     */
    event SetPlatform( address indexed sender, address indexed platform );
    
    /**
     *  @notice Event tracking the status of the audit and who the auditor is
     */
    event ApprovedAudit( address auditor );

    /**
     *  @notice Event tracking the status of the audit and who the auditor is
     */
    event OpposedAudit( address auditor );
    
    /**
     *  @notice A contract has a transaction which is the contract creation.
     *  @dev The contract creation hash allows one to view the bytecode of the contract even after it has self destructed
     */
    event CreationHashSet( address hash );

    /**
     *  @notice 
     *  @param _auditor an address of a person who may or may not actually be an auditor
     *  @param _platform an address of a contract which may or may not be a valid platform
     */
    constructor( address _auditor, address _platform ) Ownable() {
        deployer = _owner;
        auditor = _auditor;
        platform = _platform;

        emit SetAuditor( _owner, auditor );
        emit SetPlatform( _owner, platform );
    }

    /**
     *  @notice Used to change the auditor by either the owner prior to the completion of the audit
     *  @param _auditor an address indicating who the new auditor will be
     */
    function setAuditor( address _auditor ) external {
        require( _msgSender() == _owner, "Owner only" );

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require( !audited, "Cannot change auditor post audit" );

        auditor = _auditor;

        emit SetAuditor( _msgSender(), auditor );
    }

    /**
     *  @notice Used to change the platform by either the owner prior to the completion of the audit
     *  @param _platform an address indicating a contract which will be the new platform
     */
    function setPlatform( address _platform ) external {
        require( _msgSender() == _owner, "Owner only" );

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require( !audited, "Cannot change platform post audit" );

        platform = _platform;

        emit SetPlatform( _msgSender(), platform );
    }

    function register() external {
        require( !audited, "Contract has already been audited" );

        IAuditingPlatform( platform ).register( deployer );
    }

    /**
     *  @notice Auditor is in favor of the contract therefore they approve it
     */
    function approveAudit() external {
        require( _msgSender() == auditor, "Auditor only" );

        // Auditor cannot change their mind and approve/oppose multiple times
        require( !audited, "Contract has already been audited" );

        // Switch to true to complete audit and approve
        audited = true;
        approved = true;

        emit ApprovedAudit( _msgSender() );
    }

    /**
     *  @notice Auditor is against the contract therefore they oppose it
     */
    function opposeAudit() external {
        require( _msgSender() == auditor, "Auditor only" );
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require( !audited, "Cannot oppose an audited contract" );

        // Switch to true to complete the audit and explicitly set approved to false (default is false)
        audited = true;
        approved = false;

        emit OpposedAudit( _msgSender() );
    }



    // TODO: remove and move to the platform    
    function register() external {
        require( confirmedCreationHash, "Hash has not been confirmed to be identical" );
        require( !audited,              "Contract has already been audited" );

        IAuditingPlatform( platform ).register( deployer, auditor, contractCreationHash );
    }

    // TODO: remove and move to the platform as part of registration
    function approveCreationHash( address creationHash ) external {
        // TODO: Flaw, any "auditor" may collude here and set the incorrect hash to register something else
        require( _msgSender() == auditor,               "Auditor only" );
        require( contractCreationHash != address( 0 ),  "Hash has not been set" );
        require( _creationHash == contractCreationHash, "Hashes do not match" );

        confirmedCreationHash = true;
    }

    // TODO: remove and make simpler, move to platform
    function approveAudit( address _creationHash ) external {
        address initiator = _msgSender();
        require( initiator == auditor, "Auditor only" );
        require( confirmedCreationHash, "Hash has not been confirmed to be identical" );
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require( !audited, "Contract has already been audited" );

        // Switch to true to complete audit and approve
        audited = true;
        approved = true;

        // TODO: think about the owner being sent and transfer of ownership and how that affects the store
        IAuditingPlatform( platform ).completeAudit( initiator, deployer, address( this ), _creationHash, approved );

        emit ApprovedAudit( initiator );
    }

    // TODO: remove and make simpler, move to platform
    function opposeAudit( address _creationHash ) external {
        address initiator = _msgSender();
        require( initiator == auditor, "Auditor only" );
        require( confirmedCreationHash, "Hash has not been confirmed to be identical" );
        
        // Auditor cannot change their mind and approve/oppose multiple times
        require( !audited, "Cannot oppose an audited contract" );

        // Switch to true to complete the audit and explicitly set approved to false (default is false)
        audited = true;
        approved = false;

        // TODO: think about the owner being sent and transfer of ownership and how that affects the store
        IAuditingPlatform( platform ).completeAudit( initiator, deployer, address( this ), _creationHash, approved );

        emit OpposedAudit( initiator );
    }

}

