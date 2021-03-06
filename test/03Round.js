const { shouldFail } = require('openzeppelin-test-helpers')

const { now } = require('../truffle/utils')
const { init, createTournament, createSubmission, waitUntilInReview, waitUntilClose, selectWinnersWhenInReview, enterTournament } = require('./helpers')(artifacts, web3)
const { accounts } = require('../truffle/network')

let platform

contract('NotYetOpen Round Testing', function() {
  let t //tournament
  let roundData

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: await now() + 80,
      duration: 3600,
      review: 60,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Able to get round details', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let { start, duration, review, bounty } = await t.getRoundDetails(roundIndex)
    assert.equal(start, roundData.start, 'Incorrect round start')
    assert.equal(duration, roundData.duration, 'Incorrect round duration')
    assert.equal(review, roundData.review, 'Incorrect round review')
    assert.equal(bounty, roundData.bounty, 'Incorrect round bounty')
  })

  it('Round state is Not Yet Open', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(state, 0, 'Round State should be NotYetOpen')
  })

  it('Round should not have any submissions', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let { submissions } = await t.getRoundInfo(roundIndex)
    assert.equal(submissions.length, 0, 'Round should not have submissions')
  })

  it('Able to add bounty to a round', async function() {
    await t.transferToRound(web3.toWei(1))
    let roundIndex = await t.getCurrentRoundIndex()
    let { bounty } = await t.getRoundDetails(roundIndex)
    assert.equal(fromWei(bounty), 6, 'Bounty was not added')
  })

  it('Unable to transfer to round more funds than are available', async function() {
    let tx = t.transferToRound(web3.toWei(100))
    await shouldFail.reverting(tx)
  })

  it('Able to enter tournament with Not Yet Open round', async function() {
    await enterTournament(t, 2)
    let isEnt = await t.isEntrant(accounts[2])
    assert.isTrue(isEnt, 'Could not enter tournament')
  })

  it('Able to edit a Not Yet Open round', async function() {
    roundData = {
      start: 1,
      duration: 3601,
      review: 40,
      bounty: web3.toWei(1)
    }

    await t.updateNextRound(roundData)
    let roundIndex = await t.getCurrentRoundIndex()
    let { start, duration, review, bounty } = await t.getRoundDetails(roundIndex)

    assert.isTrue(start != 1, 'Start not updated correctly')
    assert.equal(duration, 3601, 'Duration not updated correctly')
    assert.equal(review, 40, 'Review period not updated correctly')
    assert.equal(fromWei(bounty), 1, 'Bounty not updated correctly')
  })
})

contract('Open Round Testing', function() {
  let t //tournament

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 60,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Able to create a tournament with a Open round', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)

    assert.equal(roundIndex, 0, 'Round is not valid.')
    assert.equal(state, 2, 'Round State should be Open')
  })

  it('Able to enter the tournament and make submissions', async function() {
    // Create submission
    let sHash = await createSubmission(t, '0x00', toWei(1), 1)
    sHash = await platform.isSubmission(sHash)

    assert.isTrue(sHash, 'Unable to make submissions')
  })

  it('Number of submissions should be 2', async function() {
    await createSubmission(t, '0x00', toWei(1), 1)
    await createSubmission(t, '0x00', toWei(1), 1)

    let roundIndex = await t.getCurrentRoundIndex()
    let { submissions } = await t.getRoundInfo(roundIndex)
    assert.equal(submissions.length, 2, 'Number of Submissions should be 2')
  })

  it('Unable to start next round during open round', async function() {
    let tx = t.startNextRound()
    await shouldFail.reverting(tx)
  })

  it('Unable to close tournament during open round', async function() {
    let tx = t.closeTournament()
    await shouldFail.reverting(tx)
  })

})

