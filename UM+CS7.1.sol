// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.7.0;

import "./safemath.sol";

/*
 * The user management contract (UM) is mainly responsible for managing various information of users, including status, reputation, signed contracts, etc.
   The crowdsourcing contract (CS) refers to a specific crowdsourcing contract address, which contains an interface for users to directly call
 * ==========================================
 *  Title: UM & CS Contracts for DCrowd.
 *  Author: 
 *  Email: 
 *  
 * ==========================================
 */

interface TwoSubmission{

	function preEnroll(address _CSContract, address _worker, bytes32 _sealedrandom) external returns(bool);
	function enroll(address _CSContract, address _worker, uint _randomKey) external returns(bool);
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

	enum WState {Offline, Online, Candidate, Ready, Busy}
	
	//Record the user information of DCrowd
	struct CrowdUser {
		bool registered;
		int8 reputationW;
		int8 reputationR;//作为R的信誉值
		uint index;
		uint confirmDeadline;
		uint registerFee;
		address CSContract;
		mapping(address => bool) preEnrolled;
		WState state;
	}

	mapping(address => CrowdUser) public CrowdUserPool;
	address[] public WorkerAddrs;

	mapping(address => address[]) public WToEnrollCSs;
	address[] public selectedWorkers;

	//Record information about unbiased elections
	struct SortitionInfo {
		string introduction;
		bool valid;
		bool recruiting;
		uint sortitonNum;
		uint preEnrollDL;
		uint enrollDL;
		uint enrollFee;

		address requester;
	}

	mapping(address => SortitionInfo) public CSContractPool;

	mapping(address => address[]) public CSToEnrolledWs;


	event LogCSContractGen(address indexed _who, uint _time, address _contractAddr);
	event LogWorkerSelected(address indexed _who, uint _time, address _contractAddr);

	//Check if it has been registered
	modifier checkRegister(address _normalUser){
		require(!CrowdUserPool[_normalUser].registered,"Have registered!");
		_;
	}

	//Check if you have registered as a DC user
	modifier checkIsCrowdUser(address _register){
		require(CrowdUserPool[_register].registered,"No registered!");
		_;
	}

	//Check whether W has been selected by the unbiased algorithm
	modifier checkWSelected(address _worker){
		require(CrowdUserPool[_worker].state == WState.Candidate,"Not selected!");
		_;
	}

	//Check whether the candidate accepts the task
	modifier checkWAccrpted(address _worker) {
		require(CrowdUserPool[_worker].state == WState.Ready,"Not accepted");
		_;
	}

	//Check whether the CS is valid
	modifier checkCSContract(address _CSContract) {
		require(CSContractPool[_CSContract].valid == true,"Invalid!");
		_;
	}

	/*
	Role : R
	Function : R generates a new CS contract belonging to him
	*/
	function RgenCSContract()
		public
		returns(address)
	{
		address newCSContract = address(new OverallManagement(address(this), msg.sender, address(myTwoSubmisson), address(csm)));
		CSContractPool[newCSContract].valid = true;
		CSContractPool[newCSContract].requester = msg.sender;

		emit LogCSContractGen(msg.sender, block.timestamp, newCSContract);
		return newCSContract;
	}


    function InvalidateCSContract(address _Requester)
		external
		checkIsCrowdUser(_Requester)
		checkCSContract(msg.sender)
		returns(bool)
	{

		require(CSContractPool[msg.sender].valid,"not valid");
		require(CSContractPool[msg.sender].requester == _Requester,"not your R");

		CSContractPool[msg.sender].valid = false;
		return true;
	}

