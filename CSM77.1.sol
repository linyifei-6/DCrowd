// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.7.0;

import "./safemath.sol";

/*
 * The CSManagement contract(CSM) stipulates various operations after the crowdsourcing activity starts, 
   and is responsible for implementing the crowdsourcing process and managing the state of the crowdsourcing contract.
 * ==========================================
 *  Title: CSManagement Contract for DCrowd.
 *  Author: 
 *  Email:
 *  
 * ==========================================
 */


interface TwoSubmission{
	
	function missionID(address _worker,int[] memory _missionID,uint _imageNum) external returns(bool);
	function presubmit(address _submitter, bytes32 _sealedMessage,address[] memory _addrs)external returns(bool);
	function submit(address _submitter, int[] memory _message ,uint _randomKey) external returns(bool);
	function evaluation(address[]memory _addrs,uint[]memory _workIDToRightNum,int[] memory _rightTable, uint _submitNum)external returns(uint [] memory,int[] memory);
    function evaluation2(address[] memory _addrs, int[] memory _rightTable, uint _submitNum) external returns(int[] memory);
	function evaluation2_cal(address[] memory _addrs, uint[] memory _workIDToRightNum, int[] memory _rightTable)external view returns(uint[] memory);
	function resetCSData() external returns(bool);
	function resetWData(address _worker) external returns(bool);
}

