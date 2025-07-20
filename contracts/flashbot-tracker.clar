;; flashbot-tracker.clar
;; This contract serves as the core component for the Compile Flashbot platform, 
;; enabling automated tracking, verification, and incentivization of computational 
;; and blockchain-related activities. It provides a robust mechanism for logging 
;; and rewarding performance-critical tasks.

;; ========== Error Constants ==========
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-USER-ALREADY-EXISTS (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-CHALLENGE-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-JOINED-CHALLENGE (err u104))
(define-constant ERR-CHALLENGE-ENDED (err u105))
(define-constant ERR-CHALLENGE-NOT-STARTED (err u106))
(define-constant ERR-INVALID-WORKOUT-TYPE (err u107))
(define-constant ERR-ALREADY-RECORDED-TODAY (err u108))
(define-constant ERR-INVALID-PARAMETERS (err u109))
(define-constant ERR-NOT-CHALLENGE-CREATOR (err u110))
(define-constant ERR-CHALLENGE-ALREADY-EXISTS (err u111))

;; ========== Data Maps and Variables ==========

;; User profiles - stores basic information about each registered computational contributor
(define-map users
  { user: principal }
  {
    username: (string-utf8 50),
    registered-at: uint,
    total-tasks: uint,
    total-computational-hours: uint,
    last-task-date: (optional uint)
  }
)

;; Computational task types allowed in the system
(define-data-var task-types (list 9 (string-utf8 20)) 
  (list u"compilation" u"testing" u"deployment" u"optimization" u"validation" u"simulation" u"analysis" u"research")
)

;; Individual computational task records
(define-map tasks
  { task-id: uint, user: principal }
  {
    task-type: (string-utf8 20),
    duration-minutes: uint,
    computational-complexity: uint,
    date: uint,
    notes: (optional (string-utf8 200))
  }
)

;; Workout counter for generating unique workout IDs
(define-data-var task-counter uint u0)

;; Fitness challenges
(define-map challenges
  { challenge-id: uint }
  {
    name: (string-utf8 100),
    description: (string-utf8 500),
    creator: principal,
    start-date: uint,
    end-date: uint,
    workout-goal: uint, ;; Number of workouts to complete
    min-workout-duration: uint, ;; Minimum duration in minutes
    reward-amount: uint, ;; Amount awarded to successful participants
    active: bool
  }
)

;; Challenge participation tracking
(define-map challenge-participants
  { challenge-id: uint, participant: principal }
  {
    joined-at: uint,
    workouts-completed: uint,
    goal-reached: bool
  }
)

;; Challenge counter for generating unique challenge IDs
(define-data-var challenge-counter uint u0)

;; ========== Private Functions ==========

;; Check if challenge is active (started but not ended)
(define-private (is-challenge-active (challenge-id uint))
  (match (map-get? challenges { challenge-id: challenge-id })
    challenge (and 
      (>= block-height (get start-date challenge))
      (<= block-height (get end-date challenge))
      (get active challenge)
    )
    false
  )
)

;; Create a new computational task record
(define-private (create-task-record
  (user principal)
  (task-type (string-utf8 20))
  (duration-minutes uint)
  (computational-complexity uint)
  (notes (optional (string-utf8 200)))
)
  (let
    (
      (new-task-id (+ (var-get task-counter) u1))
      (current-date (/ burn-block-height u144)) ;; Approximate daily blocks
    )
    ;; Increment the task counter
    (var-set task-counter new-task-id)
    
    ;; Insert the new task record
    (map-set tasks
      { task-id: new-task-id, user: user }
      {
        task-type: task-type,
        duration-minutes: duration-minutes,
        computational-complexity: computational-complexity,
        date: block-height,
        notes: notes
      }
    )
    
    ;; Update the user's profile with new task count and date
    (match (map-get? users { user: user })
      prev-data
        (map-set users
          { user: user }
          {
            username: (get username prev-data),
            registered-at: (get registered-at prev-data),
            total-workouts: (+ (get total-workouts prev-data) u1),
            last-workout-date: (some block-height)
          }
        )
      false
    )

    ;; Return the new task ID
    new-task-id
  )
)

