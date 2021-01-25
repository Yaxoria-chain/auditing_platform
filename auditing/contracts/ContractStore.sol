// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IDatastore.sol";

contract ContractStore {
    
    using SafeMath for uint256;

    uint256 public registeredContractCount;
    uint256 public approvedContractCount;
    uint256 public opposedContractCount;

    Contract[] private contracts;

    struct Contract {
        address auditor;
        address deployer;
        address contractHash;
        address creationHash;
        bool    audited;
        bool    approved;
    }

    // Note for later, 0th index is used to check if it already exists
    mapping( address => uint256 ) private contractHash;
    mapping( address => uint256 ) private contractCreationHash;

    event NewContractRecord(
        address indexed contract_, 
        address indexed deployer, 
        uint256         contractIndex
    );

    event SetContractAuditor( 
        address indexed contract_, 
        address indexed auditor
    );

    event SetContractCreationHash( 
        address indexed contract_, 
        address indexed creationHash
    );

    event SetContractApproval( 
        address indexed contract_,
        address indexed auditor, 
        bool    indexed approved
    );

    constructor() internal {}

    function _registerContract( address contract_, address deployer ) internal {
        require( !_hasContractRecord( contract_ ), "Contract has already been registered" );

        // Create a single struct for the contract data and then reference it via indexing instead of managing mulitple storage locations
        Contract memory _contractData = Contract({
            deployer:       deployer,
            contractHash:   contract_
        });

        // Start adding from the next position and thus have an empty 0th default value which indicates an error to the user
        contracts[ contracts.length++ ] = _contractData;
        uint256 contractIndex_ = contracts.length;

        // Add to mapping for easy lookup, note that 0th index will also be default which allows us to do some safety checks
        contractHash[ contract_ ] = contractIndex_;

        registeredContractCount = registeredContractCount.add( 1 );

        emit NewContractRecord( contract_, deployer, contractIndex_ );
    }

    function _setContractAuditor( contract_, auditor ) internal {
        uint256 contractIndex_ = _contractIndex( contract_ );

        contracts[ contractIndex_ ].auditor = auditor;

        emit SetContractAuditor( contract_, auditor );
    }

    function _setContractCreationHash( contract_, creationHash ) internal {
        require( !_hasCreationRecord( creationHash ), "Contract exists in the contract creation hash mapping" );
        
        uint256 contractIndex_ = _contractIndex( contract_ );
        contractCreationHash[ creationHash ] = contractIndex_;
        
        contracts[ contractIndex_ ].creationHash = creationHash;

        emit SetContractCreationHash( contract_, creationHash );
    }

    function _setContractApproval( address contract_, bool approved ) internal {
        uint256 contractIndex_ = _contractIndex( contract_ );

        require( !contracts[ contractIndex_ ].audited, "Cannot change audit state post audit" );

        contracts[ contractIndex_ ].audited = true;
        contracts[ contractIndex_ ].approved = approved;

        if ( approved ) {
            approvedContractCount = approvedContractCount.add( 1 );
        } else {
            opposedContractCount = opposedContractCount.add( 1 );
        }

        emit SetContractApproval( contract_, contracts[ contractIndex_ ].auditor, approved );
    }

    function _hasContractRecord( address contractHash_ ) internal view returns ( bool ) {
        return contractHash[ contractHash_ ] != 0;
    }

    function _hasCreationRecord( address creationHash ) internal view returns ( bool ) {
        return contractCreationHash[ creationHash ] != 0;
    }

    function _contractDetailsRecursiveSearch( address contract_, address previousDataStore ) internal view returns 
    (
        address auditor,
        address deployer, 
        address contractHash_,
        address creationHash,  
        bool    audited, 
        bool    approved
    ) {
        // Check in all previous stores if this contract has been recorded
        // This is likely to be expensive so it is better to check each store manually / individually

        uint256 index;

        if ( _hasContractRecord( contract_ ) ) {
            index = contractHash[ contract_ ];
        } else if ( _hasCreationRecord( contract_ ) ) {
            index = contractCreationHash[ contract_ ];
        }

        if ( index != 0 ) {
            auditor       = contracts[ index ].auditor;
            deployer      = contracts[ index ].deployer;
            contractHash_ = contracts[ index ].contractHash;
            creationHash  = contracts[ index ].creationHash;
            audited       = contracts[ index ].audited;
            approved      = contracts[ index ].approved;
        } else if ( previousDataStore != address( 0 ) ) {
            ( auditor, deployer, contractHash_, creationHash, audited, approved ) = IDatastore( previousDatastore ).searchAllStoresForContractDetails( contract_ );
        } else {
            revert( "No contract record in any data store" );
        }
    }

    function _contractDetails( address contract_ ) internal view returns ( address, address, address, address, bool, bool ) {
        require( 0 < contracts.length,      "No contracts have been added" );
        uint256 index = _contractIndex( contract_ );
        require( index <= contracts.length, "Record does not exist" );

        return 
        (
            contracts[ index ].auditor,
            contracts[ index ].deployer,
            contracts[ index ].contractHash,
            contracts[ index ].creationHash,
            contracts[ index ].audited,
            contracts[ index ].approved,
        );
    }

    function _contractIndex( address contract_ ) private view returns ( uint256 index ) {
        index = contractHash[ contract_ ];

        if ( index == 0 ) {
            index = contractCreationHash[ contract_ ];
        }

        require( index != 0, "Contract has not been added" );
    }

}





