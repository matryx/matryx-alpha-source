pragma solidity ^0.4.18;
pragma experimental ABIEncoderV2;

import "../math/SafeMath.sol";
import "./LibTournamentStateManagement.sol";
import "../LibEnums.sol";
import "../../interfaces/IMatryxToken.sol";
import "../../interfaces/IMatryxPlatform.sol";
import "../../interfaces/IMatryxTournament.sol";

library LibTournamentEntrantMethods
{
    using SafeMath for uint256;

    struct uint256_optional
    {
        bool exists;
        uint256 value;
    }

    /// @dev Enters the user into the tournament.
    /// @param _entrantAddress Address of the user to enter.
    /// @return success Whether or not the user was entered successfully.
    function enterUserInTournament(LibConstruction.TournamentData storage data, LibTournamentStateManagement.StateData storage stateData, LibTournamentStateManagement.EntryData storage entryData, address _entrantAddress) public returns (bool _success)
    {
        if(entryData.addressToEntryFeePaid[_entrantAddress].exists == true)
        {
            return false;
        }

        // Change the tournament's state to reflect the user entering.
        entryData.addressToEntryFeePaid[_entrantAddress].exists = true;
        entryData.addressToEntryFeePaid[_entrantAddress].value = data.entryFee;
        stateData.entryFeesTotal = stateData.entryFeesTotal.add(data.entryFee);
        entryData.numberOfEntrants = entryData.numberOfEntrants.add(1);

        (, address currentRoundAddress) = LibTournamentStateManagement.currentRound(stateData);

        return true;
    }

    /// @dev Returns the fee in MTX to be payed by a prospective entrant.
    /// @return Entry fee for this tournament.
    function getEntryFee(LibConstruction.TournamentData data) public view returns (uint256)
    {
        return data.entryFee;
    }

    function collectMyEntryFee(LibTournamentStateManagement.StateData storage stateData, LibTournamentStateManagement.EntryData storage entryData, address matryxTokenAddress) public
    {
        returnEntryFeeToEntrant(stateData, entryData, msg.sender, matryxTokenAddress);
    }

    function returnEntryFeeToEntrant(LibTournamentStateManagement.StateData storage stateData, LibTournamentStateManagement.EntryData storage entryData, address _entrant, address matryxTokenAddress) internal
    {
        // Make sure entrants don't withdraw their entry fee early
        (,address currentRoundAddress) = LibTournamentStateManagement.currentRound(stateData);
        IMatryxToken matryxToken = IMatryxToken(matryxTokenAddress);
        require(matryxToken.transfer(_entrant, entryData.addressToEntryFeePaid[_entrant].value));
        stateData.entryFeesTotal = stateData.entryFeesTotal.sub(entryData.addressToEntryFeePaid[_entrant].value);
        entryData.addressToEntryFeePaid[_entrant].exists = false;
        entryData.addressToEntryFeePaid[_entrant].value = 0;
        entryData.numberOfEntrants = entryData.numberOfEntrants.sub(1);
    }

    // function createSubmission(address currentRoundAddress, LibTournamentStateManagement.EntryData storage entryData, address platformAddress, LibConstruction.SubmissionData submissionData) public returns (address _submissionAddress)
    // function createSubmission(address[3] _requiredAddresses, LibTournamentStateManagement.EntryData storage entryData, LibConstruction.SubmissionData submissionData) public returns (address _submissionAddress)
    function createSubmission(address _platformAddress, address _roundAddress, LibTournamentStateManagement.EntryData storage entryData, LibConstruction.SubmissionData submissionData) public returns (address _submissionAddress)
    {
        address submissionAddress = IMatryxRound(_roundAddress).createSubmission(msg.sender, _platformAddress, submissionData);

        entryData.numberOfSubmissions = entryData.numberOfSubmissions.add(1);
        entryData.entrantToSubmissionToSubmissionIndex[msg.sender][submissionAddress].exists = true;
        entryData.entrantToSubmissionToSubmissionIndex[msg.sender][submissionAddress].value = entryData.entrantToSubmissions[msg.sender].length;
        entryData.entrantToSubmissions[msg.sender].push(submissionAddress);
        IMatryxPlatform(_platformAddress).updateSubmissions(msg.sender, submissionAddress);
        return submissionAddress;
    }

    function withdrawFromAbandoned(LibTournamentStateManagement.StateData storage stateData, LibTournamentStateManagement.EntryData storage entryData, address matryxTokenAddress) public
    {
        require(LibTournamentStateManagement.getState(stateData) == uint256(LibEnums.TournamentState.Abandoned), "This tournament is still valid.");
        require(!entryData.hasWithdrawn[msg.sender]);

        address currentRoundAddress;
        (, currentRoundAddress) = LibTournamentStateManagement.currentRound(stateData);
        uint256 numberOfEntrants = entryData.numberOfEntrants;
        uint256 bounty = IMatryxTournament(this).getBounty();
        if(entryData.hasWithdrawn[msg.sender] == false)
        {
            // If this is the first withdrawal being made...
            if(stateData.hasBeenWithdrawnFrom == false)
            {
                uint256 roundBounty = IMatryxRound(currentRoundAddress).transferBountyToTournament();
                stateData.roundBountyAllocation = stateData.roundBountyAllocation.sub(roundBounty);
                returnEntryFeeToEntrant(stateData, entryData, msg.sender, matryxTokenAddress);
                require(IMatryxToken(matryxTokenAddress).transfer(msg.sender, bounty.div(entryData.numberOfEntrants).mul(2)));

                stateData.hasBeenWithdrawnFrom = true;
            }
            else
            {
                returnEntryFeeToEntrant(stateData, entryData, msg.sender, matryxTokenAddress);
                require(IMatryxToken(matryxTokenAddress).transfer(msg.sender, bounty.mul(numberOfEntrants.sub(2)).div(numberOfEntrants).div(numberOfEntrants.sub(1))));
            }

            entryData.hasWithdrawn[msg.sender] = true;
        }
    }
}
