// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.7.0;


interface TwoSubmission{
	
	function missionID(address _crowdUR,int[] memory _missionID,uint _imageNum) external returns(bool);
	function presubmit(address _submitter, bytes32 _sealedMessage,address[] memory _addrs)external returns(bool);
	function submit(address _submitter, int[] memory _message ,uint _randomKey) external returns(bool);
	function evaluation(address[]memory _addrs,uint[]memory _workIDToRightNum,int[] memory _rightTable, uint _submitNum)external returns(uint [] memory,int[] memory);
    function evaluation2(address[] memory _addrs, int[] memory _rightTable, uint _submitNum) external returns(int[] memory);
	function evaluation2_cal(address[] memory _addrs, uint[] memory _workIDToRightNum, int[] memory _rightTable)external view returns(uint[] memory);
	function resetCSData() external returns(bool);
	function resetURData(address _crowdUR) external returns(bool);
}

contract CSManagement {

	TwoSubmission public myTwoSubmisson;
	
	constructor(address _TwoAddrs) {
		myTwoSubmisson = TwoSubmission(_TwoAddrs);
		require(myTwoSubmisson.resetCSData(),"ts");
	}

    enum State {Fresh, Init, Ready, Submited, Failed,Stagnant, Completed}

	struct timeInfo{

		uint EnrollTime;
		uint AcceptTime;
		uint PreSubmitTime;
		uint SubmitTime;
		uint WithdrawTime;
		uint SortitionTime;
		uint StartTime;
		uint CheckTime;
		uint EvaluationTime;
    }
    mapping(address => timeInfo) public CSToTime;
    
    struct timeEndInfo{
		uint  PreEnrollTimeEnd;
		uint  EnrollTimeEnd;
		uint  SortitionEnd;
		uint  AcceptTimeEnd;
		uint  StartTimeEnd;
		uint  PreSubmitTimeEnd;
		uint  SubmitTimeEnd;
		uint  CheckTimeEnd;
		uint  EvaluationTimeEnd;
		uint  URWithdrawEnd;
		uint  UTWithdrawEnd;
	}
	mapping(address => timeEndInfo) public CSToTimeEnd;

	struct numberInfo {
		uint ImageNumber;
		uint CrowdURNumMax;
		uint CrowdURNumMin;
		uint SubmitNum;
		uint CleanedNum;
	}
	mapping(address => numberInfo) public CSToNumber;
	struct feeInfo {

		uint  UTPrepayment;
		uint  ShareFee;
		uint  RewardFee;
		uint EnrollFee;
		uint  CommFee;
	}
	mapping(address => feeInfo) public CSToFee;

	struct textInfo {
		string Introduction;
		string Detail;
	}
	mapping(address => textInfo) public CSToText;

	struct contractInfo {
		bool URchecked;
		bool CSInit;
		address crowdUT;
		State CState;
		uint [] workIDToRightNumber;//可以考虑放到TS里边去
		int [] rightTableArray;//同上
		mapping(uint => int[]) workIDToMissionID;
	}
	mapping(address => contractInfo) public CSDataInfo;

	struct crowdUTInfo{
		bool setMissionID;
		bool sorted;
		bool startMission;
		bool checkSubmited;
		bool evaluated;
		// bool cleaned;
		uint balance;
	}
	mapping(address => crowdUTInfo) public CrowdUT;

    struct CrowdURAccount {
        bool accepted;
        bool presubmited;
        bool submited;
        // bool cleaned;
        uint balance;
        uint workID;
        address CSContract;
    }
    mapping(address => CrowdURAccount) public CrowdURs;
	mapping(address => address[]) public  CSToCommittee;

	event LogCStateModified(address indexed _CSContract, address indexed _who, uint _time, State _newstate);
	event LogURPreSubmited(address indexed _CSContract, address indexed _who, uint _time, bytes32 _sealedMessage);
	event LogURSubmited(address indexed _CSContract, address indexed _who, uint _time,int[] _message);

	modifier checkState(State _state) {
		require(CSDataInfo[msg.sender].CState == _state,"Wrong State");
		_;
	}

	//不必检测是不是哪一个CSC的，因为只可能参与一个CSC,那他去别人家那块瞎搞呢？还得检查属于哪一个
	modifier checkIsCommiittee(address _crowdUR) {
		require(CrowdURs[_crowdUR].CSContract == msg.sender,"Not CC");
		_;
	}

	modifier checkTimeIn(uint _endTime) {
		require(block.timestamp < _endTime,"Out of time!");
		_;
	}

	modifier checkTimeOut(uint _endTime) {
		require(block.timestamp > _endTime,"Too early!");
		_;
	}

	function initCrowdUT(address _crowdUT) external checkState(State.Fresh) returns(bool){
		CSDataInfo[msg.sender].crowdUT = _crowdUT;
		CSDataInfo[msg.sender].CSInit = true;
		return true;
	}

	function setImageNum(uint _imageNum)
		external
		checkState(State.Fresh)
		returns(bool)
	{
		//uint 用>0检测不好用，比如传进-1，不会报错，会变成很大数字
		require(_imageNum > 0);

		CSToNumber[msg.sender].ImageNumber = _imageNum;
		return true;
	}

	function setCCNnum(uint _URNumMax, uint _URNumMin)
		external
		checkState(State.Fresh)
		returns(bool)
	{
		require(_URNumMax > 0);
		require(_URNumMin > 0);

		CSToNumber[msg.sender].CrowdURNumMax = _URNumMax;
		CSToNumber[msg.sender].CrowdURNumMin = _URNumMin;
		return true;
	}

	function setFee(uint _rewardFee, uint _enrollFee,uint _deposit)
		external
		checkState(State.Fresh)
		returns(uint,uint,uint)
	{
		require(_rewardFee > 0);
		require(_deposit > 0);
		require(_enrollFee > 0);
		require(CSToNumber[msg.sender].ImageNumber > 0,"NO ImageNumber");
		require(CSToNumber[msg.sender].CrowdURNumMax > 0);

		uint oneUnit = 1 gwei;
		CSToFee[msg.sender].RewardFee = _rewardFee * oneUnit;
		CSToFee[msg.sender].EnrollFee = _enrollFee * oneUnit;
		CSToFee[msg.sender].CommFee = _deposit * oneUnit;

		return (CSToFee[msg.sender].RewardFee,CSToFee[msg.sender].CommFee, CSToFee[msg.sender].CommFee);
	}

	function setCTTime(uint _enrollTime, uint _sortTime,uint _acceptTime, uint _startTime)
		external 
		checkState(State.Fresh)
		returns(uint) 
	{
		uint oneUnit = 1 minutes;
		CSToTime[msg.sender].EnrollTime = _enrollTime * oneUnit;
		CSToTime[msg.sender].SortitionTime = _sortTime * oneUnit;
		CSToTime[msg.sender].AcceptTime = _acceptTime * oneUnit;
		CSToTime[msg.sender].StartTime = _startTime * oneUnit;

		return CSToTime[msg.sender].EnrollTime;
	}

	function setPTTime(uint _presubmitTime, uint _submitTime, uint _evaluationTime, uint _withdrawTime)
		external
		checkState(State.Fresh) 
		returns(bool)
	{
		uint oneUnit = 1 minutes;

		CSToTime[msg.sender].PreSubmitTime = _presubmitTime * oneUnit;
		CSToTime[msg.sender].SubmitTime = _submitTime * oneUnit;
		CSToTime[msg.sender].EvaluationTime = _evaluationTime * oneUnit;
		CSToTime[msg.sender].WithdrawTime = _withdrawTime * oneUnit;
		return true;
	}
/*
	function setURTimeParas(uint _enrollTime,uint _acceptTime,uint _presubmitTime, uint _submitTime,uint _withdrawTime)
		external
		checkState(State.Fresh)
		returns(uint)
	{
	    uint oneUnit = 1 minutes;

		CSToTime[msg.sender].EnrollTime = _enrollTime * oneUnit;
		CSToTime[msg.sender].AcceptTime = _acceptTime * oneUnit;
		CSToTime[msg.sender].PreSubmitTime = _presubmitTime * oneUnit;
		CSToTime[msg.sender].SubmitTime = _submitTime * oneUnit;
		CSToTime[msg.sender].WithdrawTime = _withdrawTime * oneUnit;
		return CSToTime[msg.sender].EnrollTime;
	}

	function setUTTimeParas(uint _sortTime, uint _startTime,uint _checkTime,uint _evaluationTime, uint _CleanTime)
		external
		checkState(State.Fresh)
		returns(bool)
	{
	    uint oneUnit = 1 seconds;

	    CSToTime[msg.sender].SortitionTime = _sortTime * oneUnit;
		CSToTime[msg.sender].StartTime = _startTime * oneUnit;
		CSToTime[msg.sender].CheckTime = _checkTime * oneUnit;
		CSToTime[msg.sender].EvaluationTime = _evaluationTime * oneUnit;
		CSToTime[msg.sender].CleanTime = _CleanTime * oneUnit;
		return true;
	}
*/
	function recruit(string memory _introduction)
		external
		checkState(State.Fresh)
		returns(uint,uint,uint)
	{
		// 设置整个CS活动周期的时间
		require(CSToTime[msg.sender].EnrollTime > 0,"EnrollTime == 0");
		require(CSToTime[msg.sender].AcceptTime > 0,"AcceptTime == 0");
		require(CSToTime[msg.sender].PreSubmitTime > 0,"PreSubmitTime == 0");
		require(CSToTime[msg.sender].SubmitTime > 0," SubmitTime== 0");
		require(CSToTime[msg.sender].WithdrawTime > 0,"WithdrawTime == 0");
		require(CSToTime[msg.sender].SortitionTime > 0,"SortitionTime == 0");
		require(CSToTime[msg.sender].StartTime > 0," StartTime== 0");
		require(CSToTime[msg.sender].EvaluationTime > 0,"EvaluationTime == 0");

		require(cleanCSM(),"Havn't Clean");//检查CS Data是否Clean,(新建 or 已清除)。

		CSToText[msg.sender].Introduction = _introduction;

		CSToTimeEnd[msg.sender].PreEnrollTimeEnd = block.timestamp + CSToTime[msg.sender].EnrollTime;
		CSToTimeEnd[msg.sender].EnrollTimeEnd =CSToTimeEnd[msg.sender].PreEnrollTimeEnd + CSToTime[msg.sender].EnrollTime;
		CSToTimeEnd[msg.sender].SortitionEnd = CSToTimeEnd[msg.sender].EnrollTimeEnd + CSToTime[msg.sender].SortitionTime;
		CSToTimeEnd[msg.sender].AcceptTimeEnd = CSToTimeEnd[msg.sender].SortitionEnd + CSToTime[msg.sender].AcceptTime;
		CSToTimeEnd[msg.sender].StartTimeEnd = CSToTimeEnd[msg.sender].AcceptTimeEnd + CSToTime[msg.sender].StartTime;
		CSToTimeEnd[msg.sender].PreSubmitTimeEnd = CSToTimeEnd[msg.sender].StartTimeEnd + CSToTime[msg.sender].PreSubmitTime;
		CSToTimeEnd[msg.sender].SubmitTimeEnd = CSToTimeEnd[msg.sender].PreSubmitTimeEnd + CSToTime[msg.sender].SubmitTime;
		CSToTimeEnd[msg.sender].EvaluationTimeEnd = CSToTimeEnd[msg.sender].SubmitTimeEnd + CSToTime[msg.sender].EvaluationTime;
		CSToTimeEnd[msg.sender].URWithdrawEnd = CSToTimeEnd[msg.sender].EvaluationTimeEnd + CSToTime[msg.sender].WithdrawTime;
		CSToTimeEnd[msg.sender].UTWithdrawEnd = CSToTimeEnd[msg.sender].URWithdrawEnd + CSToTime[msg.sender].WithdrawTime;

		//本次开始，
		if(!CSDataInfo[msg.sender].CSInit)
			CSDataInfo[msg.sender].CSInit = false;

		CSToFee[msg.sender].UTPrepayment = CSToFee[msg.sender].RewardFee * CSToNumber[msg.sender].CrowdURNumMax * CSToNumber[msg.sender].ImageNumber;
		
		return (CSToNumber[msg.sender].CrowdURNumMax ,CSToTimeEnd[msg.sender].PreEnrollTimeEnd,CSToTimeEnd[msg.sender].EnrollTimeEnd);
	}


/*
	0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6
	0x405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace
	0xc2575a0e9e593c00f959f8c92f12db2869c3395a3b0502d05e2516446f71f85b
	0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19b
	0x036b6384b5eca791c62761152d0c79bb0604c104a5fb6f4eb0703f3154bb3db0
	0xf652222313e28459528d920b65115c16c04f3efc82aaedc97be59f3f377c0d3f


	0xd570bdd07bf43796c12338e611cbc6b50f339408471fd397e7690a5427d15153
	[1,1,1,1,1],1
	0x40112658e646f1f0b96571c65e30efd9400db0808817796e2058ae37ed9fe0d6
	[0,1,1,1,1],1
	0x115b1482067f01093f88478092bad089a5810f7d66bd75d5a20cf7b174c6092d
	[0,1,2,3,4],0
	0x853074d7c5c3da4595e841ff41e3a72d0b220eed1c764b02aef5fdcff87eca0d
	[0,1,2,3,4],1
	0x93d9a844595c14be0a842d2b6c8592e3f7a261726b9eaeb1f842a4820650bb87
	[0,1,2,3,4],2

[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49],0	
0x58ad7758bbfdb03a9b37da0484c64c6416ca7fbf27a223e1110b2a0c0fc2bbd7
[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]


[0,1,2,3,4,5,6,7,8,9,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49],0	
0x40089d1453d2f99b0a4ce54a12a86decc71d0d552d638d1559b7fe93e3932277
[0,0,0,0,0,0,0,0,0,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49],0	
 0x55cc946e8dc422cb930c70cf9d29ee7b8163d3093b92aaf3f2a8cd35c3885696

[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0
0xc8da71eeae238e8e40991929fc63f9f3471129feb2d7afa16057c4d60940562a
[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

[0,1,2,3,4,5,6,7,8,9,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0
0xc21a2f27ec4b3167a736cad7894e5f3840cb4d90108ef610a9cf9fba32e6046c
[0,0,0,0,0,0,0,0,0,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0
0xc402223767eaa9d59bd4290e819dafa2b1c3e5840392206edf23c4fd636f9100
[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0
0xd87154119ad3e938c204b798ff949c9e10e0c70010bde4588aa4680bb6e4a393	
[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0	
0xac1f14d5745b2d47c24b9ac638e6b21fc11910508018a168f33df3c247f60642
[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0	
0x420b4642d9d925d43dc65892ffa82d203c0b59648b2e221a38a516230b220b49
[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0	
0x7d0e4e718107e1da55a4752a2478a0a07cada53ec4737b689588bb846285fd00
[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99],0	
0x7f54ec2b674bbbb62cd199a5915411cb6c107287e3bfb277ae0168ae52067cb9
[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,90,91,92,93,94,95,96,97,98,99],0
0x8b6c0afb5aca75d9b51ab0a9265eea8298c692fc74b4017ef7a69ab45e173629
[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,5657,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,7475,76,77,78,79,80,81,82,83,84,85,86,87,88,89,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],0	
0x971c27e451c7abdc011b146525e6d773ad30faf3e11d4874efd2def71977ab32

	0xd570bdd07bf43796c12338e611cbc6b50f339408471fd397e7690a5427d15153
	[1,1,1,1,1],1
	0x40112658e646f1f0b96571c65e30efd9400db0808817796e2058ae37ed9fe0d6
	[0,1,1,1,1],1
	0xc5856d8cf801075e183d1c18f291983dbfe5058e65a8ba8dc6d08d6e833b3197
	[-1,1,2,3,4],1
	0x8edbb87dbe023581924134186adb89f9e0c67f9ba3fbc103741f442a01025a46
	[0,-1,2,3,4],1
	0x4b95b622fb08035560a4c49aaee1cf415ddbd2716081faa67f06d806542561a2
	[0,1,-1,3,4],1

*/
	function setMissionID(uint _workID, int[]memory _missionID)
		external
		checkState(State.Fresh)
		checkTimeIn(CSToTimeEnd[msg.sender].EnrollTimeEnd)
		returns(bool)
	{
		require(_workID < CSToNumber[msg.sender].CrowdURNumMax,"Wrong ID");
		require(_missionID.length == CSToNumber[msg.sender].ImageNumber,"Wrong length");

        for(uint i =0;i<_missionID.length ; i++)
            require(_missionID[i] == 0 || _missionID[i] == -1,"Wrong Table");

        CSDataInfo[msg.sender].workIDToMissionID[_workID] = _missionID;

		uint counter = 0;
		for(uint j =0;j<CSToNumber[msg.sender].CrowdURNumMax ; j++)
            if(CSDataInfo[msg.sender].workIDToMissionID[j].length != 0)
                counter++;

        if(counter == CSToNumber[msg.sender].CrowdURNumMax)
           	CrowdUT[CSDataInfo[msg.sender].crowdUT].setMissionID = true;
       	return true;
	}

	function sort(uint _number)
		external
		checkState(State.Fresh)
		checkTimeOut(CSToTimeEnd[msg.sender].EnrollTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].SortitionEnd)
		returns(uint)
	{	
		require(CSToNumber[msg.sender].CrowdURNumMax - CSToCommittee[msg.sender].length == _number,"Wrong _number");
		require(CrowdUT[CSDataInfo[msg.sender].crowdUT].setMissionID,"No setMissionID");

		CrowdUT[CSDataInfo[msg.sender].crowdUT].sorted = true;

		CSDataInfo[msg.sender].CState = State.Init;
		emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].crowdUT, block.timestamp, State.Init);

		return CSToTimeEnd[msg.sender].AcceptTimeEnd;
	}

	function accept(address _crowdUR ,uint _deposit)
		external
		checkTimeOut(CSToTimeEnd[msg.sender].SortitionEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].AcceptTimeEnd)
		returns(bool)
	{
		require(CSDataInfo[msg.sender].CState == State.Init || CSDataInfo[msg.sender].CState == State.Ready,"Wrong State");
		require(!CrowdURs[_crowdUR].accepted,"Have accepted");
		require(_deposit == CSToFee[msg.sender].CommFee,"Wrong _rewardFee");

    	// require(myTwoSubmisson.resetURData(_crowdUR),"ts");//接受时清空TPS数据

		CSToCommittee[msg.sender].push(_crowdUR);
		CrowdURs[_crowdUR].workID = CSToCommittee[msg.sender].length - 1;
		CrowdURs[_crowdUR].accepted = true;
        CrowdURs[_crowdUR].presubmited = false;
        CrowdURs[_crowdUR].submited = false;
		CrowdURs[_crowdUR].balance +=  _deposit;
		CrowdURs[_crowdUR].CSContract = msg.sender;

		require(myTwoSubmisson.missionID(_crowdUR,CSDataInfo[msg.sender].workIDToMissionID[CrowdURs[_crowdUR].workID],CSToNumber[msg.sender].ImageNumber),"missionID error");
   		
		State nonsenseState;
   		if(CSToCommittee[msg.sender].length >= CSToNumber[msg.sender].CrowdURNumMin) {
   			CSDataInfo[msg.sender].CState = State.Ready;//全部接受：Ready
   			emit LogCStateModified(msg.sender, _crowdUR, block.timestamp, State.Ready);
   		}else{
   			nonsenseState = State.Ready;
   		}

		return true;
	}

	function reject(address _crowdUR)
		external
		checkTimeOut(CSToTimeEnd[msg.sender].SortitionEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].AcceptTimeEnd)
		view
		returns(bool)
	{
		require(!CrowdURs[_crowdUR].accepted,"Have accepted");
		return true;
	}


	function start(string memory _detail,uint _deposit)
		external
		checkTimeOut(CSToTimeEnd[msg.sender].AcceptTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].StartTimeEnd)
		returns(bool)
	{
		require(_deposit == CSToFee[msg.sender].UTPrepayment,"_deposit error");

		require(CSDataInfo[msg.sender].CState == State.Init || CSDataInfo[msg.sender].CState == State.Ready,"Wrong State");
		//无论成功创建与否，都有可能存在超时的UR

		CSToText[msg.sender].Detail = _detail;
		CrowdUT[CSDataInfo[msg.sender].crowdUT].balance += _deposit;
		CrowdUT[CSDataInfo[msg.sender].crowdUT].startMission = true;

		if(CSDataInfo[msg.sender].CState == State.Ready){

            require(myTwoSubmisson.resetCSData(),"ts");//可以正常开始再清楚TPS数据

			CSDataInfo[msg.sender].CState = State.Submited;
			emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].crowdUT, block.timestamp, State.Submited);

			return true;
		}else{
			CSDataInfo[msg.sender].CState = State.Fresh;
			emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].crowdUT, block.timestamp, State.Fresh);
			return false;
		}
	}


	function presubmitCSM(address _crowdUR, bytes32 _sealedMessage)
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].StartTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].PreSubmitTimeEnd)
		checkIsCommiittee(_crowdUR)
		returns(bool)
	{
		require(myTwoSubmisson.presubmit(_crowdUR, _sealedMessage,CSToCommittee[msg.sender]),"TS presubmit error");

		if(CrowdURs[_crowdUR].presubmited == false)
			CrowdURs[_crowdUR].presubmited = true;

		emit LogURPreSubmited(msg.sender,_crowdUR, block.timestamp, _sealedMessage);
		return true;
	}

	function submitCSM(address _crowdUR,int[] memory _message, uint _randomKey)
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].PreSubmitTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].SubmitTimeEnd)
		checkIsCommiittee(_crowdUR)
		returns(bool)
	{
		require(CrowdURs[_crowdUR].presubmited,"No presubmited!");
		require(myTwoSubmisson.submit(_crowdUR,_message, _randomKey),"TS Submit");

		if(CrowdURs[_crowdUR].submited == false){
			CrowdURs[_crowdUR].submited = true;
			CSToNumber[msg.sender].SubmitNum++;
		}

		emit LogURSubmited(msg.sender, _crowdUR , block.timestamp, _message);

		return true;
	}

	function check()
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].SubmitTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		returns(bool[]memory , bool[]memory)
	{
		require(!(CrowdUT[CSDataInfo[msg.sender].crowdUT].checkSubmited),"checked");
	    bool[] memory _noSubmitID = new bool[](CSToCommittee[msg.sender].length);
        bool[] memory _noPresubmitID = new bool[](CSToCommittee[msg.sender].length);

		for(uint i = 0 ; i <CSToCommittee[msg.sender].length ; i++){

			CSDataInfo[msg.sender].workIDToRightNumber.push(0);

			//对没正式提交的UR处理,若没提交，_noSubmitID中对应ID为true
			if(CrowdURs[CSToCommittee[msg.sender][i]].presubmited){
				if(CrowdURs[CSToCommittee[msg.sender][i]].submited == false){
					_noSubmitID[i] = true;
					CrowdURs[CSToCommittee[msg.sender][i]].balance -= CSToFee[msg.sender].CommFee;
				}
			}else{//对没预提交的UR处理,若没预提交，_noPresubmitID中对应ID为true
				_noPresubmitID[i] = true;
				CrowdURs[CSToCommittee[msg.sender][i]].balance -= CSToFee[msg.sender].CommFee;
			}
		}

		if(CSToNumber[msg.sender].SubmitNum != 0){
			for(uint j =0 ; j < CSToNumber[msg.sender].ImageNumber ;j++ ){
				CSDataInfo[msg.sender].rightTableArray.push(-1);
			}
		}else{
			CSDataInfo[msg.sender].CState = State.Failed;
			emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].crowdUT,block.timestamp, State.Failed);
		}

		CrowdUT[CSDataInfo[msg.sender].crowdUT].checkSubmited = true;

		return(_noPresubmitID, _noSubmitID);

	}

	function evaluation()
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].CheckTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		returns(bool)
	{
		require(CrowdUT[CSDataInfo[msg.sender].crowdUT].checkSubmited,"hav't check");
		(CSDataInfo[msg.sender].workIDToRightNumber,CSDataInfo[msg.sender].rightTableArray) = myTwoSubmisson.evaluation(CSToCommittee[msg.sender],
			CSDataInfo[msg.sender].workIDToRightNumber,CSDataInfo[msg.sender].rightTableArray,CSToNumber[msg.sender].SubmitNum);

		require(calPaid(),"calPaid error");

		return true;
	}

	function evaluation2()
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].CheckTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		returns(bool)
	{
		require(CrowdUT[CSDataInfo[msg.sender].crowdUT].checkSubmited,"hav't check");

		CSDataInfo[msg.sender].rightTableArray = myTwoSubmisson.evaluation2(CSToCommittee[msg.sender],
			CSDataInfo[msg.sender].rightTableArray,CSToNumber[msg.sender].SubmitNum);
		CSDataInfo[msg.sender].workIDToRightNumber = myTwoSubmisson.evaluation2_cal(CSToCommittee[msg.sender],
			CSDataInfo[msg.sender].workIDToRightNumber,CSDataInfo[msg.sender].rightTableArray);

		require(calPaid(),"calPaid error");

		return true;
	}

	function calPaid() internal returns(bool) {

		for(uint i = 0 ;i < CSToCommittee[msg.sender].length;i++){
			uint paid_i = CSToFee[msg.sender].RewardFee * CSDataInfo[msg.sender].workIDToRightNumber[i];
			CrowdURs[CSToCommittee[msg.sender][i]].balance += paid_i;
			CrowdUT[CSDataInfo[msg.sender].crowdUT].balance -= paid_i;
		}

		CSDataInfo[msg.sender].CState = State.Completed;
		emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].crowdUT,block.timestamp, State.Completed);

		CrowdUT[CSDataInfo[msg.sender].crowdUT].evaluated = true;

		return true;
	}

