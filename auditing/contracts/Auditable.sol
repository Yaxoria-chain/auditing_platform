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
     *  @notice A deployed contract has a creation hash, store it so that you can access the code post self destruct
     *  @dev When a contract is deployed the first transaction is the contract creation - use that hash
     */
    address public contractCreationHash;

    /**
     * @notice After the creation hash is set by the deployer/dev the auditor must confirm that the correct 
     *         hash has been set in order to proceed to register the contract in the data store
     */
    bool confirmedCreationHash;

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
     *  @notice Method used to set the contract creation has before the audit is completed
     *  @dev After deploying this is the first thing that must be done by the owner and the owner only gets 1 attempt to prevent race conditions with the auditor
     *  @param _creationHash The transaction hash representing the contract creation
     */
    function setContractCreationHash( address _creationHash ) external onlyOwner() {
        // Prevent the owner from setting the hash post audit for safety
        require( !audited, "Contract has already been audited" );

        // We do not want the deployer to change this as the auditor is approving/opposing
        // Auditor can check that this has been set at the beginning and move on
        require( contractCreationHash == address( 0 ), "Hash has already been set" );

        contractCreationHash = _creationHash;

        emit CreationHashSet( contractCreationHash );
    }

    /**
     *  @notice Used to change the auditor by either the owner or auditor prior to the completion of the audit
     *  @param _auditor an address indicating who the new auditor will be (may be a contract)
     */
    function setAuditor( address _auditor ) external {
        // If auditor bails then owner can change
        // If auditor loses contact with owner and cannot complete the audit then they can change
        address initiator = _msgSender();
        require( initiator == auditor || initiator == _owner, "Auditor and Owner only" );

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require( !audited, "Cannot change auditor post audit" );

        auditor = _auditor;

        emit SetAuditor( initiator, auditor );
    }

    /**
     *  @notice Used to change the platform by either the owner or auditor prior to the completion of the audit
     *  @param _platform an address indicating a contract which will be the new platform (middle man)
     */
    function setPlatform( address _platform ) external {
        // If auditor bails then owner can change
        // If auditor loses contact with owner and cannot complete the audit then they can change
        address initiator = _msgSender();
        require( initiator == auditor || initiator == _owner, "Auditor and Owner only" );

        // Do not spam events after the audit; easier to check final state if you cannot change it
        require( !audited, "Cannot change platform post audit" );

        platform = _platform;

        emit SetPlatform( initiator, platform );
    }
    
    function register() external {
        require( confirmedCreationHash, "Hash has not been confirmed to be identical" );
        require( !audited,              "Contract has already been audited" );

        IAuditingPlatform( platform ).register( deployer, auditor, contractCreationHash );
    }

    function approveCreationHash( address creationHash ) external {
        // TODO: Flaw, any "auditor" may collude here and set the incorrect hash to register something else
        require( _msgSender() == auditor,               "Auditor only" );
        require( contractCreationHash != address( 0 ),  "Hash has not been set" );
        require( _creationHash == contractCreationHash, "Hashes do not match" );

        confirmedCreationHash = true;
    }

    /**
     *  @notice Auditor is in favor of the contract therefore they approve it and transmit to the platform
     *  @param _creationHash The contract creation hash that the owner set
     *  @dev The auditor and owner may conspire to use a different hash therefore the platform would yeet them after the fact - if they find out
     */
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

    /**
     *  @notice Auditor is against the contract therefore they oppose it and transmit to the platform
     *  @param _creationHash The contract creation hash that the owner set
     *  @dev The auditor and owner may conspire to use a different hash therefore the platform would yeet them after the fact - if they find out
     */
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

