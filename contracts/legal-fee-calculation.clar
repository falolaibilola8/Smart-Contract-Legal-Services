;; Legal Fee Calculation Contract
;; Transparent calculation of legal service fees

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-INPUT (err u401))
(define-constant ERR-INVOICE-NOT-FOUND (err u402))
(define-constant ERR-ATTORNEY-NOT-FOUND (err u403))
(define-constant ERR-INSUFFICIENT-FUNDS (err u404))

;; Data Variables
(define-data-var next-invoice-id uint u1)
(define-data-var next-attorney-id uint u1)
(define-data-var platform-fee-rate uint u5) ;; 5% platform fee

;; Data Maps
(define-map attorneys principal {
  name: (string-ascii 100),
  bar-number: (string-ascii 50),
  specialization: (string-ascii 100),
  hourly-rate: uint,
  flat-fee-services: (list 10 {service: (string-ascii 50), fee: uint}),
  contingency-rate: uint, ;; Percentage for contingency cases
  experience-years: uint,
  rating: uint,
  active: bool,
  registered-at: uint
})

(define-map fee-structures uint {
  attorney: principal,
  service-type: (string-ascii 50),
  fee-type: (string-ascii 20), ;; "hourly", "flat", "contingency", "hybrid"
  base-rate: uint,
  minimum-fee: uint,
  maximum-fee: (optional uint),
  complexity-multiplier: uint, ;; Percentage (100 = no change)
  created-at: uint,
  active: bool
})

(define-map invoices uint {
  attorney: principal,
  client: principal,
  service-description: (string-ascii 200),
  fee-structure-id: uint,
  hours-worked: uint,
  expenses: uint,
  base-fee: uint,
  platform-fee: uint,
  total-amount: uint,
  status: (string-ascii 20), ;; "draft", "sent", "paid", "overdue", "disputed"
  created-at: uint,
  due-date: uint,
  paid-at: (optional uint)
})

(define-map time-entries uint {
  invoice-id: uint,
  attorney: principal,
  date: uint,
  hours: uint,
  description: (string-ascii 200),
  hourly-rate: uint,
  amount: uint
})

(define-map expense-entries uint {
  invoice-id: uint,
  attorney: principal,
  date: uint,
  description: (string-ascii 200),
  amount: uint,
  category: (string-ascii 50),
  receipt-hash: (optional (buff 32))
})

(define-map fee-estimates uint {
  attorney: principal,
  client: principal,
  service-type: (string-ascii 50),
  estimated-hours: uint,
  estimated-expenses: uint,
  estimated-total: uint,
  complexity-factor: uint,
  valid-until: uint,
  created-at: uint
})

(define-map attorney-earnings principal uint)
(define-map client-payments principal uint)

;; Private Functions
(define-private (is-authorized (user principal))
  (or (is-eq user CONTRACT-OWNER) (is-eq user tx-sender))
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u100)
)

(define-private (is-valid-fee-type (fee-type (string-ascii 20)))
  (or (is-eq fee-type "hourly")
      (or (is-eq fee-type "flat")
          (or (is-eq fee-type "contingency")
              (is-eq fee-type "hybrid"))))
)

;; Public Functions

;; Register attorney
(define-public (register-attorney (name (string-ascii 100))
                                 (bar-number (string-ascii 50))
                                 (specialization (string-ascii 100))
                                 (hourly-rate uint)
                                 (contingency-rate uint)
                                 (experience-years uint))
  (begin
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len bar-number) u0) ERR-INVALID-INPUT)
    (asserts! (> hourly-rate u0) ERR-INVALID-INPUT)
    (asserts! (<= contingency-rate u50) ERR-INVALID-INPUT) ;; Max 50% contingency

    (map-set attorneys tx-sender {
      name: name,
      bar-number: bar-number,
      specialization: specialization,
      hourly-rate: hourly-rate,
      flat-fee-services: (list),
      contingency-rate: contingency-rate,
      experience-years: experience-years,
      rating: u50, ;; Start with neutral rating
      active: true,
      registered-at: block-height
    })

    (ok true)
  )
)

