pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import './Ownable.sol';
import './Tournament.sol';
import './MatryxToken.sol';

contract Round is Ownable {
	using SafeMath for uint256;

	address public tournamentAddress;
	address public matryxToken;
	uint256 public roundIndex;
	address public previousRound;
	address public nextRound;
	uint256 public startTime;
	uint256 public endTime;
	uint256 public reviewPeriodEndTime;
	uint256 public reward;
	uint256 public winningSubmissionIndex;
	bool public winningSubmissionChosen;

	mapping(address => uint) addressToParticipantType;
 	mapping(address => Submission[]) contributorToSubmissionArray;
	mapping(bytes32 => Submission) externalAddressToSubmission;
	Submission[] submissions;

	function Round(address _tournamentAddress, uint256 _reward, uint256 _roundIndex) public
	{		
		tournamentAddress = _tournamentAddress;
		roundIndex = _roundIndex;
		reward = _reward;
		winningSubmissionChosen = false;
	}

	struct Submission {
		// Tournament identification
		address tournamentAddress;
		
		// Submission
		string name;
		address author;
		bytes32 externalAddress;
		address[] references;
		address[] contributors;
		uint256 timeSubmitted;
		bool publicallyAccessibleDuringTournament;

		uint256 balance;
	}

	// ----------------- Enums  --------------------

	enum participantType { nonentrant, entrant, contributor, author }

	// ----------------- Events --------------------

	event WinningSubmissionChosen(uint256 _submissionIndex);

	// ----------------- Modifiers -----------------

	modifier duringOpenSubmission()
	{
		require(now > startTime);
		require(endTime > now);
		require(winningSubmissionChosen == false);
		_;
	}

	modifier duringWinnerSelection()
	{
		require(endTime != 0);
		require(now > endTime);
		require(winningSubmissionChosen == false);
		_;
	}

	modifier afterWinnerSelected()
	{
		require(winningSubmissionChosen == true);
		_;
	}

	modifier whileTournamentOpen()
	{
		Tournament tournament = Tournament(tournamentAddress);
		require(tournament.tournamentOpen());
		_;
	}

	modifier whenAccessible(address _requester, uint256 _index)
	{
		require(isAccessible(_requester, _index));
		_;
	}

	modifier onlySubmissionAuthor(uint256 _submissionIndex)
	{
		require(submissions[_submissionIndex].author == msg.sender);
		_;
	}

	function isAccessible(address _requester, uint256 _index) public constant returns (bool)
	{
		Tournament tournament = Tournament(tournamentAddress);
		Submission memory submission = submissions[_index];
		bool requesterOwnsTournament = tournament.isOwner(_requester);
		bool requesterIsEntrant = addressToParticipantType[_requester] != 0;
		bool publicallyAccessible = submission.publicallyAccessibleDuringTournament;
		bool closedTournament = !tournament.tournamentOpen();

		return requesterOwnsTournament || publicallyAccessible || closedTournament || (requesterIsEntrant && winningSubmissionChosen);
	}

	// ----------------- Getter Methods -----------------

	function roundIsOpen() public constant returns (bool)
	{
		return (now > startTime) && (endTime > now) && (winningSubmissionChosen == false);
	}

	function getSubmissionAuthor(uint256 _index) public constant whenAccessible(msg.sender, _index) returns (address) 
	{
		return submissions[_index].author;
	}

	function getSubmissionReferences(uint256 _index) public constant whenAccessible(msg.sender, _index) returns(address[])
	{
		return submissions[_index].references;
	}

	function getSubmissionContributors(uint256 _index) public constant whenAccessible(msg.sender, _index) returns(address[])
	{
		return submissions[_index].contributors;
	}

	function getSubmissionExternalAddress(uint256 _index) public constant whenAccessible(msg.sender, _index) returns(bytes32)
	{
		return submissions[_index].externalAddress;
	}

	function getSubmissionTimeSubmitted(uint256 _index) public constant whenAccessible(msg.sender, _index) returns(uint256)
	{
		return submissions[_index].timeSubmitted;
	}

	function getWinningSubmissionIndex() public constant returns (uint256)
	{
		return winningSubmissionIndex;
	}

	function numberOfSubmissions() public constant returns (uint256)
	{
		return submissions.length;
	}

	// ----------------- Round Administration Methods -----------------

	function Start(uint256 _duration) public onlyOwner
	{
		startTime = now;
		endTime = startTime.add(_duration);
	}

	// Allows the tournament owner to choose a winning submission for the round
	function chooseWinningSubmission(uint256 _submissionIndex) public onlyOwner duringWinnerSelection
	{
		winningSubmissionIndex = _submissionIndex;
		submissions[winningSubmissionIndex].balance.add(reward);
		WinningSubmissionChosen(winningSubmissionIndex);
		
		reward = 0;
		winningSubmissionChosen = true;
	}

	// ----------------- Entrant Methods -----------------

	function createSubmission(string _name, bytes32 _externalAddress, address _author, address[] references, address[] contributors, bool _publicallyAccessible) public duringOpenSubmission whileTournamentOpen returns (uint256 _submissionIndex)
	{
		uint256 timeSubmitted = now;
        Submission memory submission = Submission(tournamentAddress, _name, _author, _externalAddress, references, contributors, timeSubmitted, _publicallyAccessible, 0);
        
        // submission bookkeeping
        submissions.push(submission);
        contributorToSubmissionArray[msg.sender].push(submission);
        externalAddressToSubmission[_externalAddress] = submission;

        // round participant bookkeeping
        addressToParticipantType[_author] = uint(participantType.author);
        for(uint256 i = 0; i < contributors.length; i++)
        {
        	addressToParticipantType[contributors[i]] = uint(participantType.contributor);
        }

        Tournament(tournamentAddress).TriggerSubmissionCreatedEvent(roundIndex, submissions.length-1);
        return submissions.length-1;
	}

	function withdrawReward(uint256 _submissionIndex) public afterWinnerSelected onlySubmissionAuthor(_submissionIndex)
	{
		uint submissionReward = submissions[_submissionIndex].balance;
		submissions[_submissionIndex].balance = 0;
		MatryxToken(matryxToken).transfer(msg.sender, submissionReward);
	}
}