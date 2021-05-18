// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.7.0;

import "./safemath.sol";

/*
 * The TwoSubmission contract(TPS) is mainly responsible for storing crowdsourcing data and implementing functions such as two-phase submission and quality inspection
 * ==========================================
 *  Title: TwoSubmission Contracts for DCrowd.
 *  Author: Huajian Wang.
 *  Email: wanghuajian19@nudt.edu.cn.
 *  
 * ==========================================
 */

contract TwoSubmission{
	
	using SafeMath for uint;
	using SafeMath for int;

	//Each CS corresponds to an EnrollData, and records the forecast name and registration information of the registered W.
	struct EnrollData{
		bool used;
		uint[] keyArray;
		mapping(address => bytes32) AddrToMessage;
		mapping(address => uint) AddrToRandomKey;	
	}
	mapping(address => EnrollData)  CSToEnrollData;

	function getEnrollData(address _CSContract, address  _worker)public view returns(bool, uint[] memory,bytes32,uint){
		return (CSToEnrollData[_CSContract].used,CSToEnrollData[_CSContract].keyArray,CSToEnrollData[_CSContract].AddrToMessage[_worker],CSToEnrollData[_CSContract].AddrToRandomKey[_worker]);
	}

	//Each registered W corresponds to a WorkerData, and records the basic information of the registered W.
	struct WorkerData {
		bool used;
		bool missionIDSeted;
		bytes32 sealedMessage;
		int[] tableArray;
		int[] missionID;
	}
	mapping(address => WorkerData) public AddrToWorkerData;

	function getWorkerData(address _worker) public view returns(bool, bool,bytes32,int[] memory,int[] memory) {
		return (AddrToWorkerData[_worker].used,AddrToWorkerData[_worker].missionIDSeted,AddrToWorkerData[_worker].sealedMessage,AddrToWorkerData[_worker].tableArray,AddrToWorkerData[_worker].missionID);
	}

	//Each CS that has been successfully released corresponds to a CSData that records the basic information of the crowdsourcing mission.
	struct CSData {
		bool used;
		uint RightNumberNeed;
		uint imageNumber;
	    mapping(int => uint) resultcount;
	    int[] results;
	}
	mapping(address => CSData) public CSToData;
	
	function getCSData(address _CSContract) public view returns(bool,uint,uint,int[] memory) {
		return (CSToData[_CSContract].used,CSToData[_CSContract].RightNumberNeed,CSToData[_CSContract].imageNumber,CSToData[_CSContract].results);
	}

	/*
	Role : CW
	Function : CW clears this or previous data of the crowdsourced address
	*/
	function resetURData(address _worker) public returns(bool) {

		if(!AddrToWorkerData[_worker].used)
			return true;
		else{
			delete AddrToWorkerData[_worker];
			AddrToWorkerData[_worker].used = false;
			return true;
		}
	}

	/*
	Role : R
	Function : R clears this or previous data of the crowdsourced address
	*/
	function resetCSData() public returns(bool){

		if(!CSToData[msg.sender].used)
			return true;
		else{
			if(CSToData[msg.sender].results.length != 0){
				for(uint i = 0 ; i < CSToData[msg.sender].results.length;i = i.add(1))
					delete CSToData[msg.sender].resultcount[CSToData[msg.sender].results[i]];
			}
			delete CSToData[msg.sender];
			CSToData[msg.sender].used = false;
			return true;
		}

	}

	/*
	Role : R
	Function : R clears this or previous data of EnrollData
	*/
	function resetEnrollData(address _CSContract,address[] memory _enrollAddrs) external returns(bool) {

		if(!CSToEnrollData[_CSContract].used){
			return true;
		}else{
			for(uint i = 0;i < _enrollAddrs.length;i = i.add(1)){
				delete CSToEnrollData[_CSContract].AddrToMessage[_enrollAddrs[i]];
				delete CSToEnrollData[_CSContract].AddrToRandomKey[_enrollAddrs[i]];
			}
			delete CSToEnrollData[_CSContract];

			CSToEnrollData[_CSContract].used = false;

			return true;
		}
	}

	/*
	Role : W & R
	Function : W or R Sign up for a specific crowdsourcing task in the first stage
	*/
	function preEnroll(address _CSContract, address _worker, bytes32 _sealedrandom) external returns(bool){

		if(!CSToEnrollData[_CSContract].used)
			CSToEnrollData[_CSContract].used = true;

		CSToEnrollData[_CSContract].AddrToMessage[_worker] = _sealedrandom;

		return true;
	}

	/*
	Role : W & R
	Function : W or R Sign up for a specific crowdsourcing task in the second stage
	*/
	function enroll(address _CSContract, address _worker, uint _randomKey) external returns(bool) {

		require(keccak256(abi.encodePacked(_randomKey)) == CSToEnrollData[_CSContract].AddrToMessage[_worker],"Not same");

		CSToEnrollData[_CSContract].AddrToRandomKey[_worker] = _randomKey;
		CSToEnrollData[_CSContract].keyArray.push(_randomKey);
		
		return true;
	}


	function getKeyArraySum(address _CSContract) external view returns(uint){
		uint sum = 0;
		for(uint i = 0;i < CSToEnrollData[_CSContract].keyArray.length; i = i.add(1))
			sum =sum.add(CSToEnrollData[_CSContract].keyArray[i]);
		
		return sum;
	}

	/*
	Role : R
	Function : R upload task ID of WC
	*/
	function missionID(address _worker,int[] memory _missionID ,uint _imageNum) external returns(bool) {

		require(resetURData(_worker));

		if(!CSToData[msg.sender].used)
			CSToData[msg.sender].used = true;

		if(!AddrToWorkerData[_worker].used)
			AddrToWorkerData[_worker].used = true;

		CSToData[msg.sender].imageNumber = _imageNum;

		for(uint i =0 ; i< _imageNum ; i = i.add(1)){
			AddrToWorkerData[_worker].tableArray.push(-1);
		}

		AddrToWorkerData[_worker].missionID = _missionID;
		AddrToWorkerData[_worker].missionIDSeted = true;

		return true;
	}

	/*
	Role : CW
	Function : CW pre-submission crowdsourcing commitments
	*/
	function presubmit(address _submitter, bytes32 _sealedMessage,address[]  memory _addrs)public returns(bool)
	{
		bool same;
		for(uint i = 0; i < _addrs.length;i = i.add(1)){
			if(_sealedMessage == AddrToWorkerData[_addrs[i]].sealedMessage){
				same = true;
			}
		}

		require(!same,"have same");

		AddrToWorkerData[_submitter].sealedMessage = _sealedMessage;
		return true;
	}

	/*
	Role : CW
	Function : CW public crowdsourcing results and random numbers
	*/
	function submit(address _submitter, int[] memory _message ,uint _randomKey) public returns(bool){

		for(uint i = 0; i < _message.length ; i = i.add(1)){

			if(AddrToWorkerData[_submitter].missionID[i] == -1)
				require(_message[i] == -1,"Wrong missionID");
			else
				require(_message[i] >=0 && _message[i] < 10,"Wrong Table");
		}
		
		require(keccak256(abi.encodePacked(_message,_randomKey)) == AddrToWorkerData[_submitter].sealedMessage,"Not same");

		AddrToWorkerData[_submitter].tableArray = _message;

		return true;
	}

	/*
	Role : R
	Function : Calculate the correct answer according to the convention
	
	function evaluation(address[] memory _addrs,uint[] memory _workIDToRightNum,int[] memory _rightTable, uint _submitNum)public returns(uint[] memory,int[] memory){

		CSToData[msg.sender].RightNumberNeed = (_submitNum.div(2)).add(1);//可以放到上个函数

		for(uint i =0; i< _addrs.length;i = i.add(1)){

			uint rightTableCount = 0;
			for(uint j = 0;j < CSToData[msg.sender].imageNumber; j =j.add(1)){
				uint equallCount = 0;
				if(AddrToWorkerData[_addrs[i]].tableArray[j] != -1){
					for(uint k =0 ; k< _addrs.length ; k = k.add(1)){
						if(AddrToWorkerData[_addrs[i]].tableArray[j] == AddrToWorkerData[_addrs[k]].tableArray[j])
							equallCount =equallCount.add(1);
					}
				}

				if(equallCount >= CSToData[msg.sender].RightNumberNeed){
					rightTableCount = rightTableCount.add(1);
					if(_rightTable[j] != AddrToWorkerData[_addrs[i]].tableArray[j])
					   	_rightTable[j] = AddrToWorkerData[_addrs[i]].tableArray[j];
				}
			}
			_workIDToRightNum[i] = rightTableCount;
			//计算报酬在主函数中
		}
		return (_workIDToRightNum , _rightTable);
	}
// ["0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db","0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB","0x617F2E2fD72FD9D5503197092aC168c91465E7f2","0x17F6AD8Ef982297579C203069C1DbfFE4348c372","0x5c6B0f7Bf3E7ce046039Bd8FABdfD3f9F5021678"]
	*/

	/*
	Role : R
	Function : Calculate the correct answer according to the convention
	*/
	function evaluation2(address[] memory _addrs, int[] memory _rightTable, uint _submitNum) public returns(int[] memory) {

		CSToData[msg.sender].RightNumberNeed = (_submitNum.div(2)).add(1);

		for(uint j = 0;j < CSToData[msg.sender].imageNumber; j=j.add(1)){

			int MaxResult = -1;
			uint MaxResultCount = 0;
			bool MaxMul = false;

			for(uint i = 0 ; i < _addrs.length ; i = i.add(1)){
				if(AddrToWorkerData[_addrs[i]].tableArray[j] != -1){
					CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[i]].tableArray[j]] = CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[i]].tableArray[j]].add(1);

					if(CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[i]].tableArray[j]] == 1){
						CSToData[msg.sender].results.push(AddrToWorkerData[_addrs[i]].tableArray[j]);
					}
					
					if(CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[i]].tableArray[j]] == MaxResultCount){
						MaxMul = true;
					}
					if(CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[i]].tableArray[j]] > MaxResultCount){
						MaxResult = AddrToWorkerData[_addrs[i]].tableArray[j];
						MaxResultCount = CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[i]].tableArray[j]];
						MaxMul = false;
					}
					
				}
			}

			if((MaxMul == false) &&(MaxResultCount >= CSToData[msg.sender].RightNumberNeed)){
				_rightTable[j] = MaxResult;
			}

			for(uint k = 0 ;k < _addrs.length ; k=k.add(1)){
				if(AddrToWorkerData[_addrs[k]].tableArray[j] != -1){
					delete CSToData[msg.sender].resultcount[AddrToWorkerData[_addrs[k]].tableArray[j]];
				}
			}
		}
		
		return _rightTable;
	}

	/*
	Role : R
	Function : Quality assessment based on correct answers
	*/
	function evaluation2_cal(address[]memory _addrs, uint[]memory _workIDToRightNum, int[]memory _rightTable)public view returns(uint[]memory){
	    
	    for(uint i = 0; i < _addrs.length ; i = i.add(1)){
			uint rightTableCount = 0;
			for(uint j = 0 ; j < CSToData[msg.sender].imageNumber; j=j.add(1)){
				if(AddrToWorkerData[_addrs[i]].tableArray[j] != -1){
					if(AddrToWorkerData[_addrs[i]].tableArray[j] == _rightTable[j])
						rightTableCount = rightTableCount.add(1);
				}
			}

			_workIDToRightNum[i] = rightTableCount;
		}
		return _workIDToRightNum;
	}
}