/*
	function cleanUT()
		public
		checkTimeOut(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].CleanTimeEnd)
		returns(bool)	
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed,"Wrong State");
		//是不是除了TS那边的，CSM这边的也得清除。先别清了，CSM这边一定得清的
		require(CrowdUT[CSDataInfo[msg.sender].crowdUT].evaluated,"No evaluat");
		require(myTwoSubmisson.resetCSData(),"ts");

		CrowdUT[CSDataInfo[msg.sender].crowdUT].cleaned = true;
		return true;
	}

	function cleanUR(address _crowdUR)
		public
		checkIsCommiittee(_crowdUR)
		checkTimeOut(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].CleanTimeEnd)
		returns(bool)
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");
		require(CrowdURs[_crowdUR].submited,"No submit");//暂且设置为只有完成上一步才能进行下一步。
		// require(CrowdUT[CSDataInfo[msg.sender].crowdUT].evaluated,"No evaluat");//未必有必要检测
		require(myTwoSubmisson.resetURData(_crowdUR),"ts");

		if(CrowdURs[_crowdUR].cleaned == false){
			CSToNumber[msg.sender].CleanedNum++;
			CrowdURs[_crowdUR].cleaned = true;
		}

		return true;
	}
*/
	function withdrawUR(address _crowdUR)
		external
		checkIsCommiittee(_crowdUR)
		checkTimeOut(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].URWithdrawEnd)
		returns(uint _balance)
	{
		require(CrowdURs[_crowdUR].balance > 0,"No money");
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");

		// require(CrowdURs[_crowdUR].cleaned,"no cleaned");

		if(CSDataInfo[msg.sender].CState == State.Stagnant){
			CrowdURs[_crowdUR].balance += CSToFee[msg.sender].ShareFee;
			CrowdUT[CSDataInfo[msg.sender].crowdUT].balance -=CSToFee[msg.sender].ShareFee;
		}

		_balance = CrowdURs[_crowdUR].balance;
		//CS合约中去提钱，这里只改balance
		CrowdURs[_crowdUR].balance = 0;

		return _balance;
	}

	function withdrawUT()
		external
		checkTimeOut(CSToTimeEnd[msg.sender].URWithdrawEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].UTWithdrawEnd)
		returns(uint _UTbalance)
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed,"Wrong State");
		require(CrowdUT[CSDataInfo[msg.sender].crowdUT].balance != 0,"no money");

		_UTbalance = CrowdUT[CSDataInfo[msg.sender].crowdUT].balance;
		CrowdUT[CSDataInfo[msg.sender].crowdUT].balance = 0;

		return _UTbalance;
	}

	function checkStagnant(address _crowdUR)
		external
		checkIsCommiittee(_crowdUR)
		checkTimeOut(CSToTimeEnd[msg.sender].StartTimeEnd)
		returns(int8 _value)
	{
		require(CSDataInfo[msg.sender].CState != State.Failed,"Wrong State");
		require(!CSDataInfo[msg.sender].URchecked,"have checked");

		//如果他没开始的话，只需要扣1就行了，因为大家还没交钱没工作。
		if(!CrowdUT[CSDataInfo[msg.sender].crowdUT].startMission){
        	_value = 1;
        	CSDataInfo[msg.sender].URchecked = true;

        }else{
        	if(!CrowdUT[CSDataInfo[msg.sender].crowdUT].checkSubmited){
        		if(block.timestamp > CSToTimeEnd[msg.sender].CheckTimeEnd){
        			_value = 4;
        			CSDataInfo[msg.sender].URchecked = true;
        		}
        	}else{
        		if(!CrowdUT[CSDataInfo[msg.sender].crowdUT].evaluated){
        			if(block.timestamp > CSToTimeEnd[msg.sender].EvaluationTimeEnd){
        				_value = 5;
        				CSDataInfo[msg.sender].URchecked = true;
        			}
        		}
        	}

        }

        if(CSDataInfo[msg.sender].URchecked){
        	CSDataInfo[msg.sender].CState = State.Stagnant;
			emit LogCStateModified(msg.sender, _crowdUR,block.timestamp, State.Stagnant);
        }
        
        //要帮UT清理。.
        require(myTwoSubmisson.resetCSData(),"resetCSData error");

        CSToFee[msg.sender].ShareFee = CrowdUT[CSDataInfo[msg.sender].crowdUT].balance / (CSToNumber[msg.sender].CleanedNum + 1);
        CrowdURs[_crowdUR].balance += CSToFee[msg.sender].ShareFee;
        CrowdUT[CSDataInfo[msg.sender].crowdUT].balance -= CSToFee[msg.sender].ShareFee;

        return _value;
	}

	function release(address _crowdUR) 
		external
		checkIsCommiittee(_crowdUR)
		checkTimeOut(CSToTimeEnd[msg.sender].URWithdrawEnd)
		returns(bool)
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");
		require(CrowdURs[_crowdUR].balance == 0);

        /*
        //没必要调整位置了，因为无论主动推出还是统一清楚都要删除工人信息
		CSToCommittee[msg.sender][CrowdURs[_crowdUR].workID] = CSToCommittee[msg.sender][CSToCommittee[msg.sender].length -1];
		CrowdURs[CSToCommittee[msg.sender][CSToCommittee[msg.sender].length -1]].workID = CrowdURs[_crowdUR].workID;
		CSToCommittee[msg.sender].length--;
        */
		delete CrowdURs[_crowdUR];
		return true;
	}

	function restartCS()
		external
		checkState(State.Completed)
		returns(bool[]memory)
	{
		//清除CSData必要的
		CSToNumber[msg.sender].SubmitNum = 0;
		CSToNumber[msg.sender].CleanedNum = 0;
		CSToFee[msg.sender].ShareFee = 0;

		//清除委员会,记录成功完成的ID，以便在UM中进行状态操作
		bool[] memory CompletedID = new bool[](CSToCommittee[msg.sender].length);

		for(uint i = 0 ; i< CSToCommittee[msg.sender].length ;i++){
			if(CrowdURs[CSToCommittee[msg.sender][i]].submited){
				CompletedID[i] = true;
				delete CrowdURs[CSToCommittee[msg.sender][i]];
			}
		}

		delete CrowdUT[CSDataInfo[msg.sender].crowdUT];

		delete CSDataInfo[msg.sender].workIDToRightNumber;
		delete CSToCommittee[msg.sender];

		return CompletedID;
	}
