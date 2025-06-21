;; Authentication Protocol Contract
;; Manages authentication protocols and sessions

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PROVIDER (err u201))
(define-constant ERR_SESSION_EXISTS (err u202))
(define-constant ERR_SESSION_NOT_FOUND (err u203))
(define-constant ERR_SESSION_EXPIRED (err u204))

;; Session duration in blocks (approximately 24 hours)
(define-constant SESSION_DURATION u144)

;; Authentication methods
(define-constant AUTH_PASSWORD u1)
(define-constant AUTH_BIOMETRIC u2)
(define-constant AUTH_MFA u3)
(define-constant AUTH_CERTIFICATE u4)

;; Data structures
(define-map authentication-sessions
  { session-id: (string-ascii 64) }
  {
    user-principal: principal,
    provider-id: (string-ascii 64),
    auth-method: uint,
    created-at: uint,
    expires-at: uint,
    is-active: bool,
    last-activity: uint
  }
)

(define-map user-auth-history
  { user: principal, timestamp: uint }
  {
    provider-id: (string-ascii 64),
    auth-method: uint,
    success: bool,
    ip-hash: (buff 32)
  }
)

(define-data-var session-count uint u0)

;; Create authentication session
(define-public (create-auth-session (session-id (string-ascii 64))
                                   (provider-id (string-ascii 64))
                                   (auth-method uint))
  (let ((existing-session (map-get? authentication-sessions { session-id: session-id }))
        (expires-at (+ block-height SESSION_DURATION)))
    (if (is-some existing-session)
      ERR_SESSION_EXISTS
      (begin
        (map-set authentication-sessions
          { session-id: session-id }
          {
            user-principal: tx-sender,
            provider-id: provider-id,
            auth-method: auth-method,
            created-at: block-height,
            expires-at: expires-at,
            is-active: true,
            last-activity: block-height
          }
        )
        (var-set session-count (+ (var-get session-count) u1))
        (ok session-id)
      )
    )
  )
)

;; Validate authentication session
(define-public (validate-session (session-id (string-ascii 64)))
  (match (map-get? authentication-sessions { session-id: session-id })
    session-data
    (if (and (get is-active session-data)
             (< block-height (get expires-at session-data)))
      (begin
        (map-set authentication-sessions
          { session-id: session-id }
          (merge session-data { last-activity: block-height })
        )
        (ok true)
      )
      ERR_SESSION_EXPIRED
    )
    ERR_SESSION_NOT_FOUND
  )
)

;; Terminate authentication session
(define-public (terminate-session (session-id (string-ascii 64)))
  (match (map-get? authentication-sessions { session-id: session-id })
    session-data
    (if (is-eq tx-sender (get user-principal session-data))
      (begin
        (map-set authentication-sessions
          { session-id: session-id }
          (merge session-data { is-active: false })
        )
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
    ERR_SESSION_NOT_FOUND
  )
)

;; Record authentication attempt
(define-public (record-auth-attempt (provider-id (string-ascii 64))
                                   (auth-method uint)
                                   (success bool)
                                   (ip-hash (buff 32)))
  (begin
    (map-set user-auth-history
      { user: tx-sender, timestamp: block-height }
      {
        provider-id: provider-id,
        auth-method: auth-method,
        success: success,
        ip-hash: ip-hash
      }
    )
    (ok true)
  )
)

;; Get session information
(define-read-only (get-session (session-id (string-ascii 64)))
  (map-get? authentication-sessions { session-id: session-id })
)

;; Check if session is valid
(define-read-only (is-session-valid (session-id (string-ascii 64)))
  (match (map-get? authentication-sessions { session-id: session-id })
    session-data
    (and (get is-active session-data)
         (< block-height (get expires-at session-data)))
    false
  )
)

;; Get user authentication history
(define-read-only (get-auth-history (user principal) (timestamp uint))
  (map-get? user-auth-history { user: user, timestamp: timestamp })
)

;; Get total session count
(define-read-only (get-session-count)
  (var-get session-count)
)
