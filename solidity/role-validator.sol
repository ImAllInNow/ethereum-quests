pragma solidity ^0.4.18;

/* NOTE: This will be an external contract that performs the role validation.
 *       This contract could be a Token-curated Registry such as one provided by
 *       MedCredits to verifiy that the public address passed is indeed the role desired. 
*/
contract RoleValidation {
    function validateRole(address _user, bytes32 _role) public view returns (bool) {
        return true;
    }
}