	/*
	Role : R
	Function : Post recruitment information
	*/
	function recruit(string memory _introduction,uint _sortitionNum,uint _preEnrollEnd,uint _enrollEnd,uint _enrollFee)
		external
		checkCSContract(msg.sender)
		returns(bool success)
	{
		//为避免上一次只进行了报名，但没有进行选取的情况发生，在进行招募时，要先清掉该CS的招聘信息（上次遗留的报名者）
		if(CSToEnrolledWs[msg.sender].length != 0)//说明上次招募失败没有进行选取或者选取失败（不符合选取条件）
			require(myTwoSubmisson.resetEnrollData(msg.sender, CSToEnrolledWs[msg.sender]),"resetEnrollData Error");

		CSContractPool[msg.sender].recruiting = true;
		CSContractPool[msg.sender].introduction = _introduction;
		CSContractPool[msg.sender].sortitonNum = _sortitionNum;
		CSContractPool[msg.sender].preEnrollDL = _preEnrollEnd;
		CSContractPool[msg.sender].enrollDL = _enrollEnd;
		CSContractPool[msg.sender].enrollFee = _enrollFee;

		return true;
	}

	/*
	Role : Ordinary users
	Function : Ordinary users register as DC users
	*/
	function UserRegister()
		public
		payable
		checkRegister(msg.sender)
	{
		require(msg.value == registrationFee,"Wrong registrationFee!");
		WorkerAddrs.push(msg.sender);
		CrowdUserPool[msg.sender].index = WorkerAddrs.length.sub(1);
		CrowdUserPool[msg.sender].registered = true;
		CrowdUserPool[msg.sender].reputationW = 100;
		CrowdUserPool[msg.sender].reputationR = 100;
		CrowdUserPool[msg.sender].state = WState.Offline;
		CrowdUserPool[msg.sender].registerFee = registrationFee;
	}

	/*
	Role : W & R
	Function : W or R Sign up for a specific crowdsourcing task in the first stage
	*/
	function WPreEnroll(address _CSContract,bytes32 _sealedrandom)
		public
		checkCSContract(_CSContract)
		checkIsCrowdUser(msg.sender)
	{
		require(CrowdUserPool[msg.sender].state == WState.Online,"Not Online!");
		require(block.timestamp < CSContractPool[_CSContract].preEnrollDL,"Out of preEnrollDL!");
		require(CrowdUserPool[msg.sender].CSContract != _CSContract,"You have been selected");

		require(CSContractPool[_CSContract].recruiting,"Hasn't started");

        // require(!CrowdUserPool[msg.sender].preEnrolled[_CSContract],"Have enrolled");
        //没必要在这检查，在后边检查，因为你可以多次提交加密随机数。但只有提交了真实随机数才算做报名成功。

        require(myTwoSubmisson.preEnroll(_CSContract,msg.sender,_sealedrandom),"preEnroll Error");

        //设置符号，已预报名该CSC，还是那个问题，没必要检测是否预报名（因为没预报名直接提交肯定不予接受。）
        CrowdUserPool[msg.sender].preEnrolled[_CSContract] = true;
	}

	/*
	Role : W & R
	Function : W or R Sign up for a specific crowdsourcing task in the second stage
	*/
	function Wenroll(address _CSContract, uint _randomKey)
		external
		payable
		checkCSContract(_CSContract)
		checkIsCrowdUser(msg.sender)
	{
		require(CrowdUserPool[msg.sender].state == WState.Online,"Not Online!");
		require(block.timestamp < CSContractPool[_CSContract].enrollDL,"Out of enrollDL!");
		require(CSToEnrolledWs[_CSContract].length <= CSContractPool[_CSContract].sortitonNum.mul(10),"Too many");
		require(CSContractPool[_CSContract].enrollFee == msg.value,"Wrong EnrollFee");

		require(myTwoSubmisson.enroll(_CSContract, msg.sender, _randomKey),"enroll error");

		//检测是否报名过该CSC(必须通过该方法检测)
		for(uint i =0;i < CSToEnrolledWs[_CSContract].length ; i=i.add(1)) {
			require(msg.sender != CSToEnrolledWs[_CSContract][i],"Have Enrolled!");
		}
		//报名成功
        CSToEnrolledWs[_CSContract].push(msg.sender);
        WToEnrollCSs[msg.sender].push(_CSContract);
	}

	/*
	// 完整系统里是需要的（有助于W进行报名前的查询），但现在还用不到该函数
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
		return WToEnrollCSs[msg.sender][_i];
	}
	 */

