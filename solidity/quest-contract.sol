pragma solidity ^0.4.18;

import "./safe_math.sol";
import "./owned.sol";

contract RoleInterface {
    function validateRole(address _user, bytes32 _role) public view returns (bool);
}

contract QuestContract is Owned {
    using SafeMath for uint;

    struct QuestData {
        bool isCompleted;
        string name;
        bytes32 role;
        uint reward;
        uint roleSharePerMillion;
        uint durationToCompleteQuest; // 0 for non-time limited quests
        uint takenTime; // 0 if quest has not been taken yet
    }

    uint public totalQuests;
    string public questsName;

    mapping (uint => QuestData) public quests;
    mapping (uint => address) private questToMaker;
    mapping (uint => address) private questToTaker;
    mapping (uint => string) private questToMetadata;
    mapping (address => uint) private takerToQuestCount;
    mapping (address => uint) private makerToQuestCount;

    event QuestCreated(address indexed maker, uint questId);
    event QuestTaken(address indexed taker, uint questId);
    event QuestReleased(address indexed taker, uint questId);
    event QuestRemoved(address indexed maker, uint questId);
    event QuestCompleted(address indexed maker, address indexed taker, uint questId);
    event QuestFailed(address indexed maker, address indexed taker, uint questId);

    RoleInterface private roleContract;

    constructor() public {
        questsName = "Arbitrated Quests";
        totalQuests = 0;
    }

    function setRoleContract(address _roleContract) public onlyOwner {
        roleContract = RoleInterface(_roleContract);
    }

    function getTotalActiveQuests() public view returns(uint) {
        return totalQuests - makerToQuestCount[address(0)];
    }

    function makerOf(uint _questId) public view returns (address) {
        return questToMaker[_questId];
    }

    function takerOf(uint _questId) public view returns (address) {
        return questToTaker[_questId];
    }

    function metadataOf(uint _questId) public view returns (string) {
        return questToMetadata[_questId];
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function getAllActiveQuests() external view returns (uint[]) {
        uint totalActiveQuests = getTotalActiveQuests();
        if (totalActiveQuests > 0) {
            uint256[] memory result = new uint[](totalActiveQuests);
            uint256 resultIndex = 0;
            uint256 i;
            for (i = 0; i < totalQuests; i++) {
                if (questToMaker[i] != 0) {
                    result[resultIndex] = i;
                    resultIndex++;
                }
            }

            return result;
        } else {
            return new uint[](0);
        }
    }

    function questsForMaker(address _maker) external view returns (uint[]) {
        uint256 questCount = makerToQuestCount[_maker];

        if (questCount > 0) {
            uint256[] memory result = new uint[](questCount);
            uint256 resultIndex = 0;
            uint256 i;
            for (i = 0; i < totalQuests; i++) {
                if (questToMaker[i] == msg.sender) {
                    result[resultIndex] = i;
                    resultIndex++;
                }
            }

            return result;
        } else {
            return new uint[](0);
        }
    }

    function questsForTaker(address _taker) external view returns (uint[]) {
        uint256 questCount = takerToQuestCount[_taker];

        if (questCount > 0) {
            uint256[] memory result = new uint[](questCount);
            uint256 resultIndex = 0;
            uint256 i;
            for (i = 0; i < totalQuests; i++) {
                if (questToTaker[i] == msg.sender) {
                    result[resultIndex] = i;
                    resultIndex++;
                }
            }

            return result;
        } else {
            return new uint[](0);
        }
    }

    function createQuest(
            address _taker,
            string _name,
            bytes32 _role,
            uint _roleSharePerMillion,
            uint _durationToCompleteQuest,
            string _metadata) public payable {
        require(makerToQuestCount[msg.sender] <= 100); // NOTE: max of 100 concurrent quests
        require(takerToQuestCount[_taker] <= 100); // NOTE: max of 100 concurrent quests
        require(_taker != msg.sender);
        require(msg.value > 1000000);
        require(_roleSharePerMillion < 1000000);

        QuestData memory newQuestData = QuestData (false, _name, _role, msg.value, _roleSharePerMillion, _durationToCompleteQuest, now);

        makerToQuestCount[msg.sender] = makerToQuestCount[msg.sender].add(1);
        takerToQuestCount[_taker] = takerToQuestCount[_taker].add(1);

        uint questId = totalQuests;
        quests[questId] = newQuestData;
        questToMaker[questId] = msg.sender;
        questToTaker[questId] = _taker;
        questToMetadata[questId] = _metadata;
        totalQuests++;

        emit QuestCreated(msg.sender, questId);
        emit QuestTaken(_taker, questId);
    }

    function removeTakerFromQuest(address _taker, uint _questId) private {
        assert(questToTaker[_questId] == _taker);

        questToTaker[_questId] = address(0);
        takerToQuestCount[_taker] = takerToQuestCount[_taker].sub(1);
        takerToQuestCount[address(0)] = takerToQuestCount[address(0)].add(1);

        if (questToMaker[_questId] != address(0)) {
            emit QuestReleased(_taker, _questId);
        }
    }

    function removeMakerFromQuest(address _maker, uint _questId) private {
        assert(questToMaker[_questId] == _maker);

        questToMaker[_questId] = address(0);
        makerToQuestCount[_maker] = makerToQuestCount[_maker].sub(1);
        makerToQuestCount[address(0)] = makerToQuestCount[address(0)].add(1);

        emit QuestRemoved(_maker, _questId);
    }

    function recoverFailedQuest(uint _questId) public {
        require(questToMaker[_questId] == msg.sender);
        address taker = questToTaker[_questId];
        require(taker != address(0));
        require(isQuestFailed(_questId));

        QuestData storage quest = quests[_questId];

        removeMakerFromQuest(msg.sender, _questId);
        removeTakerFromQuest(taker, _questId); // TODO: penalty for failed quest?

        msg.sender.transfer(quest.reward);

        emit QuestFailed(msg.sender, taker, _questId);
    }

    function isQuestFailed(uint _questId) public view returns (bool) {
        QuestData storage quest = quests[_questId];
        return !quest.isCompleted && quest.durationToCompleteQuest > 0
            && (quest.durationToCompleteQuest + quest.takenTime > now);
    }

    // NOTE: for use externally to view reward amounts
    function getRoleReward(uint _questId) public view returns (uint) {
        QuestData storage quest = quests[_questId];
        return quest.reward.div(1000000).mul(quest.roleSharePerMillion);
    }

    // NOTE: for use externally to view reward amounts
    function getTakerReward(uint _questId) public view returns (uint) {
        QuestData storage quest = quests[_questId];
        return quest.reward.sub(getRoleReward(_questId));
    }

    function validateQuestCompletion(uint _questId, address _taker) public returns (bool) {
        QuestData storage quest = quests[_questId];
        require(!quest.isCompleted && !isQuestFailed(_questId));
        require(questToTaker[_questId] == _taker);
        require(msg.sender != _taker);

        if (roleContract.validateRole(msg.sender, quest.role)) {
            quest.isCompleted = true;

            address maker = questToMaker[_questId];

            removeMakerFromQuest(maker, _questId);
            removeTakerFromQuest(_taker, _questId);

            uint roleReward = quest.reward.div(1000000).mul(quest.roleSharePerMillion);
            uint takerReward = quest.reward.sub(roleReward);

            msg.sender.transfer(roleReward);
            _taker.transfer(takerReward);

            emit QuestCompleted(maker, _taker, _questId);

            return true;
        } else {
            return false;
        }
    }
}