contract('In Review Round Testing', function() {
  let t //tournament

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 60,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    //Create submission
    await createSubmission(t, '0x00', toWei(1), 1)
    await waitUntilInReview(t, roundIndex)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Able to create a round In Review', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(state, 3, 'Round State should be In Review')
  })

  it('Able to allocate more tournament bounty to a round in review', async function() {
    await t.transferToRound(web3.toWei(1))
    let roundIndex = await t.getCurrentRoundIndex()
    let { bounty } = await t.getRoundDetails(roundIndex)
    assert.equal(fromWei(bounty), 6, 'Incorrect round balance')
  })

  it('Able to enter round in review', async function() {
    let isEnt = await enterTournament(t, 3)
    assert.isTrue(isEnt, 'Could not enter tournament')
  })

  it('Unable to make submissions while the round is in review', async function() {
    try {
      await createSubmission(t, '0x00', toWei(1), 1)
      assert.fail('Expected revert not received')
    } catch (error) {
      let revertFound = error.message.search('revert') >= 0
      assert(revertFound, 'Should not have been able to make a submission while In Review')
    }
  })
})

contract('Closed Round Testing', function() {
  let t //tournament
  let s //submission

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 60,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)

    // Create submissions
    s = await createSubmission(t, '0x00', toWei(1), 1)
    let roundIndex = await t.getCurrentRoundIndex()
    let { submissions } = await t.getRoundInfo(roundIndex)
    await selectWinnersWhenInReview(t, submissions, [1], [0, 0, 0, 0], 2)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Tournament should be closed', async function() {
    let state = await t.getState()
    assert.equal(+state, 3, 'Tournament is not Closed')
  })

  it('Unable to allocate more tournament bounty to a closed round', async function() {
    let tx = t.transferToRound(web3.toWei(1))
    await shouldFail.reverting(tx)
  })

  it('Unable to enter closed tournament', async function() {
    try {
      await enterTournament(t, 2)
      assert.fail('Expected revert not received')
    } catch (error) {
      let revertFound = error.message.search('revert') >= 0
      assert(revertFound, 'Should not have been able to add bounty to Closed round')
    }
  })

  it('Unable to make submissions while the round is closed', async function() {
    try {
      await createSubmission(t, '0x00', toWei(1), 1)
      assert.fail('Expected revert not received')
    } catch (error) {
      let revertFound = error.message.search('revert') >= 0
      assert(revertFound, 'Should not have been able to make a submission while In Review')
    }
  })
})

contract('Abandoned Round Testing', function() {
  let t //tournament

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 1,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    assert.equal(roundIndex, 0, 'Round is not valid.')

    // Create a submission
    s = await createSubmission(t, '0x00', toWei(1), 1)
    s = await createSubmission(t, '0x00', toWei(1), 2)

    // Wait for the round to become Abandoned
    await waitUntilClose(t, roundIndex)

  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Round state is Abandoned', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(+state, 6, 'Round State should be Abandoned')
  })

  it('Tournament state is Abandoned', async function() {
    let state = await t.getState()
    assert.equal(+state, 4, 'Tournament State should be Abandoned')
  })

  it('Unable to add bounty to Abandoned round', async function() {
    let tx = t.transferToRound(web3.toWei(1))
    await shouldFail.reverting(tx)
  })

  it('Round is still open in round data before the first withdrawal', async function () {
    let roundIndex = await t.getCurrentRoundIndex()
    let { closed } = await t.getRoundInfo(roundIndex)
    assert.isFalse(closed, 'Round should still be set as open')
  })

  it('First entrant is able to withdraw their share from the bounty from an abandoned round', async function() {
    // Switch to acounts[1]
    t.accountNumber = 1
    await t.withdrawFromAbandoned()
    let isEnt = await t.isEntrant(accounts[1])
    assert.isFalse(isEnt, 'Should no longer be an entrant')
  })

  it('Second entrant also able to withdraw their share', async function() {
    t.accountNumber = 1
    await t.withdrawFromAbandoned()
    t.accountNumber = 2
    await t.withdrawFromAbandoned()
    let isEnt = await t.isEntrant(accounts[2])
    assert.isFalse(isEnt, 'Should no longer be an entrant')
  })

  it('Unable to withdraw from tournament multiple times from the same account', async function() {
    t.accountNumber = 1
    await t.withdrawFromAbandoned()
    let tx = t.withdrawFromAbandoned()
    await shouldFail.reverting(tx)
    t.accountNumber = 0
  })

  it('Tournament balance is 0', async function() {
    t.accountNumber = 1
    await t.withdrawFromAbandoned()
    t.accountNumber = 2
    await t.withdrawFromAbandoned()
    let tB = await t.getBalance().then(fromWei)
    assert.equal(fromWei(tB), 0, 'Tournament balance should be 0')
  })

})

