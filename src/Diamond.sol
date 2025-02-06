// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Diamond is Ownable {
    // This stores the mapping of function selectors to facet addresses
    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition;
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint256 facetAddressPosition;
    }

    // Maps function selector to the facet that executes the function
    mapping(bytes4 => FacetAddressAndPosition) internal selectorToFacetAndPosition;
    // Maps facet addresses to function selectors
    mapping(address => FacetFunctionSelectors) internal facetFunctionSelectors;
    // Facet addresses
    address[] internal facetAddresses;

    event DiamondCut(address indexed facetAddress, bytes4[] selectors);

    constructor() Ownable(msg.sender) {}

    // Find facet for function that is called and execute the
    // function if a facet is found
    fallback() external payable {
        address facet = selectorToFacetAndPosition[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: Function does not exist");
        
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {revert(0, returndatasize())}
            default {return(0, returndatasize())}
        }
    }

    receive() external payable {}

    function addFacet(address _facetAddress, bytes4[] memory _functionSelectors) external onlyOwner {
        require(_facetAddress != address(0), "Diamond: Facet address cannot be 0");
        require(_functionSelectors.length > 0, "Diamond: No selectors provided");

        FacetFunctionSelectors storage facetFunctionSelector = facetFunctionSelectors[_facetAddress];
        
        // Add facet address if it's new
        if (facetFunctionSelector.functionSelectors.length == 0) {
            facetFunctionSelector.facetAddressPosition = facetAddresses.length;
            facetAddresses.push(_facetAddress);
        }

        // Add new selectors
        for (uint256 i; i < _functionSelectors.length; ++i) {
            bytes4 selector = _functionSelectors[i];
            require(selectorToFacetAndPosition[selector].facetAddress == address(0), 
                "Diamond: Function already exists");
            
            facetFunctionSelector.functionSelectors.push(selector);
            selectorToFacetAndPosition[selector] = FacetAddressAndPosition({
                facetAddress: _facetAddress,
                functionSelectorPosition: uint96(facetFunctionSelector.functionSelectors.length - 1)
            });
        }

        emit DiamondCut(_facetAddress, _functionSelectors);
    }
} 