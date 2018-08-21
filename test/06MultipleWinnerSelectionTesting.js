// TODO - test EVERYTHING

const chalk = require('chalk')
const ethers = require('ethers')
const { setup, getMinedTx, sleep, stringToBytes32, stringToBytes, bytesToString, Contract } = require('./utils')
let platform;

const genId = length => new Array(length).fill(0).map(() => Math.floor(36 * Math.random()).toString(36)).join('')
const genAddress = () => '0x' + new Array(40).fill(0).map(() => Math.floor(16 * Math.random()).toString(16)).join('')

const init = async () => {
    const data = await setup(artifacts, web3, 0)
    MatryxTournament = data.MatryxTournament
    MatryxRound = data.MatryxRound
    MatryxSubmission = data.MatryxSubmission
    wallet = data.wallet
    platform = data.platform
    token = data.token
}

const createTournament = async (_title, _category, bounty, roundData, accountNumber) => {
  const { platform } = await setup(artifacts, web3, accountNumber)

  let count = +await platform.tournamentCount()

  const category = stringToBytes(_category)
  const title = stringToBytes32(_title, 3)
  const descriptionHash = stringToBytes32('QmWmuZsJUdRdoFJYLsDBYUzm12edfW7NTv2CzAgaboj6ke', 2)
  const fileHash = stringToBytes32('QmeNv8oumYobEWKQsu4pQJfPfdKq9fexP2nh12quGjThRT', 2)
  const tournamentData = {
    category,
    title,
    descriptionHash,
    fileHash,
    initialBounty: bounty,
    entryFee: web3.toWei(2)
  }

  let tx = await platform.createTournament(tournamentData, roundData, { gasLimit: 8e6, gasPrice: 25 })
  await getMinedTx('Platform.createTournament', tx.hash)

  const address = await platform.allTournaments(count)
  const tournament = Contract(address, MatryxTournament, accountNumber)

  return tournament
}

const createSubmission = async (tournament, contribs, accountNumber) => {
  await setup(artifacts, web3, accountNumber)

  tAccount = tournament.accountNumber
  pAccount = platform.accountNumber

  tournament.accountNumber = accountNumber
  platform.accountNumber = accountNumber
  const account = tournament.wallet.address

  const isEntrant = await tournament.isEntrant(account)
  if (!isEntrant) {
    let { hash } = await platform.enterTournament(tournament.address, { gasLimit: 5e6 })
    await getMinedTx('Platform.enterTournament', hash)
  }

  const title = stringToBytes32('A submission ' + genId(6), 3)
  const descriptionHash = stringToBytes32('QmZVK8L7nFhbL9F1Ayv5NmieWAnHDm9J1AXeHh1A3EBDqK', 2)
  const fileHash = stringToBytes32('QmfFHfg4NEjhZYg8WWYAzzrPZrCMNDJwtnhh72rfq3ob8g', 2)

  const submissionData = {
    title,
    descriptionHash,
    fileHash,
    timeSubmitted: 0,
    timeUpdated: 0
  }

  const noContribsAndRefs = {
    contributors: new Array(0).fill(0).map(r => genAddress()),
    contributorRewardDistribution: new Array(0).fill(1),
    references: new Array(0).fill(0).map(r => genAddress())
  }

  const contribsAndRefs = {
    contributors: new Array(10).fill(0).map(r => genAddress()),
    contributorRewardDistribution: new Array(10).fill(1),
    references: new Array(10).fill(0).map(r => genAddress())
  }

  if (contribs) {
    let tx = await tournament.createSubmission(submissionData, contribsAndRefs, { gasLimit: 8e6 })
    await getMinedTx('Tournament.createSubmission', tx.hash)
  }
  else {
    let tx = await tournament.createSubmission(submissionData, noContribsAndRefs, { gasLimit: 8e6 })
    await getMinedTx('Tournament.createSubmission', tx.hash)
  }

  const [_, roundAddress] = await tournament.currentRound()
  const round = Contract(roundAddress, MatryxRound)
  const submissions = await round.getSubmissions()
  const submissionAddress = submissions[submissions.length-1]
  const submission = Contract(submissionAddress, MatryxSubmission, accountNumber)

  tournament.accountNumber = tAccount
  platform.accountNumber = pAccount


  return submission
}