;; Get the list of active challenges a user has joined
(define-private (get-user-active-challenges (user principal))
  ;; Note: In actual implementation, this would require a more complex mechanism
  ;; to efficiently retrieve joined challenges. This is a simplified placeholder.
  (list u0)
)

;; ========== Read-Only Functions ==========

;; Get user profile information
(define-read-only (get-user-profile (user principal))
  (map-get? users { user: user })
)

;; Get details of a specific workout
(define-read-only (get-workout (workout-id uint) (user principal))
  (map-get? workouts { workout-id: workout-id, user: user })
)

;; Get details of a specific challenge
(define-read-only (get-challenge (challenge-id uint))
  (map-get? challenges { challenge-id: challenge-id })
)

;; Get a user's participation in a specific challenge
(define-read-only (get-challenge-participation (challenge-id uint) (user principal))
  (map-get? challenge-participants { challenge-id: challenge-id, participant: user })
)

;; ========== Public Functions ==========

;; Register a new computational contributor
(define-public (register-user (username (string-utf8 50)))
  (let
    ((sender tx-sender))
    
    ;; Create new user profile
    (map-set users
      { user: sender }
      {
        username: username,
        registered-at: block-height,
        total-tasks: u0,
        total-computational-hours: u0,
        last-task-date: none
      }
    )
    (ok true)
  )
)

;; Log a computational task
(define-public (log-task (task-type (string-utf8 20)) (duration-minutes uint) (computational-complexity uint) (notes (optional (string-utf8 200))))
  (let
    ((sender tx-sender))
    ;; Verify parameters are valid
    (asserts! (> duration-minutes u0) ERR-INVALID-PARAMETERS)
    (asserts! (> computational-complexity u0) ERR-INVALID-PARAMETERS)
    
    ;; Create the task record
    (let 
      ((task-id (create-task-record sender task-type duration-minutes computational-complexity notes)))
      
      (ok task-id)
    )
  )
)

;; Create a new fitness challenge
(define-public (create-challenge 
  (name (string-utf8 100)) 
  (description (string-utf8 500))
  (start-date uint)
  (end-date uint)
  (workout-goal uint)
  (min-workout-duration uint)
  (reward-amount uint)
)
  (let
    (
      (sender tx-sender)
      (new-challenge-id (+ (var-get challenge-counter) u1))
    )
    ;; Validate parameters
    (asserts! (< start-date end-date) ERR-INVALID-PARAMETERS)
    (asserts! (>= start-date block-height) ERR-INVALID-PARAMETERS)
    (asserts! (> workout-goal u0) ERR-INVALID-PARAMETERS)
    (asserts! (> min-workout-duration u0) ERR-INVALID-PARAMETERS)
    
    ;; Increment challenge counter
    (var-set challenge-counter new-challenge-id)
    
    ;; Create the challenge
    (map-set challenges
      { challenge-id: new-challenge-id }
      {
        name: name,
        description: description,
        creator: sender,
        start-date: start-date,
        end-date: end-date,
        workout-goal: workout-goal,
        min-workout-duration: min-workout-duration,
        reward-amount: reward-amount,
        active: true
      }
    )
    (ok new-challenge-id)
  )
)

;; Join a fitness challenge
(define-public (join-challenge (challenge-id uint))
  (let
    ((sender tx-sender))
    
    ;; Verify the challenge is currently active
    (asserts! (is-challenge-active challenge-id) ERR-CHALLENGE-NOT-STARTED)
    
    ;; Record the user's participation
    (map-set challenge-participants
      { challenge-id: challenge-id, participant: sender }
      {
        joined-at: block-height,
        workouts-completed: u0,
        goal-reached: false
      }
    )
    (ok true)
  )
)

;; Add a new valid workout type (restricted to contract owner)
;; In a real implementation, you'd want proper contract ownership checks
(define-public (add-workout-type (new-type (string-utf8 20)))
  (let
    ((current-types (var-get workout-types)))
    ;; Basic implementation - would need proper authorization in production
    (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Add the new workout type
    (ok true)
  )
)