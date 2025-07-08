(defgroup org-srs nil
  "Options concerning SRS"
  :group 'org)

(defcustom org-srs-files nil
  "List of files to look for cards"
  :type '(repeat file)
  :group 'org-srs)

(defconst org-srs-current-interval
  "CURRENT-INTERVAL"
  "Property name for current interval of card.")
(defconst org-srs-ease
  "EASE"
  "Property name for easiness of card.")
(defconst org-srs-next-review
  "NEXT-REVIEW"
  "Property name for next review of card.")

(defun org-srs-get-current-interval ()
  "Retrieve the current interval of the card at point. Defaults to
1.0."
  (let ((current-interval (org-entry-get nil org-srs-current-interval)))
    (if current-interval
        (string-to-number current-interval)
      1.0)))

(defun org-srs-get-ease ()
  "Retrieve the ease of the card at point. Defaults to 2.5."
  (let ((ease (org-entry-get nil org-srs-ease)))
    (if ease
        (string-to-number ease)
      2.5)))

(defun org-srs-get-next-review ()
  "Retrieve the next review of the card at point as a time
value. Defaults to nil."
  (let ((next-review (org-entry-get nil org-srs-next-review)))
    (when next-review
      (date-to-time next-review))))

(defun org-srs-get-card-next-review (card-m)
  "Retrieve the next review of the given card marker."
  (with-point-at-marker card-m (org-srs-get-next-review)))

;; TODO: maybe use property searching
(defun org-srs-get-ready-cards ()
  "Return a marker for each card that is ready to be
reviewed. These are cards for which the current date is at or
past the card's :next-review."
  (sort 
   (delq nil
         (org-map-entries '(unless (time-less-p nil (org-srs-get-next-review))
                             (point-marker))
                          nil
                          org-srs-files
                          'archive
                          'comment))
   (lambda (card-m1 card-m2)
     (time-less-p (org-srs-get-card-next-review card-m1)
                  (org-srs-get-card-next-review card-m2)))))

;; (org-srs-get-ready-cards)

(defmacro with-point-at-marker (marker &rest body)
  "Evaluate body with the current buffer set to the marker's buffer
and the current position set to the marker's position."
  `(with-current-buffer (marker-buffer ,marker)
     (save-excursion
       (goto-char (marker-position ,marker))
       ,@body)))

(put 'with-point-at-marker 'lisp-indent-function 1)

(defun org-srs-get-card-sides (card-m)
  "Return a pair, where the CAR is the card front, and CDR is the card back.
The card front is the headline, and the card back is the body of the org elements."
  (cons (org-entry-get card-m "ITEM")
        (or
         (with-point-at-marker card-m
           (let* ((headline (org-element-at-point))
                  (contents-begin (org-element-property :contents-begin headline))
                  (contents-end (org-element-property :contents-end headline)))
             (and contents-begin
                  contents-end
                  (with-restriction
                      contents-begin
                      contents-end
                    ;; TODO: handle nested sections? get only the paragraph
                    ;; whose parent('s parent) is the right headline?
                    (car
                     (org-element-map (org-element-parse-buffer) 'paragraph
                       (lambda (paragraph)
                         (buffer-substring-no-properties
                          (org-element-property :contents-begin paragraph)
                          (org-element-property :contents-end paragraph)))))))))
         "")))

;; (mapcar 'org-srs-get-card-sides (org-srs-get-ready-cards))

(defconst day-seconds (* 24.0 60 60) "The number of seconds in a day.")

(defun modify-ease (old-ease score)
  "Return the new ease given the old ease and score."
  (max 1.3
       (+ old-ease 
          (pcase score
            (1 -0.2)
            (2 -0.15)
            (3 0)
            (4 0.15)))))

(defun modify-interval (old-interval ease overdue-days score)
  "Return the new interval, given the old interval, ease,
overdue time, and score."
  (if (= score 1)
      (* old-interval 0.8)
    (max (+ old-interval 1)
         (pcase score
           (2 (* old-interval 1.2))
           (3 (* (+ old-interval (/ overdue-days 2))
                 ease))
           (4 (* (+ old-interval overdue-days)
                 ease
                 1.2))))))

;; (modify-interval 3 2.65 2 4)

(defun org-srs-update-card (card-m score)
  "Update the given card with the given user score:
1: EASE decreases by 0.2 and CURRENT-INTERVAL is multiplied by 0.8.
2: EASE decreases by 0.15 and CURRENT-INTERVAL is multiplied by 1.2.
3. Half the time overdue is added to CURRENT-INTERVAL and CURRENT-INTERVAL is multiplied by EASE.
4. EASE increases by 0.15, time overdue is added to CURRENT-INTERVAL and CURRENT-INTERVAL is mulitplied by EASE and 1.2.

For scores other than Again, the new interval is at least the old interval plus one. The next review is
now if the score is Again, otherwise it's scheduled for now plus CURRENT-INTERVAL.

Insert a property drawer if the card doesn't have one already.
EASE has default 2.5 and is at least 1.3."
  (with-point-at-marker card-m
    (org-insert-property-drawer)
    (let* ((new-ease (modify-ease (org-srs-get-ease) score))
           (overdue-days (/ (time-convert (time-subtract nil (org-srs-get-next-review)) 'integer) day-seconds))
           (new-interval (modify-interval (org-srs-get-current-interval) new-ease overdue-days score))
           (next-review (current-time-string
                         (if (= score 1)
                             nil
                           (time-add nil (* new-interval day-seconds))))))
      (org-entry-put nil org-srs-current-interval (number-to-string new-interval))
      (org-entry-put nil org-srs-ease (number-to-string new-ease))
      (org-entry-put nil org-srs-next-review next-review))
    (save-buffer)
    (undo-boundary)))

(defun org-srs-drill ()
  "Shows the org-srs cards in a new buffer:
1. Shows the front of the card
2. Waits for user input
3. Shows the back of the card
4. Waits for user input
5. Repeat with next card, or return nil if no more cards are available"
  (interactive)
  (with-current-buffer (get-buffer-create "org-srs-drill")
    (read-only-mode)
    (display-buffer (current-buffer))
    (let ((cards-to-review (org-srs-get-ready-cards)))
      (while cards-to-review
        (let* ((num-remaining (length cards-to-review))
               (card-m (pop cards-to-review))
               (sides (org-srs-get-card-sides card-m))
               (front (car sides))
               (back (cdr sides)))
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (format "残りカード：%d\n" num-remaining))
            (insert (format-time-string "復習時間：%Y-%m-%d %H:%M:%S\n" (org-srs-get-card-next-review card-m)))
            (insert front))
          (read-char-from-minibuffer "Enter any character to advance: ")
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert "\n")
            (insert back))
          (let* ((score-input (read-char-choice
                               "Score correctness between 1 (Again), 2 (Hard), 3 (Good), 4 (Easy): "
                               '(?1 ?2 ?3 ?4)))
                 (score (string-to-number (string score-input))))
            (org-srs-update-card card-m score)
            (when (= score 1)
              ;; FIXME: Use queue
              (if cards-to-review
                  (nconc cards-to-review (list card-m))
                (setq cards-to-review (list card-m))))))))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "Drill complete."))))

;; (org-srs-drill)

(provide 'org-srs)
