;; Implement the `ft-trait` trait defined in the `ft-trait` contract - SIP 10
;; This can use sugared syntax in real deployment (unit tests do not allow)
(impl-trait 'ST3J2GVMMM2R07ZFBJDWTYEYAR8FZH5WKDTFJ9AHA.ft-trait.ft-trait)

;; ;; Implement the metadata URI trait
(impl-trait 'ST3J2GVMMM2R07ZFBJDWTYEYAR8FZH5WKDTFJ9AHA.metadata-uri-token-trait.metadata-uri-token-trait)

;; ;; Implement the token restriction trait
(impl-trait 'ST3J2GVMMM2R07ZFBJDWTYEYAR8FZH5WKDTFJ9AHA.restricted-token-trait.restricted-token-trait)

;; Error returned for permission denied - stolen from http 403
(define-constant PERMISSION_DENIED_ERROR u403)

;; Data variables specific to the deployed token contract
(define-data-var token-name (string-ascii 32) "")
(define-data-var token-symbol (string-ascii 32) "")
(define-data-var token-decimals uint u0)

;; Track who deployed the token and whether it has been initialized
(define-data-var deployer-principal principal tx-sender)
(define-data-var is-initialized bool false)

;; Meta Read Only Functions for reading details about the contract - conforms to SIP 10
;; --------------------------------------------------------------------------

;; Defines built in support functions for tokens used in this contract
(define-fungible-token tokensoft-token)

;; Get the token balance of the specified owner in base units
(define-read-only (balance-of (owner principal))
  (ok (ft-get-balance tokensoft-token owner)))

;; Returns the token name
(define-read-only (name)
  (ok (var-get token-name)))

;; Returns the symbol or "ticker" for this token
(define-read-only (symbol)
  (ok (var-get token-symbol)))

;; Returns the number of decimals used
(define-read-only (decimals)
  (ok (var-get token-decimals)))

;; Returns the total number of tokens that currently exist
(define-read-only (total-supply)
  (ok (ft-get-supply tokensoft-token)))


;; Write function to transfer tokens between accounts - conforms to SIP 10
;; --------------------------------------------------------------------------

;; Transfers tokens to a recipient
;; The originator of the transaction (tx-sender) must be the 'sender' principal
;; Smart contracts can move tokens from their own address by calling transfer with the 'as-contract' modifier to override the tx-sender.
(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (if (is-eq (unwrap-panic (detect-transfer-restriction amount sender recipient)) u0)
    (if (is-eq tx-sender sender)
      (ft-transfer? tokensoft-token amount sender recipient)
      (err u4))
    (err PERMISSION_DENIED_ERROR))) ;; TODO: get feedback on how to handle error codes


;; Role Based Access Control
;; --------------------------------------------------------------------------
(define-constant OWNER_ROLE u0) ;; Can manage RBAC
(define-constant MINTER_ROLE u1) ;; Can mint new tokens to any account
(define-constant BURNER_ROLE u2) ;; Can burn tokens from any account
(define-constant REVOKER_ROLE u3) ;; Can revoke tokens and move them to any account
(define-constant BLACKLISTER_ROLE u4) ;; Can add principals to a blacklist that can prevent transfers

;; Each role will have a mapping of principal to boolean.  A true "allowed" in the mapping indicates that the principal has the role.
;; Each role will have special permissions to modify or manage specific capabilities in the contract.
;; Note that adding/removing roles could be optimized by having just 1 function, but since this is sensitive functionality, it was split
;;    into 2 separate functions to make it explicit.
;; See the Readme about more details on the RBAC setup.
(define-map roles { role: uint, account: principal } { allowed: bool })

;; Checks if an account has the specified role
(define-read-only (has-role (role-to-check uint) (principal-to-check principal))
  (if 
    (is-eq 
      (default-to false (get allowed (map-get? roles {role: role-to-check, account: principal-to-check}))) 
      true )
    true
    false))

;; Add a principal to the specified role
;; Only existing principals with the OWNER_ROLE can modify roles
(define-public (add-principal-to-role (role-to-add uint) (principal-to-add principal))
   ;; Check the contract-caller to verify they have the owner role
   (if (has-role OWNER_ROLE contract-caller)
      (ok (map-set roles { role: role-to-add, account: principal-to-add } { allowed: true }))
      (err PERMISSION_DENIED_ERROR)))

;; Remove a principal from the specified role
;; Only existing principals with the OWNER_ROLE can modify roles
;; WARN: Removing all owners will irrevocably lose all ownership permissions
(define-public (remove-principal-from-role (role-to-remove uint) (principal-to-remove principal))
   ;; Check the contract-caller to verify they have the owner role
   (if (has-role OWNER_ROLE contract-caller)
      (ok (map-set roles { role: role-to-remove, account: principal-to-remove } { allowed: false }))
      (err PERMISSION_DENIED_ERROR)))


;; Token URI
;; --------------------------------------------------------------------------

;; Variable for URI storage
(define-data-var uri (string-utf8 1024) u"")

;; Public getter for the URI
(define-read-only (token-uri)
  (ok (var-get uri)))

;; Setter for the URI - only the owner can set it
(define-public (set-token-uri (updated-uri (string-utf8 1024)))
  (if (has-role OWNER_ROLE contract-caller)
    (ok (var-set uri updated-uri))
    (err PERMISSION_DENIED_ERROR)))

;; Minting and Burning
;; --------------------------------------------------------------------------

;; Mint tokens to the target address
;; Only existing principals with the MINTER_ROLE can mint tokens
(define-public (mint-tokens (mint-amount uint) (mint-to principal) )
  (if (has-role MINTER_ROLE contract-caller)
    (ft-mint? tokensoft-token mint-amount mint-to)
    (err PERMISSION_DENIED_ERROR)))

;; Mint tokens to the target address
;; Only existing principals with the MINTER_ROLE can mint tokens
(define-public (burn-tokens (burn-amount uint) (burn-from principal) )
  (if (has-role BURNER_ROLE contract-caller)
    (ft-burn? tokensoft-token burn-amount burn-from)
    (err PERMISSION_DENIED_ERROR)))


;; Revoking Tokens
;; --------------------------------------------------------------------------

;; Moves tokens from one account to another
;; Only existing principals with the REVOKER_ROLE can revoke tokens
(define-public (revoke-tokens (revoke-amount uint) (revoke-from principal) (revoke-to principal) )
  (if (has-role REVOKER_ROLE contract-caller)
    (ft-transfer? tokensoft-token revoke-amount revoke-from revoke-to)
    (err PERMISSION_DENIED_ERROR)))


;; Blacklisting Principals
;; --------------------------------------------------------------------------

;; Blacklist mapping.  If an account has blacklisted = true then no transfers in or out are allowed
(define-map blacklist { account: principal } { blacklisted: bool })

;; Checks if an account is blacklisted
(define-read-only (is-blacklisted (principal-to-check principal))
  (default-to false (get blacklisted (map-get? blacklist { account: principal-to-check }))))

;; Updates an account's blacklist status
;; Only existing principals with the BLACKLISTER_ROLE can update blacklist status
(define-public (update-blacklisted (principal-to-update principal) (set-blacklisted bool))
  (if (has-role BLACKLISTER_ROLE contract-caller)
    (ok (map-set blacklist { account: principal-to-update } { blacklisted: set-blacklisted }))
    (err PERMISSION_DENIED_ERROR)))

;; Transfer Restrictions
;; --------------------------------------------------------------------------
(define-constant RESTRICTION_NONE u0) ;; No restriction detected
(define-constant RESTRICTION_BLACKLIST u1) ;; Sender or receiver is on the blacklist

;; Checks to see if a transfer should be restricted.  If so returns an error code that specifies restriction type.
(define-read-only (detect-transfer-restriction (amount uint) (sender principal) (recipient principal))
  (if (or (is-blacklisted sender) (is-blacklisted recipient))
    (ok RESTRICTION_BLACKLIST)
    (ok RESTRICTION_NONE)))

;; Returns the user viewable string for a specific transfer restriction
(define-read-only (message-for-restriction (restriction-code uint))
  (if (is-eq restriction-code RESTRICTION_NONE)
    (ok u"No Restriction Detected")
    (if (is-eq restriction-code RESTRICTION_BLACKLIST)
      (ok u"Sender or recipient is on the blacklist and prevented from transacting")
      (ok u"Unknown Error Code"))))


;; Initialization
;; --------------------------------------------------------------------------

;; Check to ensure that the same account that deployed the contract is initializing it
;; Only allow this funtion to be called once by checking "is-initialized"
(define-public (initialize (name-to-set (string-ascii 32)) (symbol-to-set (string-ascii 32) ) (decimals-to-set uint) (initial-owner principal))
  (if 
    (and 
      (is-eq tx-sender (var-get deployer-principal))
      (not (var-get is-initialized)))
    (begin 
      (var-set is-initialized true) ;; Set to true so that this can't be called again
      (var-set token-name name-to-set)
      (var-set token-symbol symbol-to-set)
      (var-set token-decimals decimals-to-set)
      (map-set roles { role: OWNER_ROLE, account: initial-owner } { allowed: true })
      (ok true))
    (err PERMISSION_DENIED_ERROR)))

