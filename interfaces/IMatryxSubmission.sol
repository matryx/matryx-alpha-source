pragma solidity ^0.4.18;
pragma experimental ABIEncoderV2;

import "../libraries/LibConstruction.sol";

interface IMatryxSubmission {
  function getTournament() public view returns (address);
  function getRound() public view returns (address);
  function isAccessible(address _requester) public view returns (bool);
  function getTitle() public view returns(string);
  function getAuthor() public view returns(address);
  function getDescriptionHash() public view returns (bytes32[2]);
  function getFileHash() public view returns (bytes32[2]);
  function getReferences() public view returns(address[]);
  function getContributors() public view returns(address[]);
  function getTimeSubmitted() public view returns(uint256);
  function getTimeUpdated() public view returns(uint256);
  function update(LibConstruction.SubmissionModificationData _modificationData, LibConstruction.ContributorsModificationData _contributorsModificationData, LibConstruction.ReferencesModificationData _referencesModificationData) public;
  function updateTitle(string _title) public;
  function updateDescription(bytes32[2] _externalAddress) public;
  function updateFile(bytes32[2] _fileHash) public;
  function addToWinnings(uint256 _amount) public;
  function addReference(address _reference) public;
  function removeReference(address _reference) public;
  function receiveReferenceRequest() public;
  function cancelReferenceRequest() public;
  function approveReference(address _reference) public;
  function removeReferenceApproval(address _reference) public;
  function flagMissingReference(address _reference) public;
  function removeMissingReferenceFlag(address _reference) public;
  function setContributorsAndReferences(LibConstruction.ContributorsAndReferences _contribsAndRefs) public;
  function addContributor(address _contributor, uint128 _bountyAllocation) public;
  function addContributors(address[] _contributorsToAdd, uint128[] _distribution) public;
  function removeContributor(uint256 _contributorIndex) public;
  function removeContributors(address[] _contributorsToRemove) public;
  function getBalance() public returns (uint256);
  function withdrawReward() public;
  function myReward() public view returns (uint256);
  //function deleteSubmission() public;
}
