;; Case Outcome Tracking Contract
;; Records and analyzes legal case outcomes

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-CASE-NOT-FOUND (err u501))
(define-constant ERR-INVALID-INPUT (err u502))
(define-constant ERR-ATTORNEY-NOT-FOUND (err u503))
(define-constant ERR-CASE-CLOSED (err u504))

;; Data Variables
(define-data-var next-case-id uint u1)
(define-data-var total-cases uint u0)
(define-data-var total-settlements uint u0)
(define-data-var total-judgments uint u0)

;; Data Maps
(define-map legal-cases uint {
  case-number: (string-ascii 50),
  attorney: principal,
  client: principal,
  case-type: (string-ascii 50), ;; "civil", "criminal", "corporate", "family", etc.
  practice-area: (string-ascii 50),
  court-level: (string-ascii 30), ;; "district", "appellate", "supreme", "arbitration"
  filed-date: uint,
  closed-date: (optional uint),
  status: (string-ascii 20), ;; "active", "settled", "won", "lost", "dismissed", "appealed"
  outcome: (optional (string-ascii 50)),
  settlement-amount: (optional uint),
  judgment-amount: (optional uint),
  attorney-fees: uint,
  case-duration: (optional uint), ;; in blocks
  complexity-score: uint ;; 1-10 scale
})

(define-map case-outcomes uint {
  case-id: uint,
  outcome-type: (string-ascii 30), ;; "settlement", "judgment", "dismissal", "plea"
  winner: (optional (string-ascii 20)), ;; "plaintiff", "defendant", "mutual"
  outcome-details: (string-ascii 500),
  financial-result: uint,
  precedent-value: uint, ;; 1-10 scale for precedent importance
  appeal-filed: bool,
  satisfaction-rating: (optional uint), ;; Client satisfaction 1-100
  recorded-at: uint,
  verified: bool
})

(define-map attorney-statistics principal {
  total-cases: uint,
  cases-won: uint,
  cases-lost: uint,
  cases-settled: uint,
  total-settlements: uint,
  total-judgments: uint,
  average-case-duration: uint,
  success-rate: uint, ;; Percentage
  specialization-areas: (list 10 (string-ascii 50)),
  years-active: uint,
  last-updated: uint
})

(define-map practice-area-stats (string-ascii 50) {
  total-cases: uint,
  average-duration: uint,
  average-settlement: uint,
  success-rate: uint,
  complexity-average: uint,
  last-updated: uint
})

(define-map court-statistics (string-ascii 30) {
  total-cases: uint,
  plaintiff-wins: uint,
  defendant-wins: uint,
  settlements: uint,
  average-duration: uint,
  last-updated: uint
})

(define-map case-precedents uint {
  case-id: uint,
  legal-principle: (string-ascii 200),
  citation: (string-ascii 100),
  precedent-weight: uint, ;; 1-10 scale
  related-cases: (list 10 uint),
  keywords: (list 20 (string-ascii 30)),
  created-at: uint
})

(define-map attorney-cases principal (list 100 uint))
(define-map client-cases principal (list 50 uint))
(define-map monthly-stats uint {month: uint, cases-filed: uint, cases-closed: uint})

;; Private Functions
(define-private (is-authorized (user principal))
  (or (is-eq user CONTRACT-OWNER) (is-eq user tx-sender))
)

(define-private (is-case-participant (case-id uint) (user principal))
  (match (map-get? legal-cases case-id)
    case-info (or (is-eq (get attorney case-info) user)
                  (or (is-eq (get client case-info) user)
                      (is-authorized user)))
    false
  )
)

(define-private (calculate-success-rate (won uint) (total uint))
  (if (is-eq total u0)
    u0
    (/ (* won u100) total)
  )
)

(define-private (is-valid-case-type (case-type (string-ascii 50)))
  (or (is-eq case-type "civil")
      (or (is-eq case-type "criminal")
          (or (is-eq case-type "corporate")
              (or (is-eq case-type "family")
                  (or (is-eq case-type "immigration")
                      (is-eq case-type "intellectual-property"))))))
)

(define-private (is-valid-court-level (court-level (string-ascii 30)))
  (or (is-eq court-level "district")
      (or (is-eq court-level "appellate")
          (or (is-eq court-level "supreme")
              (is-eq court-level "arbitration"))))
)

;; Public Functions

;; File a new case
(define-public (file-case (case-number (string-ascii 50))
                         (client principal)
                         (case-type (string-ascii 50))
                         (practice-area (string-ascii 50))
                         (court-level (string-ascii 30))
                         (complexity-score uint))
  (let ((case-id (var-get next-case-id)))
    (asserts! (> (len case-number) u0) ERR-INVALID-INPUT)
    (asserts! (is-valid-case-type case-type) ERR-INVALID-INPUT)
    (asserts! (is-valid-court-level court-level) ERR-INVALID-INPUT)
    (asserts! (and (>= complexity-score u1) (<= complexity-score u10)) ERR-INVALID-INPUT)

    (map-set legal-cases case-id {
      case-number: case-number,
      attorney: tx-sender,
      client: client,
      case-type: case-type,
      practice-area: practice-area,
      court-level: court-level,
      filed-date: block-height,
      closed-date: none,
      status: "active",
      outcome: none,
      settlement-amount: none,
      judgment-amount: none,
      attorney-fees: u0,
      case-duration: none,
      complexity-score: complexity-score
    })

    ;; Add to attorney's case list
    (let ((attorney-case-list (default-to (list) (map-get? attorney-cases tx-sender))))
      (map-set attorney-cases tx-sender
        (unwrap! (as-max-len? (append attorney-case-list case-id) u100) ERR-INVALID-INPUT))
    )

    ;; Add to client's case list
    (let ((client-case-list (default-to (list) (map-get? client-cases client))))
      (map-set client-cases client
        (unwrap! (as-max-len? (append client-case-list case-id) u50) ERR-INVALID-INPUT))
    )

    ;; Update total cases
    (var-set total-cases (+ (var-get total-cases) u1))
    (var-set next-case-id (+ case-id u1))

    (ok case-id)
  )
)

;; Record case outcome
(define-public (record-outcome (case-id uint)
                              (outcome-type (string-ascii 30))
                              (winner (optional (string-ascii 20)))
                              (outcome-details (string-ascii 500))
                              (financial-result uint)
                              (attorney-fees uint))
  (let ((case-info (unwrap! (map-get? legal-cases case-id) ERR-CASE-NOT-FOUND))
        (case-duration (- block-height (get filed-date case-info))))

    (asserts! (is-case-participant case-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status case-info) "active") ERR-CASE-CLOSED)
    (asserts! (> (len outcome-details) u0) ERR-INVALID-INPUT)

    ;; Update case with outcome
    (let ((new-status (if (is-eq outcome-type "settlement") "settled"
                        (if (is-some winner)
                          (if (is-eq (unwrap-panic winner) "plaintiff") "won" "lost")
                          "dismissed"))))

      (map-set legal-cases case-id (merge case-info {
        closed-date: (some block-height),
        status: new-status,
        outcome: (some outcome-type),
        settlement-amount: (if (is-eq outcome-type "settlement") (some financial-result) none),
        judgment-amount: (if (not (is-eq outcome-type "settlement")) (some financial-result) none),
        attorney-fees: attorney-fees,
        case-duration: (some case-duration)
      }))
    )

    ;; Record detailed outcome
    (map-set case-outcomes case-id {
      case-id: case-id,
      outcome-type: outcome-type,
      winner: winner,
      outcome-details: outcome-details,
      financial-result: financial-result,
      precedent-value: u1, ;; Default, can be updated later
      appeal-filed: false,
      satisfaction-rating: none,
      recorded-at: block-height,
      verified: false
    })

    ;; Update attorney statistics
    (let ((attorney (get attorney case-info))
          (current-stats (default-to {
            total-cases: u0,
            cases-won: u0,
            cases-lost: u0,
            cases-settled: u0,
            total-settlements: u0,
            total-judgments: u0,
            average-case-duration: u0,
            success-rate: u0,
            specialization-areas: (list),
            years-active: u1,
            last-updated: block-height
          } (map-get? attorney-statistics attorney))))

      (let ((new-total (+ (get total-cases current-stats) u1))
            (new-won (if (and (is-some winner) (is-eq (unwrap-panic winner) "plaintiff"))
                       (+ (get cases-won current-stats) u1)
                       (get cases-won current-stats)))
            (new-lost (if (and (is-some winner) (is-eq (unwrap-panic winner) "defendant"))
                        (+ (get cases-lost current-stats) u1)
                        (get cases-lost current-stats)))
            (new-settled (if (is-eq outcome-type "settlement")
                           (+ (get cases-settled current-stats) u1)
                           (get cases-settled current-stats))))

        (map-set attorney-statistics attorney (merge current-stats {
          total-cases: new-total,
          cases-won: new-won,
          cases-lost: new-lost,
          cases-settled: new-settled,
          total-settlements: (if (is-eq outcome-type "settlement")
                              (+ (get total-settlements current-stats) financial-result)
                              (get total-settlements current-stats)),
          total-judgments: (if (not (is-eq outcome-type "settlement"))
                            (+ (get total-judgments current-stats) financial-result)
                            (get total-judgments current-stats)),
          success-rate: (calculate-success-rate new-won new-total),
          last-updated: block-height
        }))
      )
    )

    ;; Update global statistics
    (if (is-eq outcome-type "settlement")
      (var-set total-settlements (+ (var-get total-settlements) u1))
      (var-set total-judgments (+ (var-get total-judgments) u1))
    )

    (ok true)
  )
)

;; Record case precedent
(define-public (record-precedent (case-id uint)
                                (legal-principle (string-ascii 200))
                                (citation (string-ascii 100))
                                (precedent-weight uint)
                                (keywords (list 20 (string-ascii 30))))
  (let ((case-info (unwrap! (map-get? legal-cases case-id) ERR-CASE-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len legal-principle) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= precedent-weight u1) (<= precedent-weight u10)) ERR-INVALID-INPUT)

    (map-set case-precedents case-id {
      case-id: case-id,
      legal-principle: legal-principle,
      citation: citation,
      precedent-weight: precedent-weight,
      related-cases: (list),
      keywords: keywords,
      created-at: block-height
    })

    ;; Update outcome with precedent value
    (match (map-get? case-outcomes case-id)
      outcome (map-set case-outcomes case-id (merge outcome {
        precedent-value: precedent-weight
      }))
      false
    )

    (ok true)
  )
)

;; Update client satisfaction
(define-public (update-satisfaction (case-id uint) (rating uint))
  (let ((case-info (unwrap! (map-get? legal-cases case-id) ERR-CASE-NOT-FOUND))
        (outcome (unwrap! (map-get? case-outcomes case-id) ERR-CASE-NOT-FOUND)))

    (asserts! (is-eq (get client case-info) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= rating u100) ERR-INVALID-INPUT)

    (map-set case-outcomes case-id (merge outcome {
      satisfaction-rating: (some rating)
    }))

    (ok true)
  )
)

;; Mark appeal filed
(define-public (file-appeal (case-id uint))
  (let ((case-info (unwrap! (map-get? legal-cases case-id) ERR-CASE-NOT-FOUND))
        (outcome (unwrap! (map-get? case-outcomes case-id) ERR-CASE-NOT-FOUND)))

    (asserts! (is-case-participant case-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq (get status case-info) "active")) ERR-INVALID-INPUT)

    (map-set case-outcomes case-id (merge outcome {
      appeal-filed: true
    }))

    (map-set legal-cases case-id (merge case-info {
      status: "appealed"
    }))

    (ok true)
  )
)

;; Verify case outcome (admin function)
(define-public (verify-outcome (case-id uint))
  (let ((outcome (unwrap! (map-get? case-outcomes case-id) ERR-CASE-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    (map-set case-outcomes case-id (merge outcome {
      verified: true
    }))

    (ok true)
  )
)

;; Update practice area statistics
(define-public (update-practice-stats (practice-area (string-ascii 50)))
  (let ((current-stats (default-to {
          total-cases: u0,
          average-duration: u0,
          average-settlement: u0,
          success-rate: u0,
          complexity-average: u0,
          last-updated: u0
        } (map-get? practice-area-stats practice-area))))

    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    ;; This would calculate actual statistics from all cases in practice area
    ;; Simplified for demonstration
    (map-set practice-area-stats practice-area (merge current-stats {
      last-updated: block-height
    }))

    (ok true)
  )
)

;; Read-only Functions

;; Get case details
(define-read-only (get-case (case-id uint))
  (map-get? legal-cases case-id)
)

;; Get case outcome
(define-read-only (get-case-outcome (case-id uint))
  (map-get? case-outcomes case-id)
)

;; Get attorney statistics
(define-read-only (get-attorney-stats (attorney principal))
  (map-get? attorney-statistics attorney)
)

;; Get practice area statistics
(define-read-only (get-practice-area-stats (practice-area (string-ascii 50)))
  (map-get? practice-area-stats practice-area)
)

;; Get court statistics
(define-read-only (get-court-stats (court-level (string-ascii 30)))
  (map-get? court-statistics court-level)
)

;; Get case precedent
(define-read-only (get-case-precedent (case-id uint))
  (map-get? case-precedents case-id)
)

;; Get attorney cases
(define-read-only (get-attorney-cases (attorney principal))
  (map-get? attorney-cases attorney)
)

;; Get client cases
(define-read-only (get-client-cases (client principal))
  (map-get? client-cases client)
)

;; Get total statistics
(define-read-only (get-total-stats)
  {
    total-cases: (var-get total-cases),
    total-settlements: (var-get total-settlements),
    total-judgments: (var-get total-judgments)
  }
)

;; Calculate attorney success rate
(define-read-only (calculate-attorney-success-rate (attorney principal))
  (match (map-get? attorney-statistics attorney)
    stats (get success-rate stats)
    u0
  )
)

;; Get cases by status
(define-read-only (get-cases-by-status (status (string-ascii 20)))
  ;; This would return a list of case IDs with the given status
  ;; Simplified implementation
  (some (list))
)

;; Get average case duration by practice area
(define-read-only (get-avg-duration-by-practice (practice-area (string-ascii 50)))
  (match (map-get? practice-area-stats practice-area)
    stats (some (get average-duration stats))
    none
  )
)