/*
	function finishCS()
		external
		checkTimeOut(CSToTimeEnd[msg.sender].UTWithdrawEnd)
		returns(bool[])
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");

		//不CLean CSM的数据了，因为下次子啊用必会清理，没必要花这个钱。

		bool[] memory CompletedID = new bool[](CSToCommittee[msg.sender].length);

		for(uint i = 0 ; i< CSToCommittee[msg.sender].length ;i++){
			if(CrowdURs[CSToCommittee[msg.sender][i]].cleaned){
				CompletedID[i] = true;
				delete CrowdURs[CSToCommittee[msg.sender][i]];
			}
		}
		return CompletedID;
	}
*/

	function cleanCSM() internal returns(bool) {
		if(CSDataInfo[msg.sender].CSInit){
			return true;
		}else{
			//检查UR数据是否清除
			if(CSToCommittee[msg.sender].length != 0){//如果委员会没人，说明每一个UR都退出，推出前一定会清掉自己的相关信息,即UR信息已经clean
				for(uint i =0;i< CSToCommittee[msg.sender].length;i++){
					delete CrowdURs[CSToCommittee[msg.sender][i]];
					// delete CSDataInfo[msg.sender].workIDToMissionID[i];//这个删不删无所谓，因为下次必然要等重新设置所有的才可以变为true
				}
			}
			delete CSToCommittee[msg.sender];
			//检查UT及CS数据是否清除
			if(!CSDataInfo[msg.sender].CSInit){

				//clean CSData
				delete CSToCommittee[msg.sender];
				delete CSToText[msg.sender];
				delete CSToNumber[msg.sender];
				delete CSToFee[msg.sender];
				delete CSToTime[msg.sender];
				delete CSToTimeEnd[msg.sender];

				// Clean UTData
				delete CrowdUT[CSDataInfo[msg.sender].crowdUT];
			}

			CSDataInfo[msg.sender].CSInit = true;

			return true;
		}

	}



    function getMissionID(uint _workID) public view returns(int[]memory){
        return  CSDataInfo[msg.sender].workIDToMissionID[_workID];
    }



}