contract('Abandoned Round due to No Submissions', function() {
  let t //tournament

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 1,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    // Wait for the round to become Abandoned
    await waitUntilClose(t, roundIndex)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Round state is Abandoned', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(+state, 6, 'Round State should be Abandoned')
  })

  it('Able to recover funds', async function() {
    await t.recoverBounty()
    let tB = await t.getBalance().then(fromWei)
    assert.equal(fromWei(tB), 0, 'Tournament balance should be 0')
  })

  it('Unable to recover funds multiple times', async function() {
    await t.recoverBounty()
    let tx = t.recoverBounty()
    await shouldFail.reverting(tx)
  })

})

contract('Unfunded Round Testing', function() {
  let t //tournament
  let token

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 20,
      bounty: web3.toWei(10)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    let s = await createSubmission(t, '0x00', toWei(1), 1)

    await selectWinnersWhenInReview(t, [s], [1], [0, 0, 0, 0], 0)
    await waitUntilClose(t, roundIndex)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Round should be Unfunded', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(state, 1, 'Round is not Unfunded')
  })

  it('Bounty of unfunded round is 0', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let { bounty } = await t.getRoundDetails(roundIndex)
    assert.equal(bounty, 0, 'Round bounty should be 0')
  })

  it('Balance of tournament is 0', async function() {
    let tB = await t.getBalance().then(fromWei)
    assert.equal(tB, 0, 'Tournament balance should be 0')
  })

  it('Round should not have any submissions', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let { submissions } = await t.getRoundInfo(roundIndex)
    assert.equal(submissions.length, 0, 'Round should not have submissions')
  })

  it('Unable to make submissions while the round is Unfunded', async function() {
    try {
      await createSubmission(t, '0x00', toWei(1), 1)
      assert.fail('Expected revert not received')
    } catch (error) {
      let revertFound = error.message.search('revert') >= 0
      assert(revertFound, 'Should not have been able to make a submission while round is Unfunded')
    }
  })

  it('Able to transfer more MTX to the tournament', async function () {
    await t.addToBounty(toWei(2))
    let tB = await t.getBalance().then(fromWei)
    assert.equal(tB, 2, 'Funds not transferred')
  })

  it('Able to transfer tournament funds to the Unfunded round', async function() {
    await t.addToBounty(toWei(2))
    await t.transferToRound(toWei(2))
    let roundIndex = await t.getCurrentRoundIndex()
    let { bounty } = await t.getRoundDetails(roundIndex)
    assert.equal(fromWei(bounty), 2, 'Funds not transferred')
  })

  it('Round should now be Open', async function() {
    await t.addToBounty(toWei(2))
    await t.transferToRound(toWei(2))
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(state, 2, 'Round is not Open')
  })
})

contract('Ghost Round Testing', function() {
  let t //tournament
  let s //submission

  before(async () => {
    platform = (await init()).platform
    roundData = {
      start: 0,
      duration: 3600,
      review: 30,
      bounty: toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(20), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    assert.equal(roundIndex, 0, 'Round is not valid.')

    s = await createSubmission(t, '0x00', toWei(1), 1)
    let { submissions } = await t.getRoundInfo(roundIndex)
    await selectWinnersWhenInReview(t, submissions, submissions.map(s => 1), [0, 0, 0, 0], 0)
  })

  beforeEach(async () => {
    snapshot = await network.provider.send("evm_snapshot", [])
    platform.accountNumber = 0
  })

  // reset accounts
  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshot])
    t.accountNumber = 0
  })

  it('Tournament should be Open', async function() {
    let state = await t.getState()
    assert.equal(state, 2, 'Tournament is not Open')
  })

  it('Round state should be Has Winners', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let state = await t.getRoundState(roundIndex)
    assert.equal(state, 4, 'Round should be in Has Winners state')
  })

  it('Ghost round details are correct', async function() {
    let roundIndex = await t.getCurrentRoundIndex()
    let { review, bounty } = await t.getRoundDetails(roundIndex + 1)
    assert.equal(review, 30, 'Incorrect ghost round review period')
    assert.equal(fromWei(bounty), 5, 'Incorrect ghost round bounty')
  })

  it('Able to edit ghost round, review period duration updated correctly', async function() {
    roundData = {
      start: await now() + 60,
      duration: 3600,
      review: 40,
      bounty: web3.toWei(5)
    }

    await t.updateNextRound(roundData)
    let roundIndex = await t.getCurrentRoundIndex()
    let { review, bounty } = await t.getRoundDetails(roundIndex + 1)

    assert.equal(review, 40, 'Review period duration not updated correctly')
    assert.equal(fromWei(bounty), 5, 'Incorrect ghost round bounty')
  })

  // Able to edit ghost round and increase funds
  it('Able to edit ghost round increasing its bounty', async function() {
    roundData = {
      start: await now() + 60,
      duration: 3600,
      review: 40,
      bounty: web3.toWei(8)
    }

    await t.updateNextRound(roundData)
    let roundIndex = await t.getCurrentRoundIndex()
    let { review, bounty  } = await t.getRoundDetails(roundIndex + 1)

    assert.equal(review, 40, 'Ghost Round not updated correctly')
    assert.equal(fromWei(bounty), 8, 'Incorrect ghost round bounty')
  })

  // Able to edit ghost round and decrease funds
  it('Able to edit ghost round decreasing its bounty', async function() {
    roundData = {
      start: await now() + 60,
      duration: 3600,
      review: 50,
      bounty: web3.toWei(2)
    }

    await t.updateNextRound(roundData)
    let roundIndex = await t.getCurrentRoundIndex()
    let { review, bounty } = await t.getRoundDetails(roundIndex + 1)

    assert.equal(review, 50, 'Ghost Round review not updated correctly')
    assert.equal(fromWei(bounty), 2, 'Incorrect ghost round bounty')
  })
})

contract('Round Timing Restrictions Testing', function() {
  let t //tournament

  it('Able to create a round with duration: 1 day', async function() {
    await init()
    roundData = {
      start: 0,
      duration: 86400,
      review: 5,
      bounty: web3.toWei(5)
    }
    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    assert.equal(roundIndex, 0, 'Round is not valid.')
  })

  it('Able to create a round with duration: 1 year', async function() {
    roundData = {
      start: 0,
      duration: 31536000,
      review: 5,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let roundIndex = await t.getCurrentRoundIndex()

    assert.equal(roundIndex, 0, 'Round is not valid.')
  })

  it('Unable to create a round with duration: 1 year + 1 second', async function() {
    roundData = {
      start: 0,
      duration: 31536001,
      review: 5,
      bounty: web3.toWei(5)
    }

    try {
      t.accountNumber = 1
      await createTournament('tournament', web3.toWei(10), roundData, 0)
      assert.fail('Expected revert not received')
    } catch (error) {
      let revertFound = error.message.search('revert') >= 0
      assert(revertFound, 'Should not have been able to create the round')
    }
  })

/*
  it('Able to create a round review period duration: 1 year', async function() {
    roundData = {
      start: 0,
      duration: 10,
      review: 31536000,
      bounty: web3.toWei(5)
    }

    t = await createTournament('tournament', web3.toWei(10), roundData, 0)
    let [, roundAddress] = await t.getCurrentRound()
    r = Contract(roundAddress, IMatryxRound, 0)

    assert.ok(r.address, 'Round not created successfully.')
  })

  it('Unable to create a round with duration: 1 year + 1 second', async function() {
    roundData = {
      start: 0,
      duration: 10,
      review: 31536001,
      bounty: web3.toWei(5)
    }

    try {
      t.accountNumber = 1
      await createTournament('tournament', web3.toWei(10), roundData, 0)
      assert.fail('Expected revert not received')
    } catch (error) {
      let revertFound = error.message.search('revert') >= 0
      assert(revertFound, 'Should not have been able to create the round')
    }
  })
*/
})