const selectWinnersWhenInReview = async (tournament, winners, rewardDistribution, roundData, selectWinnerAction) => {
  const [_, roundAddress] = await tournament.currentRound()
  const round = Contract(roundAddress, MatryxRound, tournament.accountNumber)
  const roundEndTime = await round.getEndTime()

  let timeTilRoundInReview = roundEndTime - Date.now() / 1000
  timeTilRoundInReview = timeTilRoundInReview > 0 ? timeTilRoundInReview : 0

  await sleep(timeTilRoundInReview * 1000)

  const tx = await tournament.selectWinners([winners, rewardDistribution, selectWinnerAction, 0], roundData, { gasLimit: 5000000 })
  await getMinedTx('Tournament.selectWinners', tx.hash)
}

/*
 * Case 1
 */
contract('Multiple Winning Submissions with No Contribs or Refs and Close Tournament', function(accounts) {
    let t; //tournament
    let r; //round
    let s1; //submission 1
    let s2; //submission 2
    let s3; //submission 3

  it("Able to create Multiple Submissions with no Contributors and References", async function () {
      await init();
      roundData = {
          start: Math.floor(Date.now() / 1000),
          end: Math.floor(Date.now() / 1000) + 30,
          reviewPeriodDuration: 60,
          bounty: web3.toWei(5),
          closed: false
        }

      t = await createTournament('first tournament', 'math', web3.toWei(10), roundData, 0)
      let [_, roundAddress] = await t.currentRound()
      r = Contract(roundAddress, MatryxRound, 0)

      //Create submission with some contributors
      s1 = await createSubmission(t, false, 1)
      s2 = await createSubmission(t, false, 2)
      s3 = await createSubmission(t, false, 3)
      stime = Math.floor(Date.now() / 1000);
      assert.ok(s1.address, "Submission 1 is not valid.");
      assert.ok(s2.address, "Submission 2 is not valid.");
      assert.ok(s3.address, "Submission 3 is not valid.");
  });

  it("Able to choose multiple winners and close tournament", async function () {
      let submissions = await r.getSubmissions()
      await selectWinnersWhenInReview(t, submissions, submissions.map(s => 1), [0, 0, 0, 0, 0], 2)
      let r1 = await s1.myReward();
      let r2 = await s2.myReward();
      let r3 = await s3.myReward();
      let allEqual = [fromWei(r1), fromWei(r2), fromWei(r3)].every(x => x === (10/3))
      assert.isTrue(allEqual, "Bounty not distributed correctly among all winning submissions.")
  });

  it("Tournament should be closed", async function () {
      let state = await t.getState();
      assert.equal(state, 3, "Tournament is not Closed")
  });

  it("Round should be closed", async function () {
      let state = await r.getState();
      assert.equal(state, 5, "Round is not Closed")
  });

  it("Tournament and Round balance should now be 0", async function () {
      t.accountNumber = 0
      r.accountNumber = 0
      let tB = await t.getBalance()
      console.log(fromWei(tB))
      let rB = await r.getRoundBalance()
      console.log(fromWei(rB))
      assert.isTrue(fromWei(tB) == 0 && fromWei(rB) == 0, "Tournament and round balance should both be 0")
  });

});

/*
 * Case 2
 */
