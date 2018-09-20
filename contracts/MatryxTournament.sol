pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

import "./MatryxTrinity.sol";
import "./IMatryxToken.sol";

import "./MatryxSystem.sol";
import "./MatryxPlatform.sol";
import "./MatryxRound.sol";
import "./MatryxSubmission.sol";

import "./LibGlobals.sol";

contract MatryxTournament is MatryxTrinity {
    constructor (uint256 _version, address _system) MatryxTrinity(_version, _system) public {}
}

interface IMatryxTournament {
    function transferFrom(address, address, uint256) external;
    function transferTo(address, address, uint256) external;

    function getOwner() external view returns (address);
    function getTitle() external view returns (bytes32[3]);
    function getCategory() external view returns (bytes32);
    function getDescriptionHash() external view returns (bytes32[2]);
    function getFileHash() external view returns (bytes32[2]);
    function getBounty() external view returns (uint256);
    function getEntryFee() external view returns (uint256);

    function getRounds() external view returns (address[]);
    function getDetails() external view returns (LibTournament.TournamentDetails);

    function enterTournament() external;
    function createSubmission(LibSubmission.SubmissionDetails) external returns (address);

    function selectWinners(LibRound.WinnersData, LibRound.RoundDetails) external;
}

// dependents: LibPlatform
library LibTournament {
    using SafeMath for uint256;

    event RoundCreated(address roundAddress);
    event SubmissionCreated(address submissionAddress);

    // All information needed for creation of Tournament
    struct TournamentDetails {
        bytes32[3] title;
        bytes32 category;
        bytes32[2] descHash;
        bytes32[2] fileHash;
        uint256 bounty;
        uint256 entryFee;
    }

    // All state data and details of Tournament
    struct TournamentData {
        address owner;
        TournamentDetails details;
        address[] rounds;
        address[] entrants;
        mapping(address=>LibGlobals.o_uint256) entryFeePaid;
        uint256 totalEntryFees;
    }

    /// @dev Returns the owner of this Tournament
    function getOwner(address self, address, MatryxPlatform.Data storage data) public view returns (address) {
        return data.tournaments[self].owner;
    }

    /// @dev Returns the title of this Tournament
    function getTitle(address self, address, MatryxPlatform.Data storage data) public view returns (bytes32[3]) {
        return data.tournaments[self].details.title;
    }

    /// @dev Returns the category of this Tournament
    function getCategory(address self, address, MatryxPlatform.Data storage data) public view returns (bytes32) {
        return data.tournaments[self].details.category;
    }

    /// @dev Returns the description hash of this Tournament
    function getDescriptionHash(address self, address, MatryxPlatform.Data storage data) public view returns (bytes32[2]) {
        return data.tournaments[self].details.descHash;
    }

    /// @dev Returns the file hash of this Tournament
    function getFileHash(address self, address, MatryxPlatform.Data storage data) public view returns (bytes32[2]) {
        return data.tournaments[self].details.fileHash;
    }

    /// @dev Returns the bounty of this Tournament
    function getBounty(address self, address, MatryxPlatform.Data storage data) public view returns (uint256) {
        return data.tournaments[self].details.bounty;
    }

    function getEntryFee(address self, address, MatryxPlatform.Data storage data) public view returns (uint256) {
        return data.tournaments[self].details.entryFee;
    }

    /// @dev Returns all Round addresses of this Tournament
    function getRounds(address self, address, MatryxPlatform.Data storage data) public view returns (address[]) {
        return data.tournaments[self].rounds;
    }

    /// @dev Returns the data struct of this Tournament
    function getDetails(address self, address, MatryxPlatform.Data storage data) public view returns (LibTournament.TournamentDetails) {
        return data.tournaments[self].details;
    }

    /// @dev Enter Tournament
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param data    Data struct on Platform
    function enterTournament(address self, address sender, MatryxPlatform.Info storage info, MatryxPlatform.Data storage data) public {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        uint256 entryFee = tournament.details.entryFee;

        require(data.users[sender].exists, "Must have entered Matryx");
        require(sender != tournament.owner, "Cannot enter own Tournament");
        IMatryxTournament(self).transferFrom(info.token, sender, entryFee);

        tournament.entryFeePaid[sender].exists = true;
        tournament.entryFeePaid[sender].value = entryFee;
        tournament.totalEntryFees = tournament.totalEntryFees.add(entryFee);
        data.users[sender].tournamentsEntered.push(self);
    }

    /// @dev Creates a new Round on this Tournament
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param info      Info struct on Platform
    /// @param data      Data struct on Platform
    /// @param rDetails  Details of the Round being created
    /// @return          Address of the created Round
    function createRound(address self, address sender, MatryxPlatform.Info storage info, MatryxPlatform.Data storage data, LibRound.RoundDetails rDetails) internal returns (address) {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.owner, "Must be owner");
        require(IMatryxToken(info.token).balanceOf(self) >= rDetails.bounty, "Insufficient funds for Round");

        address rAddress = new MatryxRound(info.version, info.system);

        MatryxSystem(info.system).setContractType(rAddress, MatryxSystem.ContractType.Round);
        tournament.rounds.push(rAddress);
        data.allRounds.push(rAddress);

        IMatryxTournament(self).transferTo(info.token, rAddress, rDetails.bounty);

        LibRound.RoundData storage round = data.rounds[rAddress];
        round.tournament = self;
        round.details = rDetails;

        emit RoundCreated(rAddress);
        return rAddress;
    }

    /// @dev Creates a new Submissions
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param info      Info struct on Platform
    /// @param data      Data struct on Platform
    /// @param sDetails  Submission details (title, descHash, fileHash)
    /// @return          Address of the created Submission
    function createSubmission(address self, address sender, MatryxPlatform.Info storage info, MatryxPlatform.Data storage data, LibSubmission.SubmissionDetails sDetails) public returns (address) {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(tournament.entryFeePaid[sender].exists, "Must have paid entry fee");

        address sAddress = new MatryxSubmission(info.version, info.system);

        MatryxSystem(info.system).setContractType(sAddress, MatryxSystem.ContractType.Submission);
        data.allSubmissions.push(sAddress);
        data.users[sender].submissions.push(sAddress);

        address roundAddress = tournament.rounds[tournament.rounds.length - 1];
        LibRound.RoundData storage round = data.rounds[roundAddress];
        round.submissions.push(sAddress);

        LibSubmission.SubmissionData storage submission = data.submissions[sAddress];
        submission.owner = sender;
        submission.tournament = self;
        submission.round = roundAddress;
        submission.details = sDetails;
        submission.timeSubmitted = now;
        submission.timeUpdated = now;

        emit SubmissionCreated(sAddress);
        return sAddress;
    }

    /// @dev Select winners of the current round
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param info      Info struct on Platform
    /// @param data      Data struct on Platform
    /// @param wData     Winners data struct
    /// @param rDetails  New round details struct
    function selectWinners(address self, address sender, MatryxPlatform.Info storage info, MatryxPlatform.Data storage data, LibRound.WinnersData wData, LibRound.RoundDetails rDetails) public {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.owner, "Must be owner");

        address rAddress = tournament.rounds[tournament.rounds.length - 1];
        LibRound.RoundData storage round = data.rounds[rAddress];

        uint256 distTotal = 0;
        for (uint256 i = 0; i < wData.winners.length; i++) {
            distTotal = distTotal.add(wData.distribution[i]);
        }

        for (i = 0; i < wData.winners.length; i++) {
            address winner = wData.winners[i];
            uint256 reward = wData.distribution[i].mul(round.details.bounty).div(distTotal);

            IMatryxRound(rAddress).transferTo(info.token, winner, reward);
            data.submissions[winner].reward = reward;

            address owner = data.submissions[winner].owner;
            data.users[owner].totalWinnings = data.users[owner].totalWinnings.add(reward);
        }

        round.winners = wData.winners;

        createRound(self, sender, info, data, rDetails);
    }
}