contract CSManagement {

	using SafeMath for uint;
	using SafeMath for int;

	TwoSubmission public myTwoSubmisson;
	
	constructor(address _TwoAddrs) {
		myTwoSubmisson = TwoSubmission(_TwoAddrs);
		require(myTwoSubmisson.resetCSData(),"ts");
	}

    enum State {Fresh, Init, Ready, Submited, Failed,Stagnant, Completed}

	//Record the length of time information for crowdsourcing tasks
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
    
	//Record the end time information of crowdsourcing tasks
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
		uint  WWithdrawEnd;
		uint  RWithdrawEnd;
	}
	mapping(address => timeEndInfo) public CSToTimeEnd;

	//Record the number of participants in crowdsourcing tasks
	struct numberInfo {
		uint ImageNumber;
		uint WorkerNumMax;
		uint WorkerNumMin;
		uint SubmitNum;
		uint CleanedNum;
	}
	mapping(address => numberInfo) public CSToNumber;

	//Record various fee information of crowdsourcing tasks
	struct feeInfo {
		uint  RPrepayment;
		uint  ShareFee;
		uint  RewardFee;
		uint EnrollFee;
		uint  CommFee;
	}
	mapping(address => feeInfo) public CSToFee;

	//Record the textual information of the crowdsourcing task
	struct textInfo {
		string Introduction;
		string Detail;
	}
	mapping(address => textInfo) public CSToText;

	//Record crowdsourced task execution information
	struct contractInfo {
		bool Wchecked;
		bool CSInit;
		address requester;
		State CState;
		uint [] workIDToRightNumber;
		int [] rightTableArray;
		mapping(uint => int[]) workIDToMissionID;
	}
	mapping(address => contractInfo) public CSDataInfo;

	//Record requester information for crowdsourcing activities
	struct requesterInfo{
		bool setMissionID;
		bool sorted;
		bool startMission;
		bool checkSubmited;
		bool evaluated;
		// bool cleaned;
		uint balance;
	}
	mapping(address => requesterInfo) public Requester;

    struct WorkerAccount {
        bool accepted;
        bool presubmited;
        bool submited;
        // bool cleaned;
        uint balance;
        uint workID;
        address CSContract;
    }
    mapping(address => WorkerAccount) public Workers;
	mapping(address => address[]) public  CSToCommittee;

	event LogCStateModified(address indexed _CSContract, address indexed _who, uint _time, State _newstate);
	event LogWPreSubmited(address indexed _CSContract, address indexed _who, uint _time, bytes32 _sealedMessage);
	event LogWSubmited(address indexed _CSContract, address indexed _who, uint _time,int[] _message);

	//Check the status of CS
	modifier checkState(State _state) {
		require(CSDataInfo[msg.sender].CState == _state,"Wrong State");
		_;
	}

	//Check if the user belongs to WC
	modifier checkIsCommiittee(address _worker) {
		require(Workers[_worker].CSContract == msg.sender,"Not CC");
		_;
	}

	//Check if it is within the time window
	modifier checkTimeIn(uint _endTime) {
		require(block.timestamp < _endTime,"Out of time!");
		_;
	}

	//Check if it is outside the time window
	modifier checkTimeOut(uint _endTime) {
		require(block.timestamp > _endTime,"Too early!");
		_;
	}

	//Initialize the requester of CS
	function initRequester(address _requester) external checkState(State.Fresh) returns(bool){
		CSDataInfo[msg.sender].requester = _requester;
		CSDataInfo[msg.sender].CSInit = true;
		return true;
	}

	function setImageNum(uint _imageNum)
		external
		checkState(State.Fresh)
		returns(bool)
	{
		require(_imageNum > 0);

		CSToNumber[msg.sender].ImageNumber = _imageNum;
		return true;
	}

	function setCCNnum(uint _WNumMax, uint _WNumMin)
		external
		checkState(State.Fresh)
		returns(bool)
	{
		require(_WNumMax > 0);
		require(_WNumMin > 0);

		CSToNumber[msg.sender].WorkerNumMax = _WNumMax;
		CSToNumber[msg.sender].WorkerNumMin = _WNumMin;
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
		require(CSToNumber[msg.sender].WorkerNumMax > 0);

		uint oneUnit = 1 gwei;
		CSToFee[msg.sender].RewardFee = _rewardFee.mul(oneUnit);
		CSToFee[msg.sender].EnrollFee = _enrollFee.mul(oneUnit);
		CSToFee[msg.sender].CommFee = _deposit.mul(oneUnit);

		return (CSToFee[msg.sender].RewardFee,CSToFee[msg.sender].CommFee, CSToFee[msg.sender].CommFee);
	}

	function setCTTime(uint _enrollTime, uint _sortTime,uint _acceptTime, uint _startTime)
		external 
		checkState(State.Fresh)
		returns(uint) 
	{
		uint oneUnit = 1 minutes;
		CSToTime[msg.sender].EnrollTime = _enrollTime.mul(oneUnit);
		CSToTime[msg.sender].SortitionTime = _sortTime.mul(oneUnit);
		CSToTime[msg.sender].AcceptTime = _acceptTime.mul(oneUnit);
		CSToTime[msg.sender].StartTime = _startTime.mul(oneUnit);

		return CSToTime[msg.sender].EnrollTime;
	}

	function setPTTime(uint _presubmitTime, uint _submitTime, uint _evaluationTime, uint _withdrawTime)
		external
		checkState(State.Fresh) 
		returns(bool)
	{
		uint oneUnit = 1 minutes;

		CSToTime[msg.sender].PreSubmitTime = _presubmitTime.mul(oneUnit);
		CSToTime[msg.sender].SubmitTime = _submitTime.mul(oneUnit);
		CSToTime[msg.sender].EvaluationTime = _evaluationTime.mul(oneUnit);
		CSToTime[msg.sender].WithdrawTime = _withdrawTime.mul(oneUnit);
		return true;
	}

	
	/*
	Role : R
	Function : Post recruitment information
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

		CSToTimeEnd[msg.sender].PreEnrollTimeEnd = block.timestamp.add(CSToTime[msg.sender].EnrollTime);
		CSToTimeEnd[msg.sender].EnrollTimeEnd =CSToTimeEnd[msg.sender].PreEnrollTimeEnd.add(CSToTime[msg.sender].EnrollTime);
		CSToTimeEnd[msg.sender].SortitionEnd = CSToTimeEnd[msg.sender].EnrollTimeEnd.add(CSToTime[msg.sender].SortitionTime) ;
		CSToTimeEnd[msg.sender].AcceptTimeEnd = CSToTimeEnd[msg.sender].SortitionEnd.add(CSToTime[msg.sender].AcceptTime) ;
		CSToTimeEnd[msg.sender].StartTimeEnd = CSToTimeEnd[msg.sender].AcceptTimeEnd.add(CSToTime[msg.sender].StartTime) ;
		CSToTimeEnd[msg.sender].PreSubmitTimeEnd = CSToTimeEnd[msg.sender].StartTimeEnd.add(CSToTime[msg.sender].PreSubmitTime) ;
		CSToTimeEnd[msg.sender].SubmitTimeEnd = CSToTimeEnd[msg.sender].PreSubmitTimeEnd.add(CSToTime[msg.sender].SubmitTime) ;
		CSToTimeEnd[msg.sender].EvaluationTimeEnd = CSToTimeEnd[msg.sender].SubmitTimeEnd.add(CSToTime[msg.sender].EvaluationTime) ;
		CSToTimeEnd[msg.sender].WWithdrawEnd = CSToTimeEnd[msg.sender].EvaluationTimeEnd.add(CSToTime[msg.sender].WithdrawTime) ;
		CSToTimeEnd[msg.sender].RWithdrawEnd = CSToTimeEnd[msg.sender].WWithdrawEnd.add(CSToTime[msg.sender].WithdrawTime) ;

		//本次开始，
		if(!CSDataInfo[msg.sender].CSInit)
			CSDataInfo[msg.sender].CSInit = false;

		CSToFee[msg.sender].RPrepayment = CSToFee[msg.sender].RewardFee.mul(CSToNumber[msg.sender].WorkerNumMax.mul(CSToNumber[msg.sender].ImageNumber));
		
		return (CSToNumber[msg.sender].WorkerNumMax ,CSToTimeEnd[msg.sender].PreEnrollTimeEnd,CSToTimeEnd[msg.sender].EnrollTimeEnd);
	}

	/*
	Role : R
	Function : R upload task ID of WC
	*/
	function setMissionID(uint _workID, int[]memory _missionID)
		external
		checkState(State.Fresh)
		checkTimeIn(CSToTimeEnd[msg.sender].EnrollTimeEnd)
		returns(bool)
	{
		require(_workID < CSToNumber[msg.sender].WorkerNumMax,"Wrong ID");
		require(_missionID.length == CSToNumber[msg.sender].ImageNumber,"Wrong length");

        for(uint i =0;i<_missionID.length ; i=i.add(1))
            require(_missionID[i] == 0 || _missionID[i] == -1,"Wrong Table");

        CSDataInfo[msg.sender].workIDToMissionID[_workID] = _missionID;

		uint counter = 0;
		for(uint j =0;j<CSToNumber[msg.sender].WorkerNumMax ; j=j.add(1))
            if(CSDataInfo[msg.sender].workIDToMissionID[j].length != 0)
                counter = counter.add(1);

        if(counter == CSToNumber[msg.sender].WorkerNumMax)
           	Requester[CSDataInfo[msg.sender].requester].setMissionID = true;
       	return true;
	}

	/*
	Role : R
	Function : Unbiased random selection
	*/
	function sort(uint _number)
		external
		checkState(State.Fresh)
		checkTimeOut(CSToTimeEnd[msg.sender].EnrollTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].SortitionEnd)
		returns(uint)
	{	
		require( CSToNumber[msg.sender].WorkerNumMax.sub(CSToCommittee[msg.sender].length) == _number,"Wrong _number");
		require(Requester[CSDataInfo[msg.sender].requester].setMissionID,"No setMissionID");

		Requester[CSDataInfo[msg.sender].requester].sorted = true;

		CSDataInfo[msg.sender].CState = State.Init;
		emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].requester, block.timestamp, State.Init);

		return CSToTimeEnd[msg.sender].AcceptTimeEnd;
	}

	/*
	Role : W
	Function : Candidate accepts CS task
	*/
	function accept(address _worker ,uint _deposit)
		external
		checkTimeOut(CSToTimeEnd[msg.sender].SortitionEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].AcceptTimeEnd)
		returns(bool)
	{
		require(CSDataInfo[msg.sender].CState == State.Init || CSDataInfo[msg.sender].CState == State.Ready,"Wrong State");
		require(!Workers[_worker].accepted,"Have accepted");
		require(_deposit == CSToFee[msg.sender].CommFee,"Wrong _rewardFee");

		CSToCommittee[msg.sender].push(_worker);
		Workers[_worker].workID = CSToCommittee[msg.sender].length.sub(1);
		Workers[_worker].accepted = true;
        Workers[_worker].presubmited = false;
        Workers[_worker].submited = false;
		Workers[_worker].balance = Workers[_worker].balance.add(_deposit);
		Workers[_worker].CSContract = msg.sender;

		require(myTwoSubmisson.missionID(_worker,CSDataInfo[msg.sender].workIDToMissionID[Workers[_worker].workID],CSToNumber[msg.sender].ImageNumber),"missionID error");
   		
		State nonsenseState;
   		if(CSToCommittee[msg.sender].length >= CSToNumber[msg.sender].WorkerNumMin) {
   			CSDataInfo[msg.sender].CState = State.Ready;//全部接受：Ready
   			emit LogCStateModified(msg.sender, _worker, block.timestamp, State.Ready);
   		}else{
   			nonsenseState = State.Ready;
   		}

		return true;
	}

	/*
	Role : W
	Function : Candidate rejects CS task
	*/
	function reject(address _worker)
		external
		checkTimeOut(CSToTimeEnd[msg.sender].SortitionEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].AcceptTimeEnd)
		view
		returns(bool)
	{
		require(!Workers[_worker].accepted,"Have accepted");
		return true;
	}

	/*
	Role : R
	Function : R starts crowdsourcing mission
	*/
	function start(string memory _detail,uint _deposit)
		external
		checkTimeOut(CSToTimeEnd[msg.sender].AcceptTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].StartTimeEnd)
		returns(bool)
	{
		require(_deposit == CSToFee[msg.sender].RPrepayment,"_deposit error");

		require(CSDataInfo[msg.sender].CState == State.Init || CSDataInfo[msg.sender].CState == State.Ready,"Wrong State");


		CSToText[msg.sender].Detail = _detail;
		Requester[CSDataInfo[msg.sender].requester].balance =Requester[CSDataInfo[msg.sender].requester].balance.add(_deposit);
		Requester[CSDataInfo[msg.sender].requester].startMission = true;

		if(CSDataInfo[msg.sender].CState == State.Ready){

            require(myTwoSubmisson.resetCSData(),"ts");

			CSDataInfo[msg.sender].CState = State.Submited;
			emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].requester, block.timestamp, State.Submited);

			return true;
		}else{
			CSDataInfo[msg.sender].CState = State.Fresh;
			emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].requester, block.timestamp, State.Fresh);
			return false;
		}
	}

	/*
	Role : CW
	Function : CW pre-submission crowdsourcing commitments
	*/
	function presubmitCSM(address _worker, bytes32 _sealedMessage)
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].StartTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].PreSubmitTimeEnd)
		checkIsCommiittee(_worker)
		returns(bool)
	{
		require(myTwoSubmisson.presubmit(_worker, _sealedMessage,CSToCommittee[msg.sender]),"TS presubmit error");

		if(Workers[_worker].presubmited == false)
			Workers[_worker].presubmited = true;

		emit LogWPreSubmited(msg.sender,_worker, block.timestamp, _sealedMessage);
		return true;
	}
	/*
	Role : CW
	Function : CW public crowdsourcing results and random numbers
	*/
	function submitCSM(address _worker,int[] memory _message, uint _randomKey)
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].PreSubmitTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].SubmitTimeEnd)
		checkIsCommiittee(_worker)
		returns(bool)
	{
		require(Workers[_worker].presubmited,"No presubmited!");
		require(myTwoSubmisson.submit(_worker,_message, _randomKey),"TS Submit");

		if(Workers[_worker].submited == false){
			Workers[_worker].submited = true;
			CSToNumber[msg.sender].SubmitNum = CSToNumber[msg.sender].SubmitNum.add(1);
		}

		emit LogWSubmited(msg.sender, _worker , block.timestamp, _message);

		return true;
	}

	/*
	Role : R
	Function : R check the worker's submission
	*/
	function check()
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].SubmitTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		returns(bool[]memory , bool[]memory)
	{
		require(!(Requester[CSDataInfo[msg.sender].requester].checkSubmited),"checked");
	    bool[] memory _noSubmitID = new bool[](CSToCommittee[msg.sender].length);
        bool[] memory _noPresubmitID = new bool[](CSToCommittee[msg.sender].length);

		for(uint i = 0 ; i <CSToCommittee[msg.sender].length ; i=i.add(1)){

			CSDataInfo[msg.sender].workIDToRightNumber.push(0);

			//对没正式提交的W处理,若没提交，_noSubmitID中对应ID为true
			if(Workers[CSToCommittee[msg.sender][i]].presubmited){
				if(Workers[CSToCommittee[msg.sender][i]].submited == false){
					_noSubmitID[i] = true;
					Workers[CSToCommittee[msg.sender][i]].balance =Workers[CSToCommittee[msg.sender][i]].balance.sub(CSToFee[msg.sender].CommFee);
				}
			}else{//对没预提交的W处理,若没预提交，_noPresubmitID中对应ID为true
				_noPresubmitID[i] = true;
				Workers[CSToCommittee[msg.sender][i]].balance =Workers[CSToCommittee[msg.sender][i]].balance.sub(CSToFee[msg.sender].CommFee);
			}
		}

		if(CSToNumber[msg.sender].SubmitNum != 0){
			for(uint j =0 ; j < CSToNumber[msg.sender].ImageNumber ;j=j.add(1) ){
				CSDataInfo[msg.sender].rightTableArray.push(-1);
			}
		}else{
			CSDataInfo[msg.sender].CState = State.Failed;
			emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].requester,block.timestamp, State.Failed);
		}

		Requester[CSDataInfo[msg.sender].requester].checkSubmited = true;

		return(_noPresubmitID, _noSubmitID);

	}

	/*
	Role : R
	Function : Candidate accepts CS task
	
	function evaluation()
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].CheckTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		returns(bool)
	{
		require(Requester[CSDataInfo[msg.sender].requester].checkSubmited,"hav't check");
		(CSDataInfo[msg.sender].workIDToRightNumber,CSDataInfo[msg.sender].rightTableArray) = myTwoSubmisson.evaluation(CSToCommittee[msg.sender],
			CSDataInfo[msg.sender].workIDToRightNumber,CSDataInfo[msg.sender].rightTableArray,CSToNumber[msg.sender].SubmitNum);

		require(calPaid(),"calPaid error");

		return true;
	}
	*/

	/*
	Role : R
	Function : Calculate the correct answer according to the convention
	*/
	function evaluation2()
		external
		checkState(State.Submited)
		checkTimeOut(CSToTimeEnd[msg.sender].CheckTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		returns(bool)
	{
		require(Requester[CSDataInfo[msg.sender].requester].checkSubmited,"hav't check");

		CSDataInfo[msg.sender].rightTableArray = myTwoSubmisson.evaluation2(CSToCommittee[msg.sender],
			CSDataInfo[msg.sender].rightTableArray,CSToNumber[msg.sender].SubmitNum);
		CSDataInfo[msg.sender].workIDToRightNumber = myTwoSubmisson.evaluation2_cal(CSToCommittee[msg.sender],
			CSDataInfo[msg.sender].workIDToRightNumber,CSDataInfo[msg.sender].rightTableArray);

		require(calPaid(),"calPaid error");

		return true;
	}

	/*
	Role : R
	Function : Calculate the remuneration due to the quality of the data submitted by W
	*/
	function calPaid() internal returns(bool) {

		for(uint i = 0 ;i < CSToCommittee[msg.sender].length;i=i.add(1)){
			uint paid_i = CSToFee[msg.sender].RewardFee.mul(CSDataInfo[msg.sender].workIDToRightNumber[i]);
			Workers[CSToCommittee[msg.sender][i]].balance = Workers[CSToCommittee[msg.sender][i]].balance.add(paid_i);
			Requester[CSDataInfo[msg.sender].requester].balance = Requester[CSDataInfo[msg.sender].requester].balance.sub(paid_i);
		}

		CSDataInfo[msg.sender].CState = State.Completed;
		emit LogCStateModified(msg.sender, CSDataInfo[msg.sender].requester,block.timestamp, State.Completed);

		Requester[CSDataInfo[msg.sender].requester].evaluated = true;

		return true;
	}

/*
	function cleanR()
		public
		checkTimeOut(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].CleanTimeEnd)
		returns(bool)	
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed,"Wrong State");
		//是不是除了TS那边的，CSM这边的也得清除。先别清了，CSM这边一定得清的
		require(Requester[CSDataInfo[msg.sender].requester].evaluated,"No evaluat");
		require(myTwoSubmisson.resetCSData(),"ts");

		Requester[CSDataInfo[msg.sender].requester].cleaned = true;
		return true;
	}

	function cleanW(address _worker)
		public
		checkIsCommiittee(_worker)
		checkTimeOut(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].CleanTimeEnd)
		returns(bool)
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");
		require(Workers[_worker].submited,"No submit");//暂且设置为只有完成上一步才能进行下一步。
		// require(Requester[CSDataInfo[msg.sender].requester].evaluated,"No evaluat");//未必有必要检测
		require(myTwoSubmisson.resetWData(_worker),"ts");

		if(Workers[_worker].cleaned == false){
			CSToNumber[msg.sender].CleanedNum++;
			Workers[_worker].cleaned = true;
		}

		return true;
	}
*/

	/*
	Role : CW
	Function : W get remuneration and deposit
	*/
	function withdrawW(address _worker)
		external
		checkIsCommiittee(_worker)
		checkTimeOut(CSToTimeEnd[msg.sender].EvaluationTimeEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].WWithdrawEnd)
		returns(uint _balance)
	{
		require(Workers[_worker].balance > 0,"No money");
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");

		// require(Workers[_worker].cleaned,"no cleaned");

		if(CSDataInfo[msg.sender].CState == State.Stagnant){
			Workers[_worker].balance =Workers[_worker].balance.add(CSToFee[msg.sender].ShareFee);
			Requester[CSDataInfo[msg.sender].requester].balance =Requester[CSDataInfo[msg.sender].requester].balance.sub(CSToFee[msg.sender].ShareFee);
		}

		_balance = Workers[_worker].balance;
		//CS合约中去提钱，这里只改balance
		Workers[_worker].balance = 0;

		return _balance;
	}

	/*
	Role : R
	Function : R Get back the remaining deposit
	*/
	function withdrawR()
		external
		checkTimeOut(CSToTimeEnd[msg.sender].WWithdrawEnd)
		checkTimeIn(CSToTimeEnd[msg.sender].RWithdrawEnd)
		returns(uint _Rbalance)
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed,"Wrong State");
		require(Requester[CSDataInfo[msg.sender].requester].balance != 0,"no money");

		_Rbalance = Requester[CSDataInfo[msg.sender].requester].balance;
		Requester[CSDataInfo[msg.sender].requester].balance = 0;

		return _Rbalance;
	}

	/*
	Role : CW
	Function : W checks whether R is operating in violation of regulations
	*/
	function checkStagnant(address _worker)
		external
		checkIsCommiittee(_worker)
		checkTimeOut(CSToTimeEnd[msg.sender].StartTimeEnd)
		returns(int8 _value)
	{
		require(CSDataInfo[msg.sender].CState != State.Failed,"Wrong State");
		require(!CSDataInfo[msg.sender].Wchecked,"have checked");

		//如果他没开始的话，只需要扣1就行了，因为大家还没交钱没工作。
		if(!Requester[CSDataInfo[msg.sender].requester].startMission){
        	_value = 1;
        	CSDataInfo[msg.sender].Wchecked = true;

        }else{
        	if(!Requester[CSDataInfo[msg.sender].requester].checkSubmited){
        		if(block.timestamp > CSToTimeEnd[msg.sender].CheckTimeEnd){
        			_value = 4;
        			CSDataInfo[msg.sender].Wchecked = true;
        		}
        	}else{
        		if(!Requester[CSDataInfo[msg.sender].requester].evaluated){
        			if(block.timestamp > CSToTimeEnd[msg.sender].EvaluationTimeEnd){
        				_value = 5;
        				CSDataInfo[msg.sender].Wchecked = true;
        			}
        		}
        	}

        }

        if(CSDataInfo[msg.sender].Wchecked){
        	CSDataInfo[msg.sender].CState = State.Stagnant;
			emit LogCStateModified(msg.sender, _worker,block.timestamp, State.Stagnant);
        }
        
        //要帮R清理。.
        require(myTwoSubmisson.resetCSData(),"resetCSData error");

        CSToFee[msg.sender].ShareFee = Requester[CSDataInfo[msg.sender].requester].balance.div((CSToNumber[msg.sender].CleanedNum.add(1)));
        Workers[_worker].balance = Workers[_worker].balance.add(CSToFee[msg.sender].ShareFee);
        Requester[CSDataInfo[msg.sender].requester].balance = Requester[CSDataInfo[msg.sender].requester].balance.sub(CSToFee[msg.sender].ShareFee);

        return _value;
	}

	/*
	Role : CW
	Function : CW voluntarily withdrew from the committee
	*/
	function release(address _worker) 
		external
		checkIsCommiittee(_worker)
		checkTimeOut(CSToTimeEnd[msg.sender].WWithdrawEnd)
		returns(bool)
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");
		require(Workers[_worker].balance == 0);

        /*
        //没必要调整位置了，因为无论主动推出还是统一清楚都要删除工人信息
		CSToCommittee[msg.sender][Workers[_worker].workID] = CSToCommittee[msg.sender][CSToCommittee[msg.sender].length -1];
		Workers[CSToCommittee[msg.sender][CSToCommittee[msg.sender].length -1]].workID = Workers[_worker].workID;
		CSToCommittee[msg.sender].length--;
        */
		delete Workers[_worker];
		return true;
	}

	/*
	Role : R
	Function : R restart CS mission
	*/
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

		for(uint i = 0 ; i< CSToCommittee[msg.sender].length ;i=i.add(1)){
			if(Workers[CSToCommittee[msg.sender][i]].submited){
				CompletedID[i] = true;
				delete Workers[CSToCommittee[msg.sender][i]];
			}
		}

		delete Requester[CSDataInfo[msg.sender].requester];

		delete CSDataInfo[msg.sender].workIDToRightNumber;
		delete CSToCommittee[msg.sender];

		return CompletedID;
	}
/*
	function finishCS()
		external
		checkTimeOut(CSToTimeEnd[msg.sender].RWithdrawEnd)
		returns(bool[])
	{
		require(CSDataInfo[msg.sender].CState == State.Completed || CSDataInfo[msg.sender].CState == State.Failed || CSDataInfo[msg.sender].CState == State.Stagnant,"Wrong State");

		//不CLean CSM的数据了，因为下次子啊用必会清理，没必要花这个钱。

		bool[] memory CompletedID = new bool[](CSToCommittee[msg.sender].length);

		for(uint i = 0 ; i< CSToCommittee[msg.sender].length ;i=i.add(1)){
			if(Workers[CSToCommittee[msg.sender][i]].cleaned){
				CompletedID[i] = true;
				delete Workers[CSToCommittee[msg.sender][i]];
			}
		}
		return CompletedID;
	}
*/

	/*
	Role : R
	Function : Clear the data about this CS in CSM to prevent conflicts with the next task
	*/
	function cleanCSM() internal returns(bool) {
		if(CSDataInfo[msg.sender].CSInit){
			return true;
		}else{
			//检查W数据是否清除
			if(CSToCommittee[msg.sender].length != 0){//如果委员会没人，说明每一个W都退出，推出前一定会清掉自己的相关信息,即W信息已经clean
				for(uint i =0;i< CSToCommittee[msg.sender].length;i=i.add(1)){
					delete Workers[CSToCommittee[msg.sender][i]];
					// delete CSDataInfo[msg.sender].workIDToMissionID[i];//这个删不删无所谓，因为下次必然要等重新设置所有的才可以变为true
				}
			}
			delete CSToCommittee[msg.sender];
			//检查R及CS数据是否清除
			if(!CSDataInfo[msg.sender].CSInit){

				//clean CSData
				delete CSToCommittee[msg.sender];
				delete CSToText[msg.sender];
				delete CSToNumber[msg.sender];
				delete CSToFee[msg.sender];
				delete CSToTime[msg.sender];
				delete CSToTimeEnd[msg.sender];

				// Clean RData
				delete Requester[CSDataInfo[msg.sender].requester];
			}

			CSDataInfo[msg.sender].CSInit = true;

			return true;
		}

	}

    function getMissionID(uint _workID) public view returns(int[]memory){
        return  CSDataInfo[msg.sender].workIDToMissionID[_workID];
    }



}