	/*
	Role : W
	Function : Candidate accepts CS task
	*/
	function acceptCS(address _candidate)
		external
		checkWSelected(_candidate)
		checkCSContract(msg.sender)
		returns(bool acceptSuccess)
	{
		// require(block.timestamp < CrowdUserPool[_candidate].confirmDeadline,"Time is over.");在CSM中检查过了
		require(msg.sender == CrowdUserPool[_candidate].CSContract,"Illegal call!");

		CrowdUserPool[_candidate].state = WState.Ready;

		return true;
	}

	/*
	Role : W
	Function : Candidate rejects CS task
	*/
	function rejectCS(address _candidate)
		external
		checkWSelected(_candidate)
		checkCSContract(msg.sender)
		returns(bool rejectSuccess)
	{
		// require(block.timestamp < CrowdUserPool[_candidate].confirmDeadline,"Time is over.");在CSM中检查过了
		require(msg.sender == CrowdUserPool[_candidate].CSContract,"Illegal call!");

		CrowdUserPool[_candidate].reputationW = CrowdUserPool[_candidate].reputationW.sub(1);

		if(CrowdUserPool[_candidate].reputationW > 0){
			CrowdUserPool[_candidate].state = WState.Online;
			// onlineCounter++;
		}else{
			CrowdUserPool[_candidate].state = WState.Offline;
		}

		// onlineCounter++;

		return true;
	}

	/*
	Role : R
	Function : Unbiased random selection
	*/
	function sortition(uint _N, uint _acceptTimeEnd, address _Requester)
		external
		checkCSContract(msg.sender)
		returns(bool success)
	{
		//关闭招人
		CSContractPool[msg.sender].recruiting = false;
		//正常情况下，报名人数至少也是5倍
		require(CSToEnrolledWs[msg.sender].length > CSContractPool[msg.sender].sortitonNum,"Too few applicants!");
		uint seed = myTwoSubmisson.getKeyArraySum(msg.sender);
		seed = uint(keccak256(abi.encodePacked(seed)));

		uint WorkerCounter = 0;
		while(WorkerCounter < _N) {
			address WAddr = CSToEnrolledWs[msg.sender][seed % CSToEnrolledWs[msg.sender].length];
			if(CrowdUserPool[WAddr].reputationW > 0 && CrowdUserPool[WAddr].state == WState.Online && WAddr != _Requester){

				CrowdUserPool[WAddr].confirmDeadline = _acceptTimeEnd;
				CrowdUserPool[WAddr].CSContract = msg.sender;
				CrowdUserPool[WAddr].state = WState.Candidate;

				selectedWorkers.push(WAddr);

				emit LogWorkerSelected(WAddr, block.timestamp ,msg.sender);

				WorkerCounter = WorkerCounter.add(1);
				// onlineCounter++;//可能用不上
			}

			seed = (uint)(keccak256(abi.encodePacked(seed)));
		}

		//确保下次先请求再选人
		for(uint j = 0;j < CSToEnrolledWs[msg.sender].length ; j=j.add(1)){
			if(CrowdUserPool[CSToEnrolledWs[msg.sender][j]].CSContract != msg.sender){
				CrowdUserPool[CSToEnrolledWs[msg.sender][j]].preEnrolled[msg.sender] = false;
			}
		}

		require(myTwoSubmisson.resetEnrollData(msg.sender, CSToEnrolledWs[msg.sender]),"resetEnrollData Error");

		delete CSToEnrolledWs[msg.sender];
		
		return true;
	}

	/*
	Role : W(Candidate)
	Function : Deal with candidates who have not responded in time
	*/
	function reverse()
		external
		checkCSContract(msg.sender)
		returns(bool)
	{
		for(uint i = 0 ; i < selectedWorkers.length; i=i.add(1)){
			if(CrowdUserPool[selectedWorkers[i]].state == WState.Candidate){
				CrowdUserPool[selectedWorkers[i]].reputationW = CrowdUserPool[selectedWorkers[i]].reputationW.sub(5);
				if(CrowdUserPool[selectedWorkers[i]].reputationW > 0){
					CrowdUserPool[selectedWorkers[i]].state = WState.Online;
					// onlineCounter++;
				}else{
					CrowdUserPool[selectedWorkers[i]].state = WState.Offline;
				}
			}
		}

		delete selectedWorkers;

		return true;
	}


