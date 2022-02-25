//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface NftMarketplace {
    function getPrice(address nftContract, uint nftId) external returns (uint price);
    function buy(address nftContract, uint nftId) external payable returns (bool success);
}

contract CollectorDAO {
    address public owner;
    string public constant name = "CollectorDAO Governor";
    uint256 private constant _MEMBERSHIP_COST = 1 ether;
    uint256 private constant QUORUMVOTES = 25;
    uint public constant VOTINGPERIOD = 7 days; // 1 week
   
    uint256 proposalCount;
    uint256 memberCount;
    mapping (uint => Proposal) public proposals;
    mapping (address => bool) public members;
    mapping (address => uint) public memberContributions;
    mapping (address => uint) public recentProposalId;
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets; 
        uint[] values; 
        string[] signatures; 
        bytes[] calldatas;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        uint abstainVotes;
        bool canceled;
        bool executed;
        mapping (address => Voter) voter;
    }

    struct Voter {
        bool hasVoted;
        uint support;
    }
    
    enum ProposalState {
        Active,
        Canceled,
        Defeated,
        Queued,
        Executed
    }

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier isMember(){
        require(members[msg.sender], "Must be a member");
        _;
    }


    constructor(){
        owner = msg.sender;

    }


    function quorumVotes() public view returns (uint) {
        return (memberCount * QUORUMVOTES) / 100; 
    }


    // @Dev This hashes the proposal (see OZ Gov contract)
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        bytes32 description
    ) internal pure returns (uint256){
            return uint256(keccak256(abi.encode(targets, values, signatures, calldatas, description)));
    }
    // @Dev Once votes pass, proposal is automatically queued for execution
    function state(uint proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.timestamp <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return ProposalState.Defeated;
        }  else if (proposal.executed) {
            return ProposalState.Executed;
        } else {
            return ProposalState.Queued;
        }
    }

    // @Dev All proposals voting lasts for 7 days
    function propose(address[] memory _targets, uint[] memory _values, string[] memory _signatures, bytes[] memory _calldatas, string memory _description) external isMember returns (uint){
        require(members[msg.sender], "Must be a member");
        require(_targets.length == _values.length && _targets.length == _signatures.length && _targets.length == _calldatas.length, "Information length does not match");
        require(_targets.length != 0, "Must provide targets");
        
        uint256 proposalid = hashProposal(_targets, _values, _signatures, _calldatas, keccak256(bytes(_description)));
        Proposal storage proposal = proposals[proposalid];
        uint startBlock = block.timestamp;
        uint endBlock = startBlock + VOTINGPERIOD;

        proposal.id = proposalid;
        proposal.proposer = msg.sender;
        proposal.targets = _targets;
        proposal.values = _values;
        proposal.signatures = _signatures;
        proposal.calldatas = _calldatas;
        proposal.startBlock = startBlock;
        proposal.endBlock = endBlock;

        recentProposalId[msg.sender] = proposalid;
        emit ProposalCreated(proposal.id, msg.sender, _targets, _values, _signatures, _calldatas, startBlock, endBlock, _description);
        return proposal.id;

    }


    /**
      * @notice Executes a queued proposal. Can execute once proposal succeeds
      * @param proposalId The id of the proposal to execute
      */
    function executeProposal(uint proposalId) external isMember {
        require(state(proposalId) == ProposalState.Queued, "proposal can only be executed if it is queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
     
            _execute(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i]);
            
        }
        emit ProposalExecuted(proposalId);
    }

    function _execute(address target, uint value, string memory signature, bytes memory data) public payable returns (bytes memory) {
        bytes memory callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Transaction execution reverted");
        return returnData;
    }


    function vote(uint proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) internal {
        require(state(proposalId) == ProposalState.Active, "voting is closed");
        require(support <= 2, "invalid vote type");
        
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainIdInternal(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "invalid signature");
        
        Proposal storage proposal = proposals[proposalId];
        Voter storage voter = proposal.voter[signer];

        require(!voter.hasVoted, "voter already voted");

        if (support == 0) {
            proposal.againstVotes++;
        } else if (support == 1) {
            proposal.forVotes++;
        } else if (support == 2) {
            proposal.abstainVotes++;
        }

        voter.hasVoted = true;
        voter.support = support;
        
        
        emit VoteSubmitted(signer, proposalId, support);
    }


    function cancel(uint proposalId) external {
        require(state(proposalId) != ProposalState.Executed, "cannot cancel executed proposal");

        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposer == msg.sender, "Only creator of this proposal can cancel");
        require((proposal.againstVotes + proposal.forVotes + proposal.abstainVotes) < 1, "Proposal cannot be cancelled, users have already voted");
        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function purchaseNFTFromMarketplace(NftMarketplace marketplace, address _nftContract, uint _nftId, uint _priceCap) external lock {
        uint price = marketplace.getPrice(_nftContract, _nftId);
        require(price <= _priceCap, "Price is above stated price cap");
        (bool success) = marketplace.buy{ value: price }(_nftContract, _nftId);
        require(success, 'Purchase failed');

    }


    function purchaseMembership() external payable {
        require(msg.value >= _MEMBERSHIP_COST, "Please pay 1 eth");
        require(!members[msg.sender], "Already a member");
        members[msg.sender] = true;
        memberCount++;
        memberContributions[msg.sender] += msg.value;
    }

    function getChainIdInternal() internal view returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    // @Dev submits bulk signed votes
    function submitBulkVotes(
        uint256[] calldata proposalList,
        uint8[] calldata supportList,
        uint8[] calldata vList,
        bytes32[] calldata rList,
        bytes32[] calldata sList
    ) public {
        require(proposalList.length == supportList.length, "Information length does not match");
        require(proposalList.length == vList.length, "Information length does not match");
        require(proposalList.length == rList.length, "Information length does not match");
        require(proposalList.length == sList.length, "Information length does not match");

        for (uint256 i = 0; i < proposalList.length; i++) {
            vote(proposalList[i], supportList[i], vList[i], rList[i], sList[i]);
        }
    }

    function getVoteStatus(uint256 proposalId, address _voter) external view returns (Voter memory voter) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.voter[_voter];
    }

    event ProposalCreated(uint id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);
    event ProposalExecuted(uint id);
    event VoteSubmitted(address signer, uint proposalId, uint support);
    event ProposalCanceled(uint proposalId);
}