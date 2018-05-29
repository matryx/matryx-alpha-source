pragma solidity ^0.4.18;
pragma experimental ABIEncoderV2;

import "../../libraries/LibConstruction.sol";

interface IMatryxRoundFactory
{
	function createRound(address _platform, address _tournament, address _owner, LibConstruction.RoundData roundData) public returns (address _roundAddress);
}