	function missionStart(address _readyW) 
		external
		checkCSContract(msg.sender)
		returns(bool success)
	{
		require(CrowdUserPool[_readyW].CSContract == msg.sender,"Wrong CSContract");
		require(CrowdUserPool[_readyW].state == WState.Ready,"Not Ready");

		CrowdUserPool[_readyW].state = WState.Busy;
		// onlineCounter--;
		return true;
	}

	/*
	Role : R
	Function : Deal with CW who fails to submit results in time
	*/
	function release(address _worker)
		external
		checkIsCrowdUser(_worker)
		checkCSContract(msg.sender)
		returns(bool)
	{
		require(CrowdUserPool[_worker].CSContract == msg.sender,"Wrong CSContract");

		require(CrowdUserPool[_worker].state == WState.Busy,"Not Busy");

		CrowdUserPool[_worker].CSContract = address(0);
		CrowdUserPool[_worker].preEnrolled[msg.sender] = false;

		if(CrowdUserPool[_worker].reputationW > 0){
			CrowdUserPool[_worker].state = WState.Online;
			// onlineCounter++;
		}else{
			CrowdUserPool[_worker].state = WState.Offline;
		}
		return true;
	}

	/*
	Role : R & W
	Function : Management W or R's reputation value
	*/
	function ReputationDecraese(bool _worker, address _crowdUser, int8 _value)
		external
		checkCSContract(msg.sender)
		checkIsCrowdUser(_crowdUser)
		returns(bool success)
	{
		require(_value > 0,"Wrong _value");

		if(_worker){
			require(CrowdUserPool[_crowdUser].CSContract == msg.sender,"Wrong CSContract");
			require(CrowdUserPool[_crowdUser].state == WState.Busy,"Not Busy");

			CrowdUserPool[_crowdUser].reputationW = CrowdUserPool[_crowdUser].reputationW.sub(_value);
		}else{
			require(_crowdUser == CSContractPool[msg.sender].requester,"Not Your R");

			CrowdUserPool[_crowdUser].reputationR = CrowdUserPool[_crowdUser].reputationR.sub(_value);
		}
		return true;
	}

	function WTurnOn() public checkIsCrowdUser(msg.sender){
		require(CrowdUserPool[msg.sender].state == WState.Offline,"Not Offline!");
		require(CrowdUserPool[msg.sender].reputationW > 0,"reputationW < 0");

		CrowdUserPool[msg.sender].state = WState.Online;
		// onlineCounter++;
	}

	function WTurnOff() public checkIsCrowdUser(msg.sender){
		require(CrowdUserPool[msg.sender].state == WState.Online,"Not Online!");

		CrowdUserPool[msg.sender].state = WState.Offline;
		// onlineCounter--;
	}

	/*
	Role : W & R
	Function : User logout
	*/
	function userCancellation() public checkIsCrowdUser(msg.sender) returns(bool success,string memory){
		require(CrowdUserPool[msg.sender].state == WState.Offline,"Not Offline!");
		require(CrowdUserPool[msg.sender].registerFee > 0,"No money to withdraw");

		if(CrowdUserPool[msg.sender].reputationW >= 0){

			msg.sender.transfer(registrationFee);
			CrowdUserPool[msg.sender].registered = false;
			return(true,"Success!");
		}else{
			CrowdUserPool[msg.sender].registered = false;
			return(true,"reputationW < 0");
		}

	}
    
}

