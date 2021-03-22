// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.7.0;

import "./safemath.sol";

interface TwoSubmission{

	function preEnroll(address _CSContract, address _crowdUR, bytes32 _sealedrandom) external returns(bool);
	function enroll(address _CSContract, address _crowdUR, uint _randomKey) external returns(bool);
	function getKeyArraySum(address _CSContract) external view returns(uint);
	function resetEnrollData(address _CSContract,address[] memory _enrollAddrs) external returns(bool);
}

contract UserManagement {

	using SafeMath for uint;
	using SafeMath for int8;


	TwoSubmission public myTwoSubmisson;
	CSManagement public csm;
	
	constructor(address _TwoAddrs ,address _csm) {
		myTwoSubmisson = TwoSubmission(_TwoAddrs);
		csm = CSManagement(_csm);
	}

	// uint onlineCounter;
	uint registrationFee = 1 wei;

	enum URState {Offline, Online, Candidate, Ready, Busy}
	
	struct CrowdUser {
		bool registered;
		int8 reputationUR;
		int8 reputationUT;//作为UT的信誉值
		uint index;
		uint confirmDeadline;
		uint registerFee;
		address CSContract;
		mapping(address => bool) preEnrolled;
		URState state;
	}

	mapping(address => CrowdUser) public CrowdUserPool;
	address[] public CrowdURAddrs;

	mapping(address => address[]) public URToEnrollCSs;
	address[] public selectedCrowdURs;

	struct SortitionInfo {

		string introduction;
		bool valid;
		bool recruiting;
		uint sortitonNum;
		uint preEnrollDL;
		uint enrollDL;
		uint enrollFee;

		address crowdUT;
	}

	mapping(address => SortitionInfo) public CSContractPool;

	mapping(address => address[]) public CSToEnrolledURs;


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

	0xc5856d8cf801075e183d1c18f291983dbfe5058e65a8ba8dc6d08d6e833b3197
	[-1,1,2,3,4],1
	0x8edbb87dbe023581924134186adb89f9e0c67f9ba3fbc103741f442a01025a46
	[0,-1,2,3,4],1
	0x4b95b622fb08035560a4c49aaee1cf415ddbd2716081faa67f06d806542561a2
	[0,1,-1,3,4],1

*/
	event LogCSContractGen(address indexed _who, uint _time, address _contractAddr);
	event LogCrowdURSelected(address indexed _who, uint _time, address _contractAddr);

	modifier checkRegister(address _normalUser){
		require(!CrowdUserPool[_normalUser].registered,"Have registered!");
		_;
	}

	modifier checkIsCrowdUser(address _register){
		require(CrowdUserPool[_register].registered,"No registered!");
		_;
	}

	modifier checkURSelected(address _crowdUR){
		require(CrowdUserPool[_crowdUR].state == URState.Candidate,"Not selected!");
		_;
	}

	modifier checkURAccrpted(address _crowdUR) {
		require(CrowdUserPool[_crowdUR].state == URState.Ready,"Not accepted");
		_;
	}

	modifier checkCSContract(address _CSContract) {
		require(CSContractPool[_CSContract].valid == true,"Invalid!");
		_;
	}


	function UTgenCSContract()
		public
		returns(address)
	{
		address newCSContract = address(new OverallManagement(address(this), msg.sender, address(myTwoSubmisson), address(csm)));
		CSContractPool[newCSContract].valid = true;
		CSContractPool[newCSContract].crowdUT = msg.sender;

		emit LogCSContractGen(msg.sender, block.timestamp, newCSContract);
		return newCSContract;
	}

    function InvalidateCSContract(address _CrowdUT)
		external
		checkIsCrowdUser(_CrowdUT)
		checkCSContract(msg.sender)
		returns(bool)
	{

		require(CSContractPool[msg.sender].valid,"not valid");
		require(CSContractPool[msg.sender].crowdUT == _CrowdUT,"not your UT");

		CSContractPool[msg.sender].valid = false;
		return true;
	}

	function recruit(string memory _introduction,uint _sortitionNum,uint _preEnrollEnd,uint _enrollEnd,uint _enrollFee)
		external
		checkCSContract(msg.sender)
		returns(bool success)
	{
		//为避免上一次只进行了报名，但没有进行选取的情况发生，在进行招募时，要先清掉该CS的招聘信息（上次遗留的报名者）
		if(CSToEnrolledURs[msg.sender].length != 0)//说明上次招募失败没有进行选取或者选取失败（不符合选取条件）
			require(myTwoSubmisson.resetEnrollData(msg.sender, CSToEnrolledURs[msg.sender]),"resetEnrollData Error");

		CSContractPool[msg.sender].recruiting = true;
		CSContractPool[msg.sender].introduction = _introduction;
		CSContractPool[msg.sender].sortitonNum = _sortitionNum;
		CSContractPool[msg.sender].preEnrollDL = _preEnrollEnd;
		CSContractPool[msg.sender].enrollDL = _enrollEnd;
		CSContractPool[msg.sender].enrollFee = _enrollFee;

		return true;
	}

/*
	//没必要有，因为可以直接查询
	function validateCS(address _CSContract)
		external
		view
		returns(bool valid)
	{
		if(CSContractPool[_CSContract].valid)
			return true;
		else
			return false;
	}
 */

	function UserRegister()
		public
		payable
		checkRegister(msg.sender)
	{
		require(msg.value == registrationFee,"Wrong registrationFee!");
		CrowdURAddrs.push(msg.sender);
		CrowdUserPool[msg.sender].index = CrowdURAddrs.length.sub(1);
		CrowdUserPool[msg.sender].registered = true;
		CrowdUserPool[msg.sender].reputationUR = 100;
		CrowdUserPool[msg.sender].reputationUT = 100;
		CrowdUserPool[msg.sender].state = URState.Offline;
		CrowdUserPool[msg.sender].registerFee = registrationFee;
	}

	function URPreEnroll(address _CSContract,bytes32 _sealedrandom)
		public
		checkCSContract(_CSContract)
		checkIsCrowdUser(msg.sender)
	{
		require(CrowdUserPool[msg.sender].state == URState.Online,"Not Online!");
		require(block.timestamp < CSContractPool[_CSContract].preEnrollDL,"Out of preEnrollDL!");
		require(CrowdUserPool[msg.sender].CSContract != _CSContract,"You have been selected");

		require(CSContractPool[_CSContract].recruiting,"Hasn't started");

        // require(!CrowdUserPool[msg.sender].preEnrolled[_CSContract],"Have enrolled");
        //没必要在这检查，在后边检查，因为你可以多次提交加密随机数。但只有提交了真实随机数才算做报名成功。

        require(myTwoSubmisson.preEnroll(_CSContract,msg.sender,_sealedrandom),"preEnroll Error");

        //设置符号，已预报名该CSC，还是那个问题，没必要检测是否预报名（因为没预报名直接提交肯定不予接受。）
        CrowdUserPool[msg.sender].preEnrolled[_CSContract] = true;
	}

	function URenroll(address _CSContract, uint _randomKey)
		external
		payable
		checkCSContract(_CSContract)
		checkIsCrowdUser(msg.sender)
	{
		require(CrowdUserPool[msg.sender].state == URState.Online,"Not Online!");
		require(block.timestamp < CSContractPool[_CSContract].enrollDL,"Out of enrollDL!");
		require(CSToEnrolledURs[_CSContract].length <= CSContractPool[_CSContract].sortitonNum.mul(10),"Too many");
		require(CSContractPool[_CSContract].enrollFee == msg.value,"Wrong EnrollFee");

		require(myTwoSubmisson.enroll(_CSContract, msg.sender, _randomKey),"enroll error");

		//检测是否报名过该CSC(必须通过该方法检测)
		for(uint i =0;i < CSToEnrolledURs[_CSContract].length ; i=i.add(1)) {
			require(msg.sender != CSToEnrolledURs[_CSContract][i],"Have Enrolled!");
		}
		//报名成功
        CSToEnrolledURs[_CSContract].push(msg.sender);
        URToEnrollCSs[msg.sender].push(_CSContract);
	}

	/*
	// 完整系统里是需要的（有助于UR进行报名前的查询），但现在还用不到该函数
	function checkenrolledCSC(address _CSContract)
		public
		view
		checkCSContract(_CSContract)
		checkIsCrowdUser(msg.sender)
		returns(bool preEnrolled)
	{
		return CrowdUserPool[msg.sender].preEnrolled[_CSContract];
	}

	function checkenrollCSC(uint _i)
		public
		view
		checkIsCrowdUser(msg.sender)
		returns(address)
	{
		return URToEnrollCSs[msg.sender][_i];
	}
	 */

	function acceptCS(address _candidate)
		external
		checkURSelected(_candidate)
		checkCSContract(msg.sender)
		returns(bool acceptSuccess)
	{
		// require(block.timestamp < CrowdUserPool[_candidate].confirmDeadline,"Time is over.");在CSM中检查过了
		require(msg.sender == CrowdUserPool[_candidate].CSContract,"Illegal call!");

		CrowdUserPool[_candidate].state = URState.Ready;

		return true;
	}

	//CS->UR:
	function rejectCS(address _candidate)
		external
		checkURSelected(_candidate)
		checkCSContract(msg.sender)
		returns(bool rejectSuccess)
	{
		// require(block.timestamp < CrowdUserPool[_candidate].confirmDeadline,"Time is over.");在CSM中检查过了
		require(msg.sender == CrowdUserPool[_candidate].CSContract,"Illegal call!");

		CrowdUserPool[_candidate].reputationUR = CrowdUserPool[_candidate].reputationUR.sub(1);

		if(CrowdUserPool[_candidate].reputationUR > 0){
			CrowdUserPool[_candidate].state = URState.Online;
			// onlineCounter++;
		}else{
			CrowdUserPool[_candidate].state = URState.Offline;
		}

		// onlineCounter++;

		return true;
	}

	//CS:
	function sortition(uint _N, uint _acceptTimeEnd, address _CrowdUT)
		external
		checkCSContract(msg.sender)
		returns(bool success)
	{
		//关闭招人
		CSContractPool[msg.sender].recruiting = false;
		//正常情况下，报名人数至少也是5倍
		require(CSToEnrolledURs[msg.sender].length > CSContractPool[msg.sender].sortitonNum,"Too few applicants!");
		uint seed = myTwoSubmisson.getKeyArraySum(msg.sender);
		seed = uint(keccak256(abi.encodePacked(seed)));

		uint CrowdURCounter = 0;
		while(CrowdURCounter < _N) {
			address URAddr = CSToEnrolledURs[msg.sender][seed % CSToEnrolledURs[msg.sender].length];
			if(CrowdUserPool[URAddr].reputationUR > 0 && CrowdUserPool[URAddr].state == URState.Online && URAddr != _CrowdUT){

				CrowdUserPool[URAddr].confirmDeadline = _acceptTimeEnd;
				CrowdUserPool[URAddr].CSContract = msg.sender;
				CrowdUserPool[URAddr].state = URState.Candidate;

				selectedCrowdURs.push(URAddr);

				emit LogCrowdURSelected(URAddr, block.timestamp ,msg.sender);

				CrowdURCounter = CrowdURCounter.add(1);
				// onlineCounter++;//可能用不上
			}

			seed = (uint)(keccak256(abi.encodePacked(seed)));
		}

		//确保下次先请求再选人
		for(uint j = 0;j < CSToEnrolledURs[msg.sender].length ; j=j.add(1)){
			if(CrowdUserPool[CSToEnrolledURs[msg.sender][j]].CSContract != msg.sender){
				CrowdUserPool[CSToEnrolledURs[msg.sender][j]].preEnrolled[msg.sender] = false;
			}
		}

		require(myTwoSubmisson.resetEnrollData(msg.sender, CSToEnrolledURs[msg.sender]),"resetEnrollData Error");

		delete CSToEnrolledURs[msg.sender];
		
		return true;
	}

	//UT:若任务未成功创建，对报名的UR进行操作
	function reverse()
		external
		checkCSContract(msg.sender)
		returns(bool)
	{
		for(uint i = 0 ; i < selectedCrowdURs.length; i=i.add(1)){
			if(CrowdUserPool[selectedCrowdURs[i]].state == URState.Candidate){
				CrowdUserPool[selectedCrowdURs[i]].reputationUR = CrowdUserPool[selectedCrowdURs[i]].reputationUR.sub(5);
				if(CrowdUserPool[selectedCrowdURs[i]].reputationUR > 0){
					CrowdUserPool[selectedCrowdURs[i]].state = URState.Online;
					// onlineCounter++;
				}else{
					CrowdUserPool[selectedCrowdURs[i]].state = URState.Offline;
				}
			}
		}

		delete selectedCrowdURs;

		return true;
	}

	function missionStart(address _readyUR) 
		external
		checkCSContract(msg.sender)
		returns(bool success)
	{
		require(CrowdUserPool[_readyUR].CSContract == msg.sender,"Wrong CSContract");
		require(CrowdUserPool[_readyUR].state == URState.Ready,"Not Ready");

		CrowdUserPool[_readyUR].state = URState.Busy;
		// onlineCounter--;
		return true;
	}

	//CS:对没提交的UR进行处理，CSC等也得清了
	function release(address _crowdUR)
		external
		checkIsCrowdUser(_crowdUR)
		checkCSContract(msg.sender)
		returns(bool)
	{
		require(CrowdUserPool[_crowdUR].CSContract == msg.sender,"Wrong CSContract");

		require(CrowdUserPool[_crowdUR].state == URState.Busy,"Not Busy");

		CrowdUserPool[_crowdUR].CSContract = address(0);
		CrowdUserPool[_crowdUR].preEnrolled[msg.sender] = false;

		if(CrowdUserPool[_crowdUR].reputationUR > 0){
			CrowdUserPool[_crowdUR].state = URState.Online;
			// onlineCounter++;
		}else{
			CrowdUserPool[_crowdUR].state = URState.Offline;
		}
		return true;
	}

	//CS:
	function ReputationDecraese(bool _crowdUR, address _crowdUser, int8 _value)
		external
		checkCSContract(msg.sender)
		checkIsCrowdUser(_crowdUser)
		returns(bool success)
	{
		require(_value > 0,"Wrong _value");

		if(_crowdUR){
			require(CrowdUserPool[_crowdUser].CSContract == msg.sender,"Wrong CSContract");
			require(CrowdUserPool[_crowdUser].state == URState.Busy,"Not Busy");

			CrowdUserPool[_crowdUser].reputationUR = CrowdUserPool[_crowdUser].reputationUR.sub(_value);
		}else{
			require(_crowdUser == CSContractPool[msg.sender].crowdUT,"Not Your UT");

			CrowdUserPool[_crowdUser].reputationUT = CrowdUserPool[_crowdUser].reputationUT.sub(_value);
		}
		return true;
	}
/*

 	//没必要单拉出来，合二为一
	function UTReputation(true,address _crowdUT, int8 _value)
		external
		checkCSContract(msg.sender)
		checkIsCrowdUser(_crowdUT)
		returns(bool success)
	{
		require(_value > 0,"Wrong _value");
		require(_crowdUT == CSContractPool[msg.sender].crowdUT,"Not Your UT");

		CrowdUserPool[_crowdUT].reputationUT -= _value;

		return true;
	}
*/
	function URTurnOn() public checkIsCrowdUser(msg.sender){
		require(CrowdUserPool[msg.sender].state == URState.Offline,"Not Offline!");
		require(CrowdUserPool[msg.sender].reputationUR > 0,"reputationUR < 0");

		CrowdUserPool[msg.sender].state = URState.Online;
		// onlineCounter++;
	}

	function URTurnOff() public checkIsCrowdUser(msg.sender){
		require(CrowdUserPool[msg.sender].state == URState.Online,"Not Online!");

		CrowdUserPool[msg.sender].state = URState.Offline;
		// onlineCounter--;
	}

	function URCancellation() public checkIsCrowdUser(msg.sender) returns(bool success,string memory){
		require(CrowdUserPool[msg.sender].state == URState.Offline,"Not Offline!");
		require(CrowdUserPool[msg.sender].registerFee > 0,"No money to withdraw");

		if(CrowdUserPool[msg.sender].reputationUR >= 0){

			msg.sender.transfer(registrationFee);
			CrowdUserPool[msg.sender].registered = false;
			return(true,"Success!");
		}else{
			CrowdUserPool[msg.sender].registered = false;
			return(true,"reputationUR < 0");
		}

	}
    
}

interface CSManagement {
	function initCrowdUT(address _crowdUT) external returns(bool);
	function setImageNum(uint _imageNum) external returns(bool);
	function setCCNnum(uint _URNumMax, uint _URNumMin) external returns(bool);
	function setFee(uint _rewardFee, uint _enrollFee,uint _deposit) external returns(uint,uint,uint);
	function setCTTime(uint _enrollTime, uint _sortTime,uint _acceptTime, uint _startTime)external returns(uint);
	function setPTTime(uint _presubmitTime, uint _submitTime,uint _evaluationTime,uint _withdrawTime) external returns(bool);
// 	function setURTimeParas(uint _enrollTime,uint _acceptTime,uint _presubmitTime, uint _submitTime,uint _withdrawTime) external returns(uint);
// 	function setUTTimeParas(uint _sortTime, uint _startTime,uint _checkTime,uint _evaluationTime, uint _resetDataTime) external returns(bool);
    function recruit(string memory _introduction) external returns(uint,uint,uint);
	function setMissionID(uint _workID,int[] memory _missionID) external returns(bool);
	function sort(uint _number) external returns(uint);
	function accept(address _crowdUR ,uint _deposit) external returns(bool);
	function reject(address _crowdUR) external returns(bool);
	function start(string memory _detail,uint _deposit) external returns(bool);
	function presubmitCSM(address _crowdUR, bytes32 _sealedMessage) external returns(bool);
	function submitCSM(address _crowdUR,int[] memory _message, uint _randomKey) external returns(bool);
	function check() external returns(bool[] memory , bool[] memory);
	function evaluation() external returns(bool);
	function evaluation2() external returns(bool);
	function cleanUR(address _crowdUR) external returns(bool);
	function cleanUT() external returns(bool);
	function withdrawUR(address _crowdUR) external returns(uint _balance);
	// function withdrawUT() external returns(bool[] memory,uint);
	function withdrawUT() external returns(uint _UTbalance);
	function checkStagnant(address _crowdUR) external returns(int8 _value);
	function release(address _crowdUR) external returns(bool);
	function restartCS() external returns(bool[] memory);
	function finishCS() external returns(bool[] memory);

}
contract OverallManagement {

	CSManagement public csm;
	TwoSubmission public myTwoSubmisson;
   	UserManagement public um;
	address public CrowdUT;

	using SafeMath for uint;
	using SafeMath for int8;
	
	constructor(address _um,address _CrowdUT,address _TwoAddrs ,address _csm) {
		um =  UserManagement(_um);
		myTwoSubmisson = TwoSubmission(_TwoAddrs);
		csm = CSManagement(_csm);
		CrowdUT = _CrowdUT;

		csm.initCrowdUT(_CrowdUT);
	}
	
	address [] public CrowdURCommittee;

	uint public CrowdURNumMax;
	uint public EnrollTime;
	uint AcceptTimeEnd;

	uint public EnrollFee;
	uint public RewardFee;
	uint public Deposit;

	modifier checkCrowdUT() {
		require(msg.sender == CrowdUT,"Not CrowdUT!");
		_;
	}

	function UTsetImageNum(uint _imageNum) public checkCrowdUT
	{
		require(csm.setImageNum(_imageNum),"_imageNum error");
	}

	function UTsetCrowdURCommnum(uint _URNumMax, uint _URNumMin) public checkCrowdUT
	{
		require(csm.setCCNnum(_URNumMax, _URNumMin),"_imageNum error");
		CrowdURNumMax = _URNumMax;
	}

	function UTsetRewardFee(uint _rewardFee, uint _enrollFee, uint _deposit) public checkCrowdUT
	{
		(RewardFee,EnrollFee,Deposit) = csm.setFee(_rewardFee, _enrollFee,_deposit);
	}

	function UTsetCTTime(uint _enrollTime, uint _sortTime,uint _acceptTime, uint _startTime)public checkCrowdUT
	{
		EnrollTime =  csm.setCTTime(_enrollTime, _sortTime, _acceptTime, _startTime);
	}

	function UTsetPTTime(uint _presubmitTime, uint _submitTime,uint _evaluationTime,uint _withdrawTime)public checkCrowdUT
	{
		require(csm.setPTTime(_presubmitTime, _submitTime, _evaluationTime, _withdrawTime),"_imageNum error");
	}
/*
	function UTsetURTimeParas(uint _enrollTime,uint _acceptTime,uint _presubmitTime, uint _submitTime,uint _withdrawTime)public checkCrowdUT
	{
		EnrollTime =  csm.setURTimeParas( _enrollTime, _acceptTime, _presubmitTime, _submitTime, _withdrawTime);
	}

	function UTsetUTTimeParas(uint _sortTime, uint _startTime,uint _checkSubtimeTime,uint _evaluationTime, uint _resetDataTime)
		public
		checkCrowdUT
	{
		require(csm.setUTTimeParas( _sortTime, _startTime, _checkSubtimeTime, _evaluationTime, _resetDataTime),"_imageNum error");
	}
*/
	function UTRecruit(string memory _introduction)
		public
		checkCrowdUT
	{
		uint max;
		uint preEnd;
		uint enrollEnd;
		(max, preEnd,enrollEnd) = csm.recruit(_introduction);

		require(um.recruit(_introduction,max,preEnd, enrollEnd,EnrollFee),"recruit error");
		
	}

	function UTSetMissionID(uint _workID,int[] memory _missionID)
		public
		checkCrowdUT
	{
		require(csm.setMissionID(_workID,_missionID),"setMissionID error");
	}

	function UTsortitionFromOM(uint _number)
		public
		checkCrowdUT
	{
		uint acceptEnd = csm.sort(_number);
		require(um.sortition(_number, acceptEnd, CrowdUT),"sortition Failed!");
	}

	function URAccept() public payable{

		require(um.acceptCS(msg.sender),"um");
		require(csm.accept(msg.sender,msg.value),"csm");

		CrowdURCommittee.push(msg.sender);
	}

	function URReject() public {
		require(csm.reject(msg.sender),"csm");
		require(um.rejectCS(msg.sender),"um");
	}

	function UTStartMisson(string memory _detail) public payable{

		require(um.reverse());

		bool ready = csm.start(_detail, msg.value);

		if(ready){
			for(uint i = 0 ; i < CrowdURCommittee.length ; i=i.add(1))
				require(um.missionStart(CrowdURCommittee[i]));
		}
	}

	function URPresubmit(bytes32 _sealedMessage)public {
		require(csm.presubmitCSM(msg.sender,_sealedMessage),"csm error");
	}


	function URSubmit(int[] memory _message, uint _randomKey) public {
		require(csm.submitCSM(msg.sender, _message, _randomKey),"csm error");
	}

	function UTCheckSubmit() public checkCrowdUT {

        bool[] memory noPresubmitID = new bool[](CrowdURCommittee.length);
		bool[] memory noSubmitID = new bool[](CrowdURCommittee.length);

        (noPresubmitID, noSubmitID) = csm.check();

        releaseUM(noPresubmitID);
        releaseUM(noSubmitID);
        
	}

	function UTEvaluat() public checkCrowdUT {
		require(csm.evaluation());
	}
	function UTEvaluat2() public checkCrowdUT {
		require(csm.evaluation2());
	}
/*
	function URClean() public {
		require(csm.cleanUR(msg.sender));
	}
	function UTClean() public checkCrowdUT {
		require(csm.cleanUT());
	}
*/
	function URWithdraw() public payable returns(uint){
		uint balanceUR =  csm.withdrawUR(msg.sender);
		msg.sender.transfer(balanceUR);
		return balanceUR;
	}

	function UTWithdraw() public payable checkCrowdUT returns(uint){

		uint balanceUT = csm.withdrawUT();
		msg.sender.transfer(balanceUT);
		return balanceUT;
	}

/*
	function UTWithdraw() public payable checkCrowdUT returns(uint){
		uint balanceUT;
		bool[] memory noCleanedID = new bool[](CrowdURCommittee.length);

		(noCleanedID,balanceUT) = csm.withdrawUT();
		releaseUM(noCleanedID);

		msg.sender.transfer(balanceUT);
		return balanceUT;
	}
*/
	function URCheckStagant() public {

		int8 value = csm.checkStagnant(msg.sender);
		if(value != 0)
			require(um.ReputationDecraese(false,CrowdUT,value));
	}

	function URRelease() public {
		require(csm.release(msg.sender),"csm");
		require(um.release(msg.sender),"um");
	}

	function UTRestartCS() public checkCrowdUT {
		releaseUM(csm.restartCS());
	}

	function UTCleanCS() public payable checkCrowdUT {

		if(address(this).balance > 0)
			msg.sender.transfer(address(this).balance);

		releaseUM(csm.finishCS());
	}

	function releaseUM(bool[]memory _releaseID) internal {

		bool[] memory ReleaseID = new bool[](CrowdURCommittee.length);

		ReleaseID = _releaseID;

		for(uint i = 0 ; i< CrowdURCommittee.length ; i=i.add(1)){

        	if(ReleaseID[i]){
        		require(um.ReputationDecraese(true,CrowdURCommittee[i],10),"ReputationDecraese true,error");
        		require(um.release(CrowdURCommittee[i]),"release error");
        	}
        }
        delete CrowdURCommittee;

	}
	
	function getbalance() public view returns(uint) {
		return address(this).balance;
	}
}
