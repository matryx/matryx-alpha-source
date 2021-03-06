pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./LibGlobals.sol";

import "./MatryxSystem.sol";
import "./MatryxPlatform.sol";
import "./MatryxForwarder.sol";
import "./IToken.sol";
import "./MatryxCommit.sol";

library LibTournament {
    using SafeMath for uint256;

    uint256 constant MIN_ROUND_LENGTH = 1 hours;
    uint256 constant MAX_ROUND_LENGTH = 365 days;

    event TournamentUpdated(address indexed tournament);
    event TournamentBountyAdded(address indexed tournament, address indexed donor, uint256 amount);

    event RoundCreated(address indexed tournament, uint256 roundIndex);
    event RoundUpdated(address indexed tournament, uint256 roundIndex);
    event RoundWinnersSelected(address indexed tournament, uint256 roundIndex);

    event SubmissionCreated(address indexed tournament, bytes32 submissionHash, address indexed creator);
    event SubmissionRewarded(address indexed tournament, bytes32 submissionHash);

    struct TournamentInfo {
        uint256 version;
        address owner;
    }

    // All information needed for creation of Tournament
    struct TournamentDetails {
        string content;
        uint256 bounty;
        uint256 entryFee;
    }

    // All state data and details of Tournament
    struct TournamentData {
        LibTournament.TournamentInfo info;
        LibTournament.TournamentDetails details;

        LibTournament.RoundData[] rounds;

        mapping(address=>LibGlobals.o_uint256) entryFeePaid;
        address[] allEntrants;
        uint256 totalEntryFees;

        mapping(address=>bool) hasWithdrawn;
        uint256 numWithdrawn;
    }

    struct RoundInfo {
        bytes32[] submissions;
        uint256 submitterCount;
        LibTournament.WinnersData winners;
        bool closed;
    }

    struct RoundDetails {
        uint256 start;
        uint256 duration;
        uint256 review;
        uint256 bounty;
    }

    // All information needed to choose winning submissions
    struct WinnersData {
        bytes32[] submissions;
        uint256[] distribution;
        uint256 action;
    }

    struct RoundData {
        LibTournament.RoundInfo info;
        LibTournament.RoundDetails details;

        mapping(address=>bool) hasSubmitted;
    }

    struct SubmissionData {
        address tournament;
        uint256 roundIndex;
        bytes32 commitHash;
        string content;
        uint256 reward;
        uint256 timestamp;
    }

    /// @dev Returns Tournament Info
    function getInfo(
        address self,
        address,
        MatryxPlatform.Data storage data
    )
        public
        view
        returns (LibTournament.TournamentInfo memory)
    {
        return data.tournaments[self].info;
    }

    /// @dev Returns the details struct of this Tournament
    function getDetails(
        address self,
        address,
        MatryxPlatform.Data storage data
    )
        public
        view
        returns (LibTournament.TournamentDetails memory)
    {
        return data.tournaments[self].details;
    }

    /// @dev Returns the MTX balance of the Tournament
    function getBalance(
        address self,
        address,
        MatryxPlatform.Data storage data
    )
        public
        view
        returns (uint256)
    {
        return data.tournamentBalance[self];
    }

    /// @dev Returns the state of this Tournament
    function getState(
        address self,
        address sender,
        MatryxPlatform.Data storage data
    )
        public
        view
        returns (uint256)
    {
        uint256 currentRoundIndex = getCurrentRoundIndex(self, self, data);
        uint256 roundState = getRoundState(self, sender, data, currentRoundIndex);

        if (roundState >= uint256(LibGlobals.RoundState.Unfunded) &&
            roundState <= uint256(LibGlobals.RoundState.HasWinners)
        ) {
            return uint256(LibGlobals.TournamentState.Open);
        }
        else if (roundState == uint256(LibGlobals.RoundState.NotYetOpen)) {
            if (currentRoundIndex != 0) {
                return uint256(LibGlobals.TournamentState.OnHold);
            }
            return uint256(LibGlobals.TournamentState.NotYetOpen);
        }
        else if (roundState == uint256(LibGlobals.RoundState.Closed)) {
            return uint256(LibGlobals.TournamentState.Closed);
        }
        return uint256(LibGlobals.TournamentState.Abandoned);
    }

    /// @dev Returns the state of this Tournament
    /// @param roundIndex   Round index
    function getRoundState(
        address self,
        address sender,
        MatryxPlatform.Data storage data,
        uint256 roundIndex
    )
        public
        view
        returns (uint256)
    {
        LibTournament.RoundData storage round = data.tournaments[self].rounds[roundIndex];

        if (now < round.details.start) {
            return uint256(LibGlobals.RoundState.NotYetOpen);
        }
        else if (now < round.details.start.add(round.details.duration)) {
            if (round.details.bounty == 0) {
                return uint256(LibGlobals.RoundState.Unfunded);
            }
            return uint256(LibGlobals.RoundState.Open);
        }
        else if (now < round.details.start.add(round.details.duration).add(round.details.review)) {
            if (round.info.closed) {
                return uint256(LibGlobals.RoundState.Closed);
            }
            else if (round.info.submissions.length == 0) {
                return uint256(LibGlobals.RoundState.Abandoned);
            }
            else if (round.info.winners.submissions.length > 0) {
                return uint256(LibGlobals.RoundState.HasWinners);
            }
            return uint256(LibGlobals.RoundState.InReview);
        }
        else if (round.info.winners.submissions.length > 0) {
            return uint256(LibGlobals.RoundState.Closed);
        }
        return uint256(LibGlobals.RoundState.Abandoned);
    }

    /// @dev Returns the current round number and address of this Tournament
    function getCurrentRoundIndex(
        address self,
        address sender,
        MatryxPlatform.Data storage data
    )
        public
        view
        returns (uint256)
    {
        LibTournament.RoundData[] storage rounds = data.tournaments[self].rounds;
        uint256 numRounds = rounds.length;

        if (numRounds > 1 && getRoundState(self, sender, data, numRounds-2) == uint256(LibGlobals.RoundState.HasWinners)) {
            return numRounds - 2;
        } else {
            return numRounds - 1;
        }
    }

    /// @dev Returns the Round Info
    /// @param roundIndex   Round index
    function getRoundInfo(
        address self,
        address sender,
        MatryxPlatform.Data storage data,
        uint256 roundIndex
    )
        public
        view
        returns (LibTournament.RoundInfo memory)
    {
        return data.tournaments[self].rounds[roundIndex].info;
    }

    /// @dev Returns the Round Details
    /// @param roundIndex   Round index
    function getRoundDetails(
        address self,
        address sender,
        MatryxPlatform.Data storage data,
        uint256 roundIndex
    )
        public
        view
        returns (LibTournament.RoundDetails memory)
    {
        return data.tournaments[self].rounds[roundIndex].details;
    }

    /// @dev Returns the total number of Submissions made in all rounds of this Tournament
    /// @param self  Address of this Tournament
    /// @param data  Data struct on Platform
    /// @return      Number of all Submissions in this Tournament
    function getSubmissionCount(
        address self,
        address sender,
        MatryxPlatform.Data storage data
    )
        public
        view
        returns (uint256)
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        LibTournament.RoundData[] storage rounds = data.tournaments[self].rounds;
        uint256 count = 0;

        for (uint256 i = 0; i < rounds.length; i++) {
            count += tournament.rounds[i].info.submissions.length;
        }

        return count;
    }

    /// @dev Returns the entry fee that an entrant has paid
    /// @param self  Address of this Tournament
    /// @param data  Data struct on Platform
    /// @param user  Address of the tournament entrant
    /// @return      Entry fee uAddress has paid
    function getEntryFeePaid(
        address self,
        address,
        MatryxPlatform.Data storage data,
        address user
    )
        public
        view
        returns (uint256)
    {
        return data.tournaments[self].entryFeePaid[user].value;
    }

    /// @dev Returns true if address passed has entered the Tournament
    /// @param self  Address of this Tournament
    /// @param data  Data struct on Platform
    /// @param user  Address of some user
    /// @return      If user has entered tournament
    function isEntrant(
        address self,
        address,
        MatryxPlatform.Data storage data,
        address user
    )
        public
        view
        returns (bool)
    {
        return data.tournaments[self].entryFeePaid[user].exists;
    }

    /// @dev Returns true if the user is allowed to use Matryx
    function _canUseMatryx(
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data,
        address user
    )
        internal
        returns (bool)
    {
        if (data.blacklist[user]) return false;
        if (data.whitelist[user]) return true;

        if (IToken(info.token).balanceOf(user) > 0) {
            data.whitelist[user] = true;
            return true;
        }

        return false;
    }

    /// @dev Enter Tournament and pay entry fee
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param info    Info struct on Platform
    /// @param data    Data struct on Platform
    function enter(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data
    )
        public
    {
        require(_canUseMatryx(info, data, sender), "Must be allowed to use Matryx");
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        uint256 entryFee = tournament.details.entryFee;

        require(sender != tournament.info.owner, "Cannot enter own Tournament");
        require(!tournament.entryFeePaid[sender].exists, "Cannot enter Tournament more than once");
        require(getState(self, sender, data) < uint256(LibGlobals.TournamentState.Closed), "Cannot enter closed or abandoned Tournament");

        data.totalBalance = data.totalBalance.add(entryFee);
        require(IToken(info.token).transferFrom(sender, address(this), entryFee), "Transfer failed");

        tournament.entryFeePaid[sender].exists = true;
        tournament.entryFeePaid[sender].value = entryFee;
        tournament.totalEntryFees = tournament.totalEntryFees.add(entryFee);
        tournament.allEntrants.push(sender);
    }

    /// @dev Exit Tournament and recover entry fee
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param info    Info struct on Platform
    /// @param data    Data struct on Platform
    function exit(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(tournament.entryFeePaid[sender].exists, "Must be entrant");
        uint256 entryFeePaid = tournament.entryFeePaid[sender].value;

        tournament.entryFeePaid[sender].exists = false;

        if (entryFeePaid > 0) {
            tournament.totalEntryFees = tournament.totalEntryFees.sub(entryFeePaid);
            tournament.entryFeePaid[sender].value = 0;

            data.totalBalance = data.totalBalance.sub(entryFeePaid);
            require(IToken(info.token).transfer(sender, entryFeePaid), "Transfer failed");
        }
    }

    /// @dev Creates a new Round on this Tournament
    /// @param self      Address of this Tournament
    /// @param info      Info struct on Platform
    /// @param data      Data struct on Platform
    /// @param rDetails  Details of the Round being created
    /// @return          Address of the created Round
    function createRound(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data,
        LibTournament.RoundDetails memory rDetails
    )
        public
        returns (uint256)
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];

        require(sender == address(this), "Must be called by platform");
        require(data.tournamentBalance[self] >= rDetails.bounty, "Insufficient funds for Round");

        require(rDetails.duration >= MIN_ROUND_LENGTH, "Round too short");
        require(rDetails.duration <= MAX_ROUND_LENGTH, "Round too long");

        // TODO: add review time restrictions or auto review?

        LibTournament.RoundData memory round;
        round.details = rDetails;

        // if round started in the past, start now instead
        if (rDetails.start < now) {
            round.details.start = now;
        }

        tournament.rounds.push(round);
        uint256 roundIndex = tournament.rounds.length - 1;

        emit RoundCreated(self, roundIndex);
        return roundIndex;
    }

    /// @dev Creates a new Submission
    /// @param self        Address of this Tournament
    /// @param sender      msg.sender to the Tournament
    /// @param data        Data struct on Platform
    /// @param content     Submission title and description IPFS hash
    /// @param commitHash  Commit hash to submit
    /// @return            Address of the created Submission
    function createSubmission(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data,
        string memory content,
        bytes32 commitHash
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        LibCommit.Commit storage commit = data.commits[commitHash];

        require(_canUseMatryx(info, data, sender), "Must be allowed to use Matryx");
        require(tournament.entryFeePaid[sender].exists, "Must have paid entry fee");
        require(commit.owner == sender, "Must be owner of commit");

        uint256 index = getCurrentRoundIndex(self, sender, data);
        require(getRoundState(self, sender, data, index) == uint256(LibGlobals.RoundState.Open), "Round must be Open");

        bytes32 submissionHash = keccak256(abi.encodePacked(self, commitHash, index));
        require(data.submissions[submissionHash].timestamp == 0, "Commit has already been submitted to this round");

        LibTournament.RoundData storage round = tournament.rounds[index];

        LibTournament.SubmissionData storage submission = data.submissions[submissionHash];
        submission.tournament = self;
        submission.roundIndex = index;
        submission.commitHash = commitHash;
        submission.content = content;
        submission.timestamp = now;

        data.commitToSubmissions[commitHash].push(submissionHash);
        round.info.submissions.push(submissionHash);

        if (!round.hasSubmitted[sender]) {
            round.hasSubmitted[sender] = true;
            round.info.submitterCount += 1;
        }

        emit SubmissionCreated(self, submissionHash, sender);
    }

    /// @dev Updates the details of this tournament
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param data      Data struct on Platform
    /// @param tDetails  New tournament details
    function updateDetails(
        address self,
        address sender,
        MatryxPlatform.Data storage data,
        LibTournament.TournamentDetails memory tDetails
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");
        require(getState(self, sender, data) < uint256(LibGlobals.TournamentState.Closed), "Tournament must be active");

        if (bytes(tDetails.content).length > 0) {
            tournament.details.content = tDetails.content;
        }
        if (tDetails.entryFee != 0) {
            tournament.details.entryFee = tDetails.entryFee;
        }

        emit TournamentUpdated(self);
    }

    /// @dev Adds funds to the Tournament
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param info      Info struct on Platform
    /// @param data      Data struct on Platform
    /// @param amount    Amount of MTX to add
    function addToBounty(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data,
        uint256 amount
    )
        public
    {
        require(getState(self, sender, data) < uint256(LibGlobals.TournamentState.Closed), "Tournament must be active");
        require(amount > 0, "Cannot add zero amount");

        data.totalBalance = data.totalBalance.add(amount);
        data.tournamentBalance[self] = data.tournamentBalance[self].add(amount);
        data.tournaments[self].details.bounty = data.tournaments[self].details.bounty.add(amount);
        require(IToken(info.token).transferFrom(sender, address(this), amount), "Transfer failed");

        emit TournamentUpdated(self);
        emit TournamentBountyAdded(self, sender, amount);
    }

    /// @dev Transfers some of Tournament MTX to current Round
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param data    Data struct on Platform
    /// @param amount  Amount of MTX to transfer
    function transferToRound(
        address self,
        address sender,
        MatryxPlatform.Data storage data,
        uint256 amount
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");

        uint256 roundIndex = getCurrentRoundIndex(self, sender, data);
        LibTournament.RoundData storage round = tournament.rounds[roundIndex];

        uint256 rState = getRoundState(self, sender, data, roundIndex);
        require(rState <= uint256(LibGlobals.RoundState.InReview), "Cannot transfer after winners selected");

        uint256 newBounty = round.details.bounty.add(amount);
        require(newBounty <= data.tournamentBalance[self], "Tournament does not have the funds");

        round.details.bounty = newBounty;
        emit RoundUpdated(self, roundIndex);
    }

    /// @dev Transfers the round reward to its winning submissions during the winner selection process
    /// @param data        Data struct on Platform
    /// @param roundIndex  Index of the current round
    function _transferToWinners(
        address self,
        MatryxPlatform.Data storage data,
        uint256 roundIndex
    )
        internal
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        LibTournament.RoundData storage round = tournament.rounds[roundIndex];
        LibTournament.WinnersData storage wData = round.info.winners;

        uint256 distTotal = 0;
        for (uint256 i = 0; i < wData.submissions.length; i++) {
            distTotal = distTotal.add(wData.distribution[i]);
        }

        uint256 rewardLeft = round.details.bounty;
        for (uint256 i = 0; i < wData.submissions.length; i++) {
            bytes32 winningSub = wData.submissions[i];
            bytes32 commit = data.submissions[winningSub].commitHash;

            // when distribution is fractional (e.g. thirds), give leftover wei to last winningSub
            uint256 reward = rewardLeft;
            if (i < wData.submissions.length - 1) {
                reward = wData.distribution[i].mul(round.details.bounty).div(distTotal);
            }

            data.commitBalance[commit] = data.commitBalance[commit].add(reward);
            rewardLeft = rewardLeft.sub(reward);

            // only case subs get rewarded twice: selectWinners with doNothing, then closeTournament
            reward = reward.add(data.submissions[winningSub].reward);
            data.submissions[winningSub].reward = reward;

            emit SubmissionRewarded(self, winningSub);
        }

        data.tournamentBalance[self] = data.tournamentBalance[self].sub(round.details.bounty);
    }

    /// @dev Select winners of the current round
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param info      Info struct on Platform
    /// @param data      Data struct on Platform
    /// @param wData     Winners data struct
    /// @param rDetails  New round details struct
    function selectWinners(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data,
        LibTournament.WinnersData memory wData,
        LibTournament.RoundDetails memory rDetails
    )
        public
    {
        require(wData.submissions.length > 0, "Must specify winners");
        require(wData.submissions.length == wData.distribution.length, "Must include distribution for each winner");
        require(wData.action < 3, "Invalid SelectWinnerAction");

        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");

        uint256 roundIndex = getCurrentRoundIndex(self, sender, data);
        require(getRoundState(self, sender, data, roundIndex) == uint256(LibGlobals.RoundState.InReview), "Must be in review");

        for (uint256 i = 0; i < wData.submissions.length; i++) {
            LibTournament.SubmissionData storage submission = data.submissions[wData.submissions[i]];
            bool submissionInRound = submission.tournament == self && submission.roundIndex == roundIndex;
            require(submissionInRound, "Must select winners from current round");
        }

        LibTournament.RoundData storage round = tournament.rounds[roundIndex];
        LibTournament.RoundDetails memory newRound;

        round.info.winners = wData;

        if (wData.action == uint256(LibGlobals.SelectWinnerAction.CloseTournament)) {
            // transfer rest of tournament balance to round and close tournament
            round.info.closed = true;
            round.details.bounty = data.tournamentBalance[self];
            emit RoundUpdated(self, roundIndex);

            _transferToWinners(self, data, roundIndex);
        }

        else if (wData.action == uint256(LibGlobals.SelectWinnerAction.DoNothing)) {
            _transferToWinners(self, data, roundIndex);

            // create new round but don't start
            uint256 bounty = data.tournamentBalance[self];
            bounty = bounty < round.details.bounty ? bounty : round.details.bounty;

            newRound.start = round.details.start.add(round.details.duration).add(round.details.review);
            newRound.duration = round.details.duration;
            newRound.review = round.details.review;
            newRound.bounty = bounty;

            createRound(self, address(this), info, data, newRound);
        }

        else if (wData.action == uint256(LibGlobals.SelectWinnerAction.StartNextRound)) {
            _transferToWinners(self, data, roundIndex);

            // create new round and start immediately
            round.info.closed = true;

            newRound.start = now;
            newRound.duration = rDetails.duration;
            newRound.review = rDetails.review;
            newRound.bounty = rDetails.bounty;

            createRound(self, address(this), info, data, newRound);
        }

        emit RoundWinnersSelected(self, roundIndex);
    }

    /// @dev Updates the details of an upcoming round that has not yet started
    /// @param self      Address of this Tournament
    /// @param sender    msg.sender to the Tournament
    /// @param data      Data struct on Platform
    /// @param rDetails  New round details
    function updateNextRound(
        address self,
        address sender,
        MatryxPlatform.Data storage data,
        LibTournament.RoundDetails memory rDetails
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");

        uint256 roundIndex = tournament.rounds.length - 1;
        require(getRoundState(self, sender, data, roundIndex) == uint256(LibGlobals.RoundState.NotYetOpen), "Cannot edit open Round");

        LibTournament.RoundDetails storage details = tournament.rounds[roundIndex].details;

        if (rDetails.start > 0) {
            if (tournament.rounds.length > 1) {
                LibTournament.RoundDetails storage currentDetails = tournament.rounds[roundIndex - 1].details;
                require(rDetails.start >= currentDetails.start.add(currentDetails.duration).add(currentDetails.review), "Round cannot start before end of review");
                details.start = rDetails.start;
            }
            else {
                details.start = rDetails.start < now ? now : rDetails.start;
            }
        }

        if (rDetails.duration > 0) {
            // ensure duration is valid
            require(rDetails.duration >= MIN_ROUND_LENGTH, "Round too short");
            require(rDetails.duration <= MAX_ROUND_LENGTH, "Round too long");
            details.duration = rDetails.duration;
        }

        if (rDetails.review > 0) { // TODO: review length restriction
            details.review = rDetails.review;
        }

        if (rDetails.bounty > 0) {
            require(rDetails.bounty <= data.tournamentBalance[self], "Tournament does not have the funds");
            details.bounty = rDetails.bounty;
        }

        emit RoundUpdated(self, roundIndex);
    }

    /// @dev Starts the next Round after a SelectWinnersAction.DoNothing
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param data    Data struct on Platform
    function startNextRound(
        address self,
        address sender,
        MatryxPlatform.Data storage data
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");
        require(tournament.rounds.length > 1, "No round to start");

        uint256 roundIndex = getCurrentRoundIndex(self, sender, data);
        require(getRoundState(self, sender, data, roundIndex) == uint256(LibGlobals.RoundState.HasWinners), "Must have selected winners");

        tournament.rounds[roundIndex].info.closed = true;

        roundIndex = roundIndex.add(1);
        tournament.rounds[roundIndex].details.start = now;
    }

    /// @dev Entrant can withdraw an even share of remaining balance from abandoned Tournament
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param info    Info struct on Platform
    /// @param data    Data struct on Platform
    function withdrawFromAbandoned(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];

        uint256 roundIndex = getCurrentRoundIndex(self, sender, data);
        LibTournament.RoundData storage round = tournament.rounds[roundIndex];

        require(getState(self, sender, data) == uint256(LibGlobals.TournamentState.Abandoned), "Tournament must be abandoned");
        require(round.hasSubmitted[sender], "Must be submission owner in latest round");
        require(!tournament.hasWithdrawn[sender], "Already withdrawn");

        uint256 tBalance = data.tournamentBalance[self];
        uint256 submitterCount = round.info.submitterCount.sub(tournament.numWithdrawn);
        uint256 share = tBalance.div(submitterCount);

        tournament.hasWithdrawn[sender] = true;
        tournament.numWithdrawn++;

        data.totalBalance = data.totalBalance.sub(share);
        data.tournamentBalance[self] = data.tournamentBalance[self].sub(share);
        require(IToken(info.token).transfer(sender, share), "Transfer failed");

        exit(self, sender, info, data);
    }

    /// @dev Closes Tournament after a SelectWinnersAction.DoNothing and transfers all funds to winners
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param data    Data struct on Platform
    function closeTournament(
        address self,
        address sender,
        MatryxPlatform.Data storage data
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");
        require(tournament.rounds.length > 1, "Must be in Round limbo");

        uint256 roundIndex = getCurrentRoundIndex(self, sender, data);
        LibTournament.RoundData storage round = tournament.rounds[roundIndex];
        require(getRoundState(self, sender, data, roundIndex) == uint256(LibGlobals.RoundState.HasWinners), "Must have selected winners");

        // close round
        round.info.closed = true;
        round.details.bounty = data.tournamentBalance[self];
        emit RoundUpdated(self, roundIndex);

        // then transfer all to winners of that Round
        _transferToWinners(self, data, roundIndex);

        // delete ghost round
        tournament.rounds.length--;
    }

    /// @dev Tournament owner can recover tournament funds if the round ends with no submissions
    /// @param self    Address of this Tournament
    /// @param sender  msg.sender to the Tournament
    /// @param info    Info struct on Platform
    /// @param data    Data struct on Platform
    function recoverBounty(
        address self,
        address sender,
        MatryxPlatform.Info storage info,
        MatryxPlatform.Data storage data
    )
        public
    {
        LibTournament.TournamentData storage tournament = data.tournaments[self];
        require(sender == tournament.info.owner, "Must be owner");
        require(tournament.numWithdrawn == 0, "Already withdrawn");

        uint256 roundIndex = getCurrentRoundIndex(self, sender, data);
        LibTournament.RoundData storage round = tournament.rounds[roundIndex];

        require(getRoundState(self, sender, data, roundIndex) == uint256(LibGlobals.RoundState.Abandoned), "Tournament must be abandoned");
        require(round.info.submissions.length == 0, "Must have 0 submissions");

        uint256 funds = data.tournamentBalance[self];

        tournament.numWithdrawn = 1;

        // recover remaining tournament and round funds
        data.totalBalance = data.totalBalance.sub(funds);
        data.tournamentBalance[self] = 0;
        require(IToken(info.token).transfer(sender, funds), "Transfer failed");
    }
}