interface CSManagement {
	function initRequester(address _requester) external returns(bool);
	function setImageNum(uint _imageNum) external returns(bool);
	function setCCNnum(uint _WNumMax, uint _WNumMin) external returns(bool);
	function setFee(uint _rewardFee, uint _enrollFee,uint _deposit) external returns(uint,uint,uint);
	function setCTTime(uint _enrollTime, uint _sortTime,uint _acceptTime, uint _startTime)external returns(uint);
	function setPTTime(uint _presubmitTime, uint _submitTime,uint _evaluationTime,uint _withdrawTime) external returns(bool);
    function recruit(string memory _introduction) external returns(uint,uint,uint);
	function setMissionID(uint _workID,int[] memory _missionID) external returns(bool);
	function sort(uint _number) external returns(uint);
	function accept(address _worker ,uint _deposit) external returns(bool);
	function reject(address _worker) external returns(bool);
	function start(string memory _detail,uint _deposit) external returns(bool);
	function presubmitCSM(address _worker, bytes32 _sealedMessage) external returns(bool);
	function submitCSM(address _worker,int[] memory _message, uint _randomKey) external returns(bool);
	function check() external returns(bool[] memory , bool[] memory);
	function evaluation() external returns(bool);
	function evaluation2() external returns(bool);
	function cleanW(address _worker) external returns(bool);
	function cleanR() external returns(bool);
	function withdrawW(address _worker) external returns(uint _balance);
	// function withdrawR() external returns(bool[] memory,uint);
	function withdrawR() external returns(uint _Rbalance);
	function checkStagnant(address _worker) external returns(int8 _value);
	function release(address _worker) external returns(bool);
	function restartCS() external returns(bool[] memory);
	function finishCS() external returns(bool[] memory);

}
contract OverallManagement {

	CSManagement public csm;
	TwoSubmission public myTwoSubmisson;
   	UserManagement public um;
	address public Requester;

	using SafeMath for uint;
	using SafeMath for int8;
	
	constructor(address _um,address _Requester,address _TwoAddrs ,address _csm) {
		um =  UserManagement(_um);
		myTwoSubmisson = TwoSubmission(_TwoAddrs);
		csm = CSManagement(_csm);
		Requester = _Requester;

		csm.initRequester(_Requester);
	}
	
	address [] public WorkerCommittee;

	uint public WorkerNumMax;
	uint public EnrollTime;
	uint AcceptTimeEnd;

	uint public EnrollFee;
	uint public RewardFee;
	uint public Deposit;

	modifier checkRequester() {
		require(msg.sender == Requester,"Not Requester!");
		_;
	}

	function RsetImageNum(uint _imageNum) public checkRequester
	{
		require(csm.setImageNum(_imageNum),"_imageNum error");
	}

	function RsetWorkerCommnum(uint _WNumMax, uint _WNumMin) public checkRequester
	{
		require(csm.setCCNnum(_WNumMax, _WNumMin),"_imageNum error");
		WorkerNumMax = _WNumMax;
	}

	function RsetRewardFee(uint _rewardFee, uint _enrollFee, uint _deposit) public checkRequester
	{
		(RewardFee,EnrollFee,Deposit) = csm.setFee(_rewardFee, _enrollFee,_deposit);
	}

	function RsetCTTime(uint _enrollTime, uint _sortTime,uint _acceptTime, uint _startTime)public checkRequester
	{
		EnrollTime =  csm.setCTTime(_enrollTime, _sortTime, _acceptTime, _startTime);
	}

	function RsetPTTime(uint _presubmitTime, uint _submitTime,uint _evaluationTime,uint _withdrawTime)public checkRequester
	{
		require(csm.setPTTime(_presubmitTime, _submitTime, _evaluationTime, _withdrawTime),"_imageNum error");
	}

	function RRecruit(string memory _introduction)
		public
		checkRequester
	{
		uint max;
		uint preEnd;
		uint enrollEnd;
		(max, preEnd,enrollEnd) = csm.recruit(_introduction);

		require(um.recruit(_introduction,max,preEnd, enrollEnd,EnrollFee),"recruit error");
		
	}

	/*
	Role : R
	Function : R upload task ID of WC
	*/
	function RSetMissionID(uint _workID,int[] memory _missionID)
		public
		checkRequester
	{
		require(csm.setMissionID(_workID,_missionID),"setMissionID error");
	}

	/*
	Role : R
	Function : Unbiased random selection
	*/
	function RsortitionFromOM(uint _number)
		public
		checkRequester
	{
		uint acceptEnd = csm.sort(_number);
		require(um.sortition(_number, acceptEnd, Requester),"sortition Failed!");
	}

	/*
	Role : W
	Function : Candidate accepts CS task
	*/
	function WAccept() public payable{

		require(um.acceptCS(msg.sender),"um");
		require(csm.accept(msg.sender,msg.value),"csm");

		WorkerCommittee.push(msg.sender);
	}

	/*
	Role : W
	Function : Candidate rejects CS task
	*/
	function WReject() public {
		require(csm.reject(msg.sender),"csm");
		require(um.rejectCS(msg.sender),"um");
	}

	/*
	Role : R
	Function : R starts crowdsourcing mission
	*/
	function RStartMisson(string memory _detail) public payable{

		require(um.reverse());

		bool ready = csm.start(_detail, msg.value);

		if(ready){
			for(uint i = 0 ; i < WorkerCommittee.length ; i=i.add(1))
				require(um.missionStart(WorkerCommittee[i]));
		}
	}

	/*
	Role : CW
	Function : CW pre-submission crowdsourcing commitments
	*/
	function WPresubmit(bytes32 _sealedMessage)public {
		require(csm.presubmitCSM(msg.sender,_sealedMessage),"csm error");
	}

	/*
	Role : CW
	Function : CW public crowdsourcing results and random numbers
	*/
	function WSubmit(int[] memory _message, uint _randomKey) public {
		require(csm.submitCSM(msg.sender, _message, _randomKey),"csm error");
	}

	/*
	Role : R
	Function : R check the worker's submission
	*/
	function RCheckSubmit() public checkRequester {

        bool[] memory noPresubmitID = new bool[](WorkerCommittee.length);
		bool[] memory noSubmitID = new bool[](WorkerCommittee.length);

        (noPresubmitID, noSubmitID) = csm.check();

        releaseUM(noPresubmitID);
        releaseUM(noSubmitID);
        
	}
/*
	function REvaluat() public checkRequester {
		require(csm.evaluation());
	}
*/

	/*
	Role : R
	Function : Calculate the correct answer according to the convention
	*/
	function REvaluat2() public checkRequester {
		require(csm.evaluation2());
	}

	/*
	Role : CW
	Function : W get remuneration and deposit
	*/
	function WWithdraw() public payable returns(uint){
		uint balanceW =  csm.withdrawW(msg.sender);
		msg.sender.transfer(balanceW);
		return balanceW;
	}

	/*
	Role : R
	Function : R Get back the remaining deposit
	*/
	function RWithdraw() public payable checkRequester returns(uint){

		uint balanceR = csm.withdrawR();
		msg.sender.transfer(balanceR);
		return balanceR;
	}

/*
	function RWithdraw() public payable checkRequester returns(uint){
		uint balanceR;
		bool[] memory noCleanedID = new bool[](WorkerCommittee.length);

		(noCleanedID,balanceR) = csm.withdrawR();
		releaseUM(noCleanedID);

		msg.sender.transfer(balanceR);
		return balanceR;
	}
*/

	/*
	Role : CW
	Function : W checks whether R is operating in violation of regulations
	*/
	function WCheckStagant() public {

		int8 value = csm.checkStagnant(msg.sender);
		if(value != 0)
			require(um.ReputationDecraese(false,Requester,value));
	}

	/*
	Role : CW
	Function : CW voluntarily withdrew from the committee
	*/
	function WRelease() public {
		require(csm.release(msg.sender),"csm");
		require(um.release(msg.sender),"um");
	}

	/*
	Role : R
	Function : R restart CS mission
	*/
	function RRestartCS() public checkRequester {
		releaseUM(csm.restartCS());
	}

	function RCleanCS() public payable checkRequester {

		if(address(this).balance > 0)
			msg.sender.transfer(address(this).balance);

		releaseUM(csm.finishCS());
	}

	function releaseUM(bool[]memory _releaseID) internal {

		bool[] memory ReleaseID = new bool[](WorkerCommittee.length);

		ReleaseID = _releaseID;

		for(uint i = 0 ; i< WorkerCommittee.length ; i=i.add(1)){

        	if(ReleaseID[i]){
        		require(um.ReputationDecraese(true,WorkerCommittee[i],10),"ReputationDecraese true,error");
        		require(um.release(WorkerCommittee[i]),"release error");
        	}
        }
        delete WorkerCommittee;

	}


	function getbalance() public view returns(uint) {
		return address(this).balance;
	}

}