contract('Multiple Winning Submissions with Contribs and Refs and Close Tournament', function(accounts) {
  let t; //tournament
  let r; //round
  let s1; //submission 1
  let s2; //submission 2
  let s3; //submission 3

  it("Able to create Multiple Submissions with Contributors and References", async function () {
    await init();
    roundData = {
        start: Math.floor(Date.now() / 1000),
        end: Math.floor(Date.now() / 1000) + 30,
        reviewPeriodDuration: 60,
        bounty: web3.toWei(5),
        closed: false
      }

    t = await createTournament('first tournament', 'math', web3.toWei(10), roundData, 0)
    let [_, roundAddress] = await t.currentRound()
    r = Contract(roundAddress, MatryxRound, 0)

    //Create submission with some contributors
    s1 = await createSubmission(t, true, 1)
    s2 = await createSubmission(t, true, 2)
    s3 = await createSubmission(t, true, 3)
    stime = Math.floor(Date.now() / 1000);
    s1 = Contract(s1.address, MatryxSubmission, 1)
    s2 = Contract(s2.address, MatryxSubmission, 2)
    s3 = Contract(s3.address, MatryxSubmission, 3)

    //add accounts[3] as a new contributor to the first submission
    let modCon = {
      contributorsToAdd: [accounts[3]],
      contributorRewardDistribution: [1],
      contributorsToRemove: []
    }
    await s1.updateContributors(modCon);

    assert.ok(s1.address, "Submission 1 is not valid.");
    assert.ok(s2.address, "Submission 2 is not valid.");
    assert.ok(s3.address, "Submission 3 is not valid.");
  });

  it("Able to choose multiple winners and close tournament, winners get correct bounty allocation", async function () {
    let submissions = await r.getSubmissions()
    await selectWinnersWhenInReview(t, submissions, submissions.map(s => 1), [0, 0, 0, 0, 0], 2)
    s1.accountNumber = 1
    let r1 = await s1.myReward();
    s2.accountNumber = 2
    let r2 = await s2.myReward();
    s3.accountNumber = 3
    let r3 = await s3.myReward();
    console.log(fromWei(r1) + " " + fromWei(r2) + " "  + fromWei(r3))
    let allEqual = [fromWei(r1), fromWei(r2), fromWei(r3)].every(x => x === (5/3))
    assert.isTrue(allEqual, "Bounty not distributed correctly among all winning submissions.")
  });

  it("Remaining 50% of Bounty allocation distributed correctly to contributors", async function () {
      contribs = await s1.getContributors()
      c = contribs[contribs.length]

      //switch to accounts[3]
      s1.accountNumber = 3
      let myReward = await s1.myReward()
      //switch back to accounts[1]
      s1.accountNumber = 1
      assert.isTrue(fromWei(myReward) == ((5/3)/contribs.length), "Winnings should equal initial tournament bounty")
  });

  it("Tournament should be closed", async function () {
      let state = await t.getState();
      assert.equal(state, 3, "Tournament is not Closed")
  });

  it("Round should be closed", async function () {
      let state = await r.getState();
      assert.equal(state, 5, "Round is not Closed")
  });

  it("Tournament and Round balance should now be 0", async function () {
      let tB = await t.getBalance()
      let rB = await r.getRoundBalance()
      console.log(fromWei(rB))
      assert.isTrue(fromWei(tB) == 0 && fromWei(rB) == 0, "Tournament and round balance should both be 0")
  });

});


/*
 * Case 3
 */
contract('Multiple Winning Submissions with no Contribs or Refs and Start Next Round', function(accounts) {
  let t; //tournament
  let r; //round
  let s; //submission

});


/*
 * Case 4
 */
contract('Multiple Winning Submissions with Contribs and Refs and Start Next Round', function(accounts) {
  let t; //tournament
  let r; //round
  let s; //submission

});


/*
 * Case 5
 */
contract('Multiple Winning Submissions with no Contribs or Refs and Do Nothing', function(accounts) {
  let t; //tournament
  let r; //round
  let s; //submission

});


/*
 * Case 6
 */
contract('Multiple Winning Submissions with Contribs and Refs and Do Nothing', function(accounts) {
  let t; //tournament
  let r; //round
  let s; //submission

});