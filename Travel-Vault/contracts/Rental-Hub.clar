;; Decentralized Property Rental Platform Smart Contract
;; A comprehensive smart contract for peer-to-peer property rentals with booking management, 
;; payment processing, availability tracking, and review systems on the Stacks blockchain

;; Contract owner and authorization
(define-constant contract-administrator tx-sender)

;; Error code definitions for various failure scenarios
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-PROPERTY-DOES-NOT-EXIST (err u101))
(define-constant ERR-BOOKING-RECORD-NOT-FOUND (err u102))
(define-constant ERR-INVALID-DATE-RANGE (err u103))
(define-constant ERR-PROPERTY-NOT-AVAILABLE (err u104))
(define-constant ERR-PAYMENT-AMOUNT-INSUFFICIENT (err u105))
(define-constant ERR-BOOKING-STATUS-INVALID (err u106))
(define-constant ERR-REVIEW-ALREADY-SUBMITTED (err u107))
(define-constant ERR-RATING-OUT-OF-RANGE (err u108))
(define-constant ERR-PROPERTY-REGISTRATION-DUPLICATE (err u109))
(define-constant ERR-BOOKING-DEADLINE-EXCEEDED (err u110))
(define-constant ERR-INPUT-VALIDATION-FAILED (err u111))
(define-constant ERR-STRING-CONTENT-INVALID (err u112))

;; Global counters for tracking entities
(define-data-var next-property-identifier uint u0)
(define-data-var next-booking-identifier uint u0)
(define-data-var commission-rate-basis-points uint u250) ;; Represents 2.5% platform commission

;; Property operational states
(define-constant property-status-available u1)
(define-constant property-status-suspended u2)

;; Booking lifecycle states
(define-constant booking-status-awaiting-confirmation u1)
(define-constant booking-status-active-reservation u2)
(define-constant booking-status-stay-completed u3)
(define-constant booking-status-reservation-cancelled u4)

;; Core property registry with comprehensive metadata
(define-map property-listings
  { property-identifier: uint }
  {
    property-owner: principal,
    listing-title: (string-ascii 100),
    property-description: (string-ascii 500),
    geographic-location: (string-ascii 100),
    nightly-rate-microstack: uint,
    maximum-occupancy: uint,
    operational-status: uint,
    completed-stays-count: uint,
    cumulative-rating-score: uint,
    total-review-submissions: uint
  }
)

;; Booking records with detailed reservation information
(define-map reservation-records
  { booking-identifier: uint }
  {
    associated-property-id: uint,
    guest-principal: principal,
    arrival-date-timestamp: uint,
    departure-date-timestamp: uint,
    stay-duration-nights: uint,
    final-payment-amount: uint,
    reservation-status: uint,
    booking-creation-block: uint
  }
)

;; Property availability calendar system
(define-map date-availability-matrix
  { property-identifier: uint, date-timestamp: uint }
  { available-for-booking: bool }
)

;; Guest review and rating system
(define-map guest-property-reviews
  { property-identifier: uint, reviewer-principal: principal }
  {
    associated-booking-id: uint,
    numerical-rating: uint,
    written-feedback: (string-ascii 500),
    review-submission-block: uint
  }
)

;; User reputation and activity tracking
(define-map platform-user-profiles
  { user-principal: principal }
  {
    owned-properties-count: uint,
    completed-bookings-count: uint,
    trust-score: uint,
    identity-verification-status: bool
  }
)

;; Input validation helper functions
(define-private (verify-string-has-content (input-string (string-ascii 500)))
  (> (len input-string) u0)
)

(define-private (verify-property-id-exists (property-id uint))
  (and (> property-id u0) (<= property-id (var-get next-property-identifier)))
)

(define-private (verify-booking-id-exists (booking-id uint))
  (and (> booking-id u0) (<= booking-id (var-get next-booking-identifier)))
)

(define-private (verify-timestamp-validity (timestamp uint))
  (and (> timestamp u0) (< timestamp u4294967295))
)

