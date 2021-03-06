# DCrowd
DCrowd: A Decentralized Service Model for Credible Crowdsourcing based on Game Theory and Smart Contracts

According to the two-phase submission mechanism and payment function, we have implemented a prototype system,DCrowd, based on smart contracts using Solidity programming.In general, our DCrowd system contains two entity roles: R and W(CW)and four smart contracts: UM, CS, CSM,and TPS.

TPS is mainly responsible for storing crowdsourcing data and implementing functions such as two-phase submission and quality inspection. 
CSM stipulates various operations after the crowdsourcing activity starts, and is responsible for implementing the crowdsourcing process and managing the state of the crowdsourcing contract. These two smart contracts have been deployed on the blockchain before the crowdsourcing activity starts for participants to review. 
UM is mainly responsible for managing various information of users, including status, reputation, signed contracts, etc. Everyordinary user needs to register as a member of the system in UM. At this time, its reputation of R and reputation of W are initialized to 100. If the user wants to publish a task, he just needs to call the interface “GenCSContract” to produce his crowdsourcing contract CS. 
CS actually provides various interfaces in CSM for users to call. UM and CS are contracts that directly interact with users.