;; Create fee structure
(define-public (create-fee-structure (service-type (string-ascii 50))
                                    (fee-type (string-ascii 20))
                                    (base-rate uint)
                                    (minimum-fee uint)
                                    (maximum-fee (optional uint))
                                    (complexity-multiplier uint))
  (let ((structure-id (var-get next-attorney-id)))
    (asserts! (is-some (map-get? attorneys tx-sender)) ERR-ATTORNEY-NOT-FOUND)
    (asserts! (> (len service-type) u0) ERR-INVALID-INPUT)
    (asserts! (is-valid-fee-type fee-type) ERR-INVALID-INPUT)
    (asserts! (> base-rate u0) ERR-INVALID-INPUT)
    (asserts! (>= complexity-multiplier u50) ERR-INVALID-INPUT) ;; Min 50%
    (asserts! (<= complexity-multiplier u300) ERR-INVALID-INPUT) ;; Max 300%

    (map-set fee-structures structure-id {
      attorney: tx-sender,
      service-type: service-type,
      fee-type: fee-type,
      base-rate: base-rate,
      minimum-fee: minimum-fee,
      maximum-fee: maximum-fee,
      complexity-multiplier: complexity-multiplier,
      created-at: block-height,
      active: true
    })

    (var-set next-attorney-id (+ structure-id u1))
    (ok structure-id)
  )
)

;; Generate fee estimate
(define-public (generate-estimate (client principal)
                                 (service-type (string-ascii 50))
                                 (estimated-hours uint)
                                 (estimated-expenses uint)
                                 (complexity-factor uint))
  (let ((attorney-info (unwrap! (map-get? attorneys tx-sender) ERR-ATTORNEY-NOT-FOUND))
        (base-cost (* estimated-hours (get hourly-rate attorney-info)))
        (complexity-adjustment (/ (* base-cost complexity-factor) u100))
        (total-estimate (+ complexity-adjustment estimated-expenses))
        (estimate-id (var-get next-invoice-id)))

    (asserts! (> estimated-hours u0) ERR-INVALID-INPUT)
    (asserts! (>= complexity-factor u50) ERR-INVALID-INPUT)
    (asserts! (<= complexity-factor u300) ERR-INVALID-INPUT)

    (map-set fee-estimates estimate-id {
      attorney: tx-sender,
      client: client,
      service-type: service-type,
      estimated-hours: estimated-hours,
      estimated-expenses: estimated-expenses,
      estimated-total: total-estimate,
      complexity-factor: complexity-factor,
      valid-until: (+ block-height u1440), ;; Valid for ~10 days
      created-at: block-height
    })

    (var-set next-invoice-id (+ estimate-id u1))
    (ok estimate-id)
  )
)

;; Create invoice
(define-public (create-invoice (client principal)
                              (service-description (string-ascii 200))
                              (fee-structure-id uint)
                              (hours-worked uint)
                              (expenses uint))
  (let ((invoice-id (var-get next-invoice-id))
        (attorney-info (unwrap! (map-get? attorneys tx-sender) ERR-ATTORNEY-NOT-FOUND))
        (fee-structure (unwrap! (map-get? fee-structures fee-structure-id) ERR-INVALID-INPUT))
        (base-fee (if (is-eq (get fee-type fee-structure) "hourly")
                    (* hours-worked (get base-rate fee-structure))
                    (get base-rate fee-structure)))
        (total-before-platform (+ base-fee expenses))
        (platform-fee (calculate-platform-fee total-before-platform))
        (total-amount (+ total-before-platform platform-fee)))

    (asserts! (is-eq (get attorney fee-structure) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active fee-structure) ERR-INVALID-INPUT)
    (asserts! (> (len service-description) u0) ERR-INVALID-INPUT)
    (asserts! (>= total-before-platform (get minimum-fee fee-structure)) ERR-INVALID-INPUT)

    ;; Check maximum fee if set
    (match (get maximum-fee fee-structure)
      max-fee (asserts! (<= total-before-platform max-fee) ERR-INVALID-INPUT)
      true
    )

    (map-set invoices invoice-id {
      attorney: tx-sender,
      client: client,
      service-description: service-description,
      fee-structure-id: fee-structure-id,
      hours-worked: hours-worked,
      expenses: expenses,
      base-fee: base-fee,
      platform-fee: platform-fee,
      total-amount: total-amount,
      status: "draft",
      created-at: block-height,
      due-date: (+ block-height u2016), ;; ~14 days
      paid-at: none
    })

    (var-set next-invoice-id (+ invoice-id u1))
    (ok invoice-id)
  )
)