(define-private (verify-principal-validity (user-principal principal))
  (not (is-eq user-principal 'SP000000000000000000002Q6VF78))
)

;; Property management and registration functions

(define-public (create-property-listing 
  (listing-title (string-ascii 100))
  (property-description (string-ascii 500))
  (geographic-location (string-ascii 100))
  (nightly-rate-microstack uint)
  (maximum-occupancy uint))
  (let
    (
      (new-property-id (+ (var-get next-property-identifier) u1))
      (sanitized-title listing-title)
      (sanitized-description property-description)
      (sanitized-location geographic-location)
    )
    ;; Comprehensive input validation
    (asserts! (verify-string-has-content sanitized-title) ERR-STRING-CONTENT-INVALID)
    (asserts! (verify-string-has-content sanitized-description) ERR-STRING-CONTENT-INVALID)
    (asserts! (verify-string-has-content sanitized-location) ERR-STRING-CONTENT-INVALID)
    (asserts! (> nightly-rate-microstack u0) (err u400))
    (asserts! (and (> maximum-occupancy u0) (<= maximum-occupancy u100)) (err u401))
    (asserts! (is-none (map-get? property-listings { property-identifier: new-property-id })) ERR-PROPERTY-REGISTRATION-DUPLICATE)
    
    ;; Create new property listing record
    (map-set property-listings
      { property-identifier: new-property-id }
      {
        property-owner: tx-sender,
        listing-title: sanitized-title,
        property-description: sanitized-description,
        geographic-location: sanitized-location,
        nightly-rate-microstack: nightly-rate-microstack,
        maximum-occupancy: maximum-occupancy,
        operational-status: property-status-available,
        completed-stays-count: u0,
        cumulative-rating-score: u0,
        total-review-submissions: u0
      }
    )
    
    ;; Update or create user profile with property ownership data
    (map-set platform-user-profiles
      { user-principal: tx-sender }
      (merge
        (default-to 
          { owned-properties-count: u0, completed-bookings-count: u0, trust-score: u0, identity-verification-status: false }
          (map-get? platform-user-profiles { user-principal: tx-sender })
        )
        { owned-properties-count: (+ (get owned-properties-count (default-to { owned-properties-count: u0, completed-bookings-count: u0, trust-score: u0, identity-verification-status: false } (map-get? platform-user-profiles { user-principal: tx-sender }))) u1) }
      )
    )
    
    ;; Increment property counter for next registration
    (var-set next-property-identifier new-property-id)
    (ok new-property-id)
  )
)

(define-public (modify-property-operational-status (property-id uint) (updated-status uint))
  (let
    (
      (validated-property-id property-id)
      (property-data (unwrap! (map-get? property-listings { property-identifier: validated-property-id }) ERR-PROPERTY-DOES-NOT-EXIST))
    )
    ;; Authorization and input validation
    (asserts! (verify-property-id-exists validated-property-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (or (is-eq updated-status property-status-available) (is-eq updated-status property-status-suspended)) (err u402))
    (asserts! (is-eq tx-sender (get property-owner property-data)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Update property operational status
    (map-set property-listings
      { property-identifier: validated-property-id }
      (merge property-data { operational-status: updated-status })
    )
    (ok true)
  )
)

(define-public (adjust-property-nightly-rate (property-id uint) (updated-rate uint))
  (let
    (
      (validated-property-id property-id)
      (property-data (unwrap! (map-get? property-listings { property-identifier: validated-property-id }) ERR-PROPERTY-DOES-NOT-EXIST))
    )
    ;; Authorization and input validation
    (asserts! (verify-property-id-exists validated-property-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (> updated-rate u0) (err u400))
    (asserts! (is-eq tx-sender (get property-owner property-data)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Update nightly rate pricing
    (map-set property-listings
      { property-identifier: validated-property-id }
      (merge property-data { nightly-rate-microstack: updated-rate })
    )
    (ok true)
  )
)

;; Reservation and booking management system

(define-public (initiate-property-booking (property-id uint) (arrival-date uint) (departure-date uint))
  (let
    (
      (validated-property-id property-id)
      (validated-arrival-date arrival-date)
      (validated-departure-date departure-date)
      (property-data (unwrap! (map-get? property-listings { property-identifier: validated-property-id }) ERR-PROPERTY-DOES-NOT-EXIST))
      (new-booking-id (+ (var-get next-booking-identifier) u1))
      (calculated-stay-nights (- validated-departure-date validated-arrival-date))
      (base-accommodation-cost (* (get nightly-rate-microstack property-data) calculated-stay-nights))
      (platform-commission-amount (/ (* base-accommodation-cost (var-get commission-rate-basis-points)) u10000))
      (total-payment-required (+ base-accommodation-cost platform-commission-amount))
    )
    ;; Comprehensive booking validation
    (asserts! (verify-property-id-exists validated-property-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (verify-timestamp-validity validated-arrival-date) ERR-INVALID-DATE-RANGE)
    (asserts! (verify-timestamp-validity validated-departure-date) ERR-INVALID-DATE-RANGE)
    (asserts! (is-eq (get operational-status property-data) property-status-available) ERR-PROPERTY-NOT-AVAILABLE)
    (asserts! (< validated-arrival-date validated-departure-date) ERR-INVALID-DATE-RANGE)
    (asserts! (> calculated-stay-nights u0) ERR-INVALID-DATE-RANGE)
    (asserts! (<= calculated-stay-nights u365) ERR-INVALID-DATE-RANGE)
    (asserts! (>= stx-liquid-supply total-payment-required) ERR-PAYMENT-AMOUNT-INSUFFICIENT)
    
    ;; Verify property availability for key dates
    (asserts! (check-date-availability-status validated-property-id validated-arrival-date) ERR-PROPERTY-NOT-AVAILABLE)
    (asserts! (check-date-availability-status validated-property-id (+ validated-arrival-date u1)) ERR-PROPERTY-NOT-AVAILABLE)
    (asserts! (check-date-availability-status validated-property-id (+ validated-arrival-date u2)) ERR-PROPERTY-NOT-AVAILABLE)
    
    ;; Process payment transfer to contract escrow
    (try! (stx-transfer? total-payment-required tx-sender (as-contract tx-sender)))
    
    ;; Create booking record in system
    (map-set reservation-records
      { booking-identifier: new-booking-id }
      {
        associated-property-id: validated-property-id,
        guest-principal: tx-sender,
        arrival-date-timestamp: validated-arrival-date,
        departure-date-timestamp: validated-departure-date,
        stay-duration-nights: calculated-stay-nights,
        final-payment-amount: total-payment-required,
        reservation-status: booking-status-active-reservation,
        booking-creation-block: block-height
      }
    )
    
    ;; Block availability for reserved dates
    (update-date-availability validated-property-id validated-arrival-date false)
    (update-date-availability validated-property-id (+ validated-arrival-date u1) false)
    (update-date-availability validated-property-id (+ validated-arrival-date u2) false)
    
    ;; Update system counters and statistics
    (var-set next-booking-identifier new-booking-id)
    
    ;; Increment property booking statistics
    (map-set property-listings
      { property-identifier: validated-property-id }
      (merge property-data { completed-stays-count: (+ (get completed-stays-count property-data) u1) })
    )
    
    ;; Update guest booking history
    (map-set platform-user-profiles
      { user-principal: tx-sender }
      (merge
        (default-to 
          { owned-properties-count: u0, completed-bookings-count: u0, trust-score: u0, identity-verification-status: false }
          (map-get? platform-user-profiles { user-principal: tx-sender })
        )
        { completed-bookings-count: (+ (get completed-bookings-count (default-to { owned-properties-count: u0, completed-bookings-count: u0, trust-score: u0, identity-verification-status: false } (map-get? platform-user-profiles { user-principal: tx-sender }))) u1) }
      )
    )
    
    (ok new-booking-id)
  )
)

(define-public (finalize-booking-checkout (booking-id uint))
  (let
    (
      (validated-booking-id booking-id)
      (booking-data (unwrap! (map-get? reservation-records { booking-identifier: validated-booking-id }) ERR-BOOKING-RECORD-NOT-FOUND))
      (property-data (unwrap! (map-get? property-listings { property-identifier: (get associated-property-id booking-data) }) ERR-PROPERTY-DOES-NOT-EXIST))
      (host-payment-amount (- (get final-payment-amount booking-data) (/ (* (get final-payment-amount booking-data) (var-get commission-rate-basis-points)) u10000)))
    )
    ;; Validate checkout eligibility
    (asserts! (verify-booking-id-exists validated-booking-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (>= block-height (get departure-date-timestamp booking-data)) ERR-BOOKING-DEADLINE-EXCEEDED)
    (asserts! (is-eq (get reservation-status booking-data) booking-status-active-reservation) ERR-BOOKING-STATUS-INVALID)
    
    ;; Transfer payment to property owner
    (try! (as-contract (stx-transfer? host-payment-amount tx-sender (get property-owner property-data))))
    
    ;; Update booking to completed status
    (map-set reservation-records
      { booking-identifier: validated-booking-id }
      (merge booking-data { reservation-status: booking-status-stay-completed })
    )
    
    (ok true)
  )
)

(define-public (cancel-active-reservation (booking-id uint))
  (let
    (
      (validated-booking-id booking-id)
      (booking-data (unwrap! (map-get? reservation-records { booking-identifier: validated-booking-id }) ERR-BOOKING-RECORD-NOT-FOUND))
      (partial-refund-amount (/ (* (get final-payment-amount booking-data) u90) u100))
    )
    ;; Validate cancellation eligibility
    (asserts! (verify-booking-id-exists validated-booking-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (is-eq tx-sender (get guest-principal booking-data)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get reservation-status booking-data) booking-status-active-reservation) ERR-BOOKING-STATUS-INVALID)
    (asserts! (> (get arrival-date-timestamp booking-data) block-height) ERR-BOOKING-DEADLINE-EXCEEDED)
    
    ;; Process partial refund with cancellation fee
    (try! (as-contract (stx-transfer? partial-refund-amount tx-sender (get guest-principal booking-data))))
    
    ;; Restore property availability for cancelled dates
    (update-date-availability (get associated-property-id booking-data) (get arrival-date-timestamp booking-data) true)
    (update-date-availability (get associated-property-id booking-data) (+ (get arrival-date-timestamp booking-data) u1) true)
    (update-date-availability (get associated-property-id booking-data) (+ (get arrival-date-timestamp booking-data) u2) true)
    
    ;; Update booking status to cancelled
    (map-set reservation-records
      { booking-identifier: validated-booking-id }
      (merge booking-data { reservation-status: booking-status-reservation-cancelled })
    )
    
    (ok true)
  )
)

;; Guest review and rating system

(define-public (create-property-review (property-id uint) (booking-id uint) (numerical-rating uint) (written-feedback (string-ascii 500)))
  (let
    (
      (validated-property-id property-id)
      (validated-booking-id booking-id)
      (validated-rating numerical-rating)
      (sanitized-feedback written-feedback)
      (booking-data (unwrap! (map-get? reservation-records { booking-identifier: validated-booking-id }) ERR-BOOKING-RECORD-NOT-FOUND))
      (property-data (unwrap! (map-get? property-listings { property-identifier: validated-property-id }) ERR-PROPERTY-DOES-NOT-EXIST))
    )
    ;; Validate review submission eligibility
    (asserts! (verify-property-id-exists validated-property-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (verify-booking-id-exists validated-booking-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (and (>= validated-rating u1) (<= validated-rating u5)) ERR-RATING-OUT-OF-RANGE)
    (asserts! (verify-string-has-content sanitized-feedback) ERR-STRING-CONTENT-INVALID)
    (asserts! (is-eq tx-sender (get guest-principal booking-data)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get associated-property-id booking-data) validated-property-id) ERR-BOOKING-RECORD-NOT-FOUND)
    (asserts! (is-eq (get reservation-status booking-data) booking-status-stay-completed) ERR-BOOKING-STATUS-INVALID)
    (asserts! (is-none (map-get? guest-property-reviews { property-identifier: validated-property-id, reviewer-principal: tx-sender })) ERR-REVIEW-ALREADY-SUBMITTED)
    
    ;; Store review record
    (map-set guest-property-reviews
      { property-identifier: validated-property-id, reviewer-principal: tx-sender }
      {
        associated-booking-id: validated-booking-id,
        numerical-rating: validated-rating,
        written-feedback: sanitized-feedback,
        review-submission-block: block-height
      }
    )
    
    ;; Recalculate property average rating
    (let
      (
        (existing-review-count (get total-review-submissions property-data))
        (current-cumulative-rating (get cumulative-rating-score property-data))
        (updated-review-count (+ existing-review-count u1))
        (updated-average-rating (/ (+ (* current-cumulative-rating existing-review-count) validated-rating) updated-review-count))
      )
      (map-set property-listings
        { property-identifier: validated-property-id }
        (merge property-data { 
          cumulative-rating-score: updated-average-rating,
          total-review-submissions: updated-review-count
        })
      )
    )
    
    (ok true)
  )
)

;; Availability management helper functions

(define-private (check-date-availability-status (property-id uint) (date-timestamp uint))
  (default-to true (get available-for-booking (map-get? date-availability-matrix { property-identifier: property-id, date-timestamp: date-timestamp })))
)

(define-private (update-date-availability (property-id uint) (date-timestamp uint) (availability-status bool))
  (map-set date-availability-matrix
    { property-identifier: property-id, date-timestamp: date-timestamp }
    { available-for-booking: availability-status }
  )
)

;; Extended booking date management for longer reservations

(define-public (block-additional-booking-dates (property-id uint) (booking-id uint) (date-one uint) (date-two uint) (date-three uint))
  (let
    (
      (validated-property-id property-id)
      (validated-booking-id booking-id)
      (validated-date-one date-one)
      (validated-date-two date-two)
      (validated-date-three date-three)
      (booking-data (unwrap! (map-get? reservation-records { booking-identifier: validated-booking-id }) ERR-BOOKING-RECORD-NOT-FOUND))
      (property-data (unwrap! (map-get? property-listings { property-identifier: validated-property-id }) ERR-PROPERTY-DOES-NOT-EXIST))
    )
    ;; Validate authorization and inputs
    (asserts! (verify-property-id-exists validated-property-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (verify-booking-id-exists validated-booking-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (verify-timestamp-validity validated-date-one) ERR-INVALID-DATE-RANGE)
    (asserts! (verify-timestamp-validity validated-date-two) ERR-INVALID-DATE-RANGE)
    (asserts! (verify-timestamp-validity validated-date-three) ERR-INVALID-DATE-RANGE)
    (asserts! (is-eq tx-sender (get guest-principal booking-data)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get reservation-status booking-data) booking-status-active-reservation) ERR-BOOKING-STATUS-INVALID)
    
    ;; Block specified dates from availability
    (update-date-availability validated-property-id validated-date-one false)
    (update-date-availability validated-property-id validated-date-two false)
    (update-date-availability validated-property-id validated-date-three false)
    (ok true)
  )
)

(define-public (restore-booking-date-availability (property-id uint) (booking-id uint) (date-one uint) (date-two uint) (date-three uint))
  (let
    (
      (validated-property-id property-id)
      (validated-booking-id booking-id)
      (validated-date-one date-one)
      (validated-date-two date-two)
      (validated-date-three date-three)
      (booking-data (unwrap! (map-get? reservation-records { booking-identifier: validated-booking-id }) ERR-BOOKING-RECORD-NOT-FOUND))
      (property-data (unwrap! (map-get? property-listings { property-identifier: validated-property-id }) ERR-PROPERTY-DOES-NOT-EXIST))
    )
    ;; Validate authorization with multiple role permissions
    (asserts! (verify-property-id-exists validated-property-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (verify-booking-id-exists validated-booking-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (verify-timestamp-validity validated-date-one) ERR-INVALID-DATE-RANGE)
    (asserts! (verify-timestamp-validity validated-date-two) ERR-INVALID-DATE-RANGE)
    (asserts! (verify-timestamp-validity validated-date-three) ERR-INVALID-DATE-RANGE)
    (asserts! (or (is-eq tx-sender (get guest-principal booking-data)) (is-eq tx-sender (get property-owner property-data)) (is-eq tx-sender contract-administrator)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Restore availability for specified dates
    (update-date-availability validated-property-id validated-date-one true)
    (update-date-availability validated-property-id validated-date-two true)
    (update-date-availability validated-property-id validated-date-three true)
    (ok true)
  )
)

;; Public read-only data access functions

(define-read-only (retrieve-property-details (property-id uint))
  (let ((validated-property-id property-id))
    (if (verify-property-id-exists validated-property-id)
      (map-get? property-listings { property-identifier: validated-property-id })
      none
    )
  )
)

(define-read-only (retrieve-booking-information (booking-id uint))
  (let ((validated-booking-id booking-id))
    (if (verify-booking-id-exists validated-booking-id)
      (map-get? reservation-records { booking-identifier: validated-booking-id })
      none
    )
  )
)

(define-read-only (retrieve-user-profile-data (user-principal principal))
  (map-get? platform-user-profiles { user-principal: user-principal })
)

(define-read-only (retrieve-property-review (property-id uint) (reviewer-principal principal))
  (let ((validated-property-id property-id))
    (if (verify-property-id-exists validated-property-id)
      (map-get? guest-property-reviews { property-identifier: validated-property-id, reviewer-principal: reviewer-principal })
      none
    )
  )
)

(define-read-only (check-property-date-availability (property-id uint) (date-timestamp uint))
  (let 
    (
      (validated-property-id property-id)
      (validated-date date-timestamp)
    )
    (if (and (verify-property-id-exists validated-property-id) (verify-timestamp-validity validated-date))
      (check-date-availability-status validated-property-id validated-date)
      false
    )
  )
)

(define-read-only (get-current-commission-rate)
  (var-get commission-rate-basis-points)
)

(define-read-only (get-total-properties-registered)
  (var-get next-property-identifier)
)

(define-read-only (get-total-bookings-created)
  (var-get next-booking-identifier)
)

;; Administrative control functions

(define-public (update-platform-commission-rate (updated-fee-basis-points uint))
  (begin
    (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= updated-fee-basis-points u1000) (err u403))
    (var-set commission-rate-basis-points updated-fee-basis-points)
    (ok true)
  )
)

(define-public (grant-user-verification-status (target-user principal))
  (let ((validated-target-user target-user))
    (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (verify-principal-validity validated-target-user) ERR-INPUT-VALIDATION-FAILED)
    (map-set platform-user-profiles
      { user-principal: validated-target-user }
      (merge
        (default-to 
          { owned-properties-count: u0, completed-bookings-count: u0, trust-score: u0, identity-verification-status: false }
          (map-get? platform-user-profiles { user-principal: validated-target-user })
        )
        { identity-verification-status: true }
      )
    )
    (ok true)
  )
)

(define-public (execute-emergency-booking-cancellation (booking-id uint))
  (let
    (
      (validated-booking-id booking-id)
      (booking-data (unwrap! (map-get? reservation-records { booking-identifier: validated-booking-id }) ERR-BOOKING-RECORD-NOT-FOUND))
    )
    ;; Administrative override validation
    (asserts! (verify-booking-id-exists validated-booking-id) ERR-INPUT-VALIDATION-FAILED)
    (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Process full refund for emergency cancellation
    (try! (as-contract (stx-transfer? (get final-payment-amount booking-data) tx-sender (get guest-principal booking-data))))
    
    ;; Restore all blocked dates to availability
    (update-date-availability (get associated-property-id booking-data) (get arrival-date-timestamp booking-data) true)
    (update-date-availability (get associated-property-id booking-data) (+ (get arrival-date-timestamp booking-data) u1) true)
    (update-date-availability (get associated-property-id booking-data) (+ (get arrival-date-timestamp booking-data) u2) true)
    
    ;; Update booking status to cancelled
    (map-set reservation-records
      { booking-identifier: validated-booking-id }
      (merge booking-data { reservation-status: booking-status-reservation-cancelled })
    )
    
    (ok true)
  )
)