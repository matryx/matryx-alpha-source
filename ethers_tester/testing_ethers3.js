web3.eth.defaultAccount = web3.eth.accounts[0]
ethers = require('/Users/kenmiyachi/crypto/ethers.js'); // local ethers pull
wallet = new ethers.Wallet("0x73a6a9bc6ef17fadf3d3d7920b04282ee99ebd6a25db7489f3fe6589024d3a1f")
wallet.provider = new ethers.providers.JsonRpcProvider('http://localhost:8545')
web3.eth.sendTransaction({from: web3.eth.accounts[0], to: wallet.address, value: 30*10**18})
function stringToBytes32(text, requiredLength) {var data = ethers.utils.toUtf8Bytes(text); var l = data.length; var pad_length = 64 - (l*2 % 64); data = ethers.utils.hexlify(data);data = data + "0".repeat(pad_length);data = data.substring(2); data = data.match(/.{1,64}/g);data = data.map(v => "0x" + v); while(data.length < requiredLength) { data.push("0x0"); }return data;}

platform = new ethers.Contract(MatryxPlatform.address, MatryxPlatform.abi, wallet);

platform.createPeer({gasLimit: 4000000})
token = new ethers.Contract(MatryxToken.address, MatryxToken.abi, wallet);
token.setReleaseAgent(wallet.address)
token.releaseTokenTransfer({gasLimit: 1000000})
token.mint(wallet.address, "10000000000000000000000")
token.approve(MatryxPlatform.address, "100000000000000000000")

title = stringToBytes32("the title of the tournament", 3);
categoryHash = stringToBytes32("contentHash", 2);

tournamentData = { categoryHash: web3.sha3("math"), title_1: title[0], title_2: title[1], title_3: title[2], contentHash_1: categoryHash[0], contentHash_2: categoryHash[1], Bounty: "10000000000000000000", entryFee: "2000000000000000000"}

roundData = { start: 5, end: 5, reviewDuration: 5, bounty: "5000000000000000000"}
platform.createTournament("math", tournamentData, roundData, {gasLimit: 6500000})

platform.allTournaments(0).then((address) => { return t = web3.eth.contract(MatryxTournament.abi).at(address);})
r = web3.eth.contract(MatryxRound.abi).at(t.rounds(0))