;; Send invoice to client
(define-public (send-invoice (invoice-id uint))
  (let ((invoice (unwrap! (map-get? invoices invoice-id) ERR-INVOICE-NOT-FOUND)))
    (asserts! (is-eq (get attorney invoice) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status invoice) "draft") ERR-INVALID-INPUT)

    (map-set invoices invoice-id (merge invoice {
      status: "sent"
    }))

    (ok true)
  )
)

;; Pay invoice
(define-public (pay-invoice (invoice-id uint))
  (let ((invoice (unwrap! (map-get? invoices invoice-id) ERR-INVOICE-NOT-FOUND)))
    (asserts! (is-eq (get client invoice) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status invoice) "sent") ERR-INVALID-INPUT)

    ;; In a real implementation, this would handle STX transfer
    ;; For now, we just update the status

    (map-set invoices invoice-id (merge invoice {
      status: "paid",
      paid-at: (some block-height)
    }))

    ;; Update attorney earnings
    (let ((current-earnings (default-to u0 (map-get? attorney-earnings (get attorney invoice)))))
      (map-set attorney-earnings (get attorney invoice)
        (+ current-earnings (- (get total-amount invoice) (get platform-fee invoice))))
    )

    ;; Update client payments
    (let ((current-payments (default-to u0 (map-get? client-payments tx-sender))))
      (map-set client-payments tx-sender (+ current-payments (get total-amount invoice)))
    )

    (ok true)
  )
)

;; Dispute invoice
(define-public (dispute-invoice (invoice-id uint) (reason (string-ascii 200)))
  (let ((invoice (unwrap! (map-get? invoices invoice-id) ERR-INVOICE-NOT-FOUND)))
    (asserts! (is-eq (get client invoice) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status invoice) "sent") ERR-INVALID-INPUT)
    (asserts! (> (len reason) u0) ERR-INVALID-INPUT)

    (map-set invoices invoice-id (merge invoice {
      status: "disputed"
    }))

    (ok true)
  )
)

;; Update attorney rating
(define-public (rate-attorney (attorney principal) (rating uint))
  (let ((attorney-info (unwrap! (map-get? attorneys attorney) ERR-ATTORNEY-NOT-FOUND)))
    (asserts! (<= rating u100) ERR-INVALID-INPUT)

    ;; Simplified rating update - in practice would average multiple ratings
    (map-set attorneys attorney (merge attorney-info {
      rating: rating
    }))

    (ok true)
  )
)

;; Read-only Functions

;; Get attorney info
(define-read-only (get-attorney (attorney principal))
  (map-get? attorneys attorney)
)

;; Get fee structure
(define-read-only (get-fee-structure (structure-id uint))
  (map-get? fee-structures structure-id)
)

;; Get invoice
(define-read-only (get-invoice (invoice-id uint))
  (map-get? invoices invoice-id)
)

;; Get fee estimate
(define-read-only (get-estimate (estimate-id uint))
  (map-get? fee-estimates estimate-id)
)

;; Get attorney earnings
(define-read-only (get-attorney-earnings (attorney principal))
  (default-to u0 (map-get? attorney-earnings attorney))
)

;; Get client payments
(define-read-only (get-client-payments (client principal))
  (default-to u0 (map-get? client-payments client))
)

;; Get platform fee rate
(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

;; Calculate estimated fee
(define-read-only (calculate-fee-estimate (attorney principal)
                                         (hours uint)
                                         (expenses uint)
                                         (complexity uint))
  (match (map-get? attorneys attorney)
    attorney-info
    (let ((base-cost (* hours (get hourly-rate attorney-info)))
          (complexity-adjustment (/ (* base-cost complexity) u100))
          (total (+ complexity-adjustment expenses)))
      (some total))
    none
  )
)
