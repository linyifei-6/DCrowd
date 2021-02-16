// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.7.0;
contract TwoSubmission{

	//每个CS对应一个,记录已报名UR的预报名和报名信息。
	struct EnrollData{
		bool used;//false就没事了
		uint[] keyArray;
		mapping(address => bytes32) AddrToMessage;
		mapping(address => uint) AddrToRandomKey;
		
	}
	mapping(address => EnrollData)  CSToEnrollData;

	function getEnrollData(address _CSContract, address  _crowdUR)public view returns(bool, uint[] memory,bytes32,uint){
		return (CSToEnrollData[_CSContract].used,CSToEnrollData[_CSContract].keyArray,CSToEnrollData[_CSContract].AddrToMessage[_crowdUR],CSToEnrollData[_CSContract].AddrToRandomKey[_crowdUR]);
	}

	struct CrowdURData {
		bool used;
		bool missionIDSeted;
		bytes32 sealedMessage;
		int[] tableArray;
		int[] missionID;
	}
	mapping(address => CrowdURData) public AddrToCrowdURData;

	function getCrowdURData(address _crowdUR) public view returns(bool, bool,bytes32,int[] memory,int[] memory) {
		return (AddrToCrowdURData[_crowdUR].used,AddrToCrowdURData[_crowdUR].missionIDSeted,AddrToCrowdURData[_crowdUR].sealedMessage,AddrToCrowdURData[_crowdUR].tableArray,AddrToCrowdURData[_crowdUR].missionID);
	}

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
	//UR
	function resetURData(address _crowdUR) public returns(bool) {

		if(!AddrToCrowdURData[_crowdUR].used)
			return true;
		else{
			delete AddrToCrowdURData[_crowdUR];
			AddrToCrowdURData[_crowdUR].used = false;
			return true;
		}
	}

	//UT
	function resetCSData() public returns(bool){

		if(!CSToData[msg.sender].used)
			return true;
		else{
			if(CSToData[msg.sender].results.length != 0){
				for(uint i = 0 ; i < CSToData[msg.sender].results.length;i++)
					delete CSToData[msg.sender].resultcount[CSToData[msg.sender].results[i]];
			}
			delete CSToData[msg.sender];
			CSToData[msg.sender].used = false;
			return true;
		}

	}
	
	function resetEnrollData(address _CSContract,address[] memory _enrollAddrs) external returns(bool) {

		if(!CSToEnrollData[_CSContract].used){
			return true;
		}else{
			for(uint i = 0;i < _enrollAddrs.length;i++){
				delete CSToEnrollData[_CSContract].AddrToMessage[_enrollAddrs[i]];
				delete CSToEnrollData[_CSContract].AddrToRandomKey[_enrollAddrs[i]];
			}
			delete CSToEnrollData[_CSContract];

			CSToEnrollData[_CSContract].used = false;

			return true;
		}


	}

	// 两阶段选人：往后稍稍
	function preEnroll(address _CSContract, address _crowdUR, bytes32 _sealedrandom) external returns(bool){

		if(!CSToEnrollData[_CSContract].used)
			CSToEnrollData[_CSContract].used = true;

		CSToEnrollData[_CSContract].AddrToMessage[_crowdUR] = _sealedrandom;

		return true;
	}

	function enroll(address _CSContract, address _crowdUR, uint _randomKey) external returns(bool) {

		require(keccak256(abi.encodePacked(_randomKey)) == CSToEnrollData[_CSContract].AddrToMessage[_crowdUR],"Not same");

		CSToEnrollData[_CSContract].AddrToRandomKey[_crowdUR] = _randomKey;
		CSToEnrollData[_CSContract].keyArray.push(_randomKey);
		
		return true;
	}

	function getKeyArraySum(address _CSContract) external view returns(uint){
		uint sum = 0;
		for(uint i = 0;i < CSToEnrollData[_CSContract].keyArray.length; i++)
			sum += CSToEnrollData[_CSContract].keyArray[i];
		
		return sum;
	}

	function missionID(address _crowdUR,int[] memory _missionID ,uint _imageNum) external returns(bool) {

		require(resetURData(_crowdUR));

		if(!CSToData[msg.sender].used)
			CSToData[msg.sender].used = true;

		if(!AddrToCrowdURData[_crowdUR].used)
			AddrToCrowdURData[_crowdUR].used = true;

		CSToData[msg.sender].imageNumber = _imageNum;

		for(uint i =0 ; i< _imageNum ; i++){
			AddrToCrowdURData[_crowdUR].tableArray.push(-1);//初始化标签数组为-1,为什么有此操作？如果没有的话，评估函数要改
		}//存储太贵了！！！,1个256的槽就要20000，100个就算两百万

		AddrToCrowdURData[_crowdUR].missionID = _missionID;
		AddrToCrowdURData[_crowdUR].missionIDSeted = true;

		return true;
	}

	function presubmit(address _submitter, bytes32 _sealedMessage,address[]  memory _addrs)public returns(bool)
	{
		bool same;
		for(uint i = 0; i < _addrs.length;i++){
			if(_sealedMessage == AddrToCrowdURData[_addrs[i]].sealedMessage){
				same = true;
			}
		}

		require(!same,"have same");

		AddrToCrowdURData[_submitter].sealedMessage = _sealedMessage;
		return true;
	}

	function submit(address _submitter, int[] memory _message ,uint _randomKey) public returns(bool){

		for(uint i = 0; i < _message.length ; i++){

			if(AddrToCrowdURData[_submitter].missionID[i] == -1)
				require(_message[i] == -1,"Wrong missionID");
			else
				require(_message[i] >=0 && _message[i] < 10,"Wrong Table");
		}
		
		require(keccak256(abi.encodePacked(_message,_randomKey)) == AddrToCrowdURData[_submitter].sealedMessage,"Not same");

		AddrToCrowdURData[_submitter].tableArray = _message;

		return true;
	}

	function evaluation(address[] memory _addrs,uint[] memory _workIDToRightNum,int[] memory _rightTable, uint _submitNum)public returns(uint[] memory,int[] memory){

		CSToData[msg.sender].RightNumberNeed = _submitNum / 2 + 1;//可以放到上个函数

		for(uint i =0; i< _addrs.length;i++){

			uint rightTableCount = 0;
			for(uint j = 0;j < CSToData[msg.sender].imageNumber; j++){
				uint equallCount = 0;
				if(AddrToCrowdURData[_addrs[i]].tableArray[j] != -1){
					for(uint k =0 ; k< _addrs.length ; k++){
						if(AddrToCrowdURData[_addrs[i]].tableArray[j] == AddrToCrowdURData[_addrs[k]].tableArray[j])
							equallCount++;
					}
				}

				if(equallCount >= CSToData[msg.sender].RightNumberNeed){
					rightTableCount++;
					if(_rightTable[j] != AddrToCrowdURData[_addrs[i]].tableArray[j])
					   	_rightTable[j] = AddrToCrowdURData[_addrs[i]].tableArray[j];
				}
			}
			_workIDToRightNum[i] = rightTableCount;
			//计算报酬在主函数中
		}
		return (_workIDToRightNum , _rightTable);
	}
// ["0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db","0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB","0x617F2E2fD72FD9D5503197092aC168c91465E7f2","0x17F6AD8Ef982297579C203069C1DbfFE4348c372","0x5c6B0f7Bf3E7ce046039Bd8FABdfD3f9F5021678"]


	function evaluation2(address[] memory _addrs, int[] memory _rightTable, uint _submitNum) public returns(int[] memory) {

		CSToData[msg.sender].RightNumberNeed = _submitNum / 2 + 1;

		for(uint j = 0;j < CSToData[msg.sender].imageNumber; j++){

			int MaxResult = -1;
			uint MaxResultCount = 0;
			bool MaxMul = false;

			for(uint i = 0 ; i < _addrs.length ; i++){
				if(AddrToCrowdURData[_addrs[i]].tableArray[j] != -1){
					CSToData[msg.sender].resultcount[AddrToCrowdURData[_addrs[i]].tableArray[j]]++;

					if(CSToData[msg.sender].resultcount[AddrToCrowdURData[_addrs[i]].tableArray[j]] == 1){
						CSToData[msg.sender].results.push(AddrToCrowdURData[_addrs[i]].tableArray[j]);
					}
					
					if(CSToData[msg.sender].resultcount[AddrToCrowdURData[_addrs[i]].tableArray[j]] == MaxResultCount){
						MaxMul = true;
					}
					if(CSToData[msg.sender].resultcount[AddrToCrowdURData[_addrs[i]].tableArray[j]] > MaxResultCount){
						MaxResult = AddrToCrowdURData[_addrs[i]].tableArray[j];
						MaxResultCount = CSToData[msg.sender].resultcount[AddrToCrowdURData[_addrs[i]].tableArray[j]];
						MaxMul = false;
					}
					
				}
			}

			if((MaxMul == false) &&(MaxResultCount >= CSToData[msg.sender].RightNumberNeed)){
				_rightTable[j] = MaxResult;
			}

			for(uint k = 0 ;k < _addrs.length ; k++){
				if(AddrToCrowdURData[_addrs[k]].tableArray[j] != -1){
					delete CSToData[msg.sender].resultcount[AddrToCrowdURData[_addrs[k]].tableArray[j]];
				}
			}
		}
		
		return _rightTable;
	}
	
	function evaluation2_cal(address[]memory _addrs, uint[]memory _workIDToRightNum, int[]memory _rightTable)public view returns(uint[]memory){
	    
	    for(uint i = 0; i < _addrs.length ; i++){
			uint rightTableCount = 0;
			for(uint j = 0 ; j < CSToData[msg.sender].imageNumber; j++){
				if(AddrToCrowdURData[_addrs[i]].tableArray[j] != -1){
					if(AddrToCrowdURData[_addrs[i]].tableArray[j] == _rightTable[j])
						rightTableCount++;
				}
			}

			_workIDToRightNum[i] = rightTableCount;
		}
		return _workIDToRightNum;
	}


}
