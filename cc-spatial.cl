;;; -*- Mode: Common Lisp; -*-
;;;
;;; Diagrams for spatial orbitals. Lines in h-ops and amp cannot swap freely.
;;; 

(load "utility.cl")

(defun attach-tag (tag x)
  (cons tag x))
(proclaim '(inline attach-tag))
(defmacro tag-of (x)
  `(car ,x))
(defmacro content-of (x)
  `(cdr ,x))

;;; type:
;;; he+   ->-|
;;; pe+   -<-|
;;; pe-   |-<-
;;; he-   |->-
;;; hi+   contracted ->-|
;;; pi+   contracted -<-|
;;; pi-   contracted |-<-
;;; hi-   contracted |->-
;;;
;;; (t_{ijk}^{abc} i a j b k c)

;;; rline is an indexed operator == (op index)
(defun make-line (symb idx)
  (list symb idx))
(defun symb-of (line)
  (car line))
(defun idx-of (line)
  (cadr line))

;;; a node contains an "in" and an "out" lines
(defun make-node (l-out l-in)
  ;;; todo check if l-in is "in" line and l-out is "out" line
  (list l-out l-in))
(defun out-line-of (node) (car node))
(defun in-line-of (node) (cadr node))

(defparameter *h2e-ops*
  '((g ((he- 1) (he+ 2)) ((pe+ 3) (he+ 4)))
    (g ((pe+ 1) (pe- 2)) ((pe+ 3) (he+ 4)))
    (g ((he- 1) (he+ 2)) ((he- 3) (he+ 4)))
    (g ((pe+ 1) (pe- 2)) ((pe+ 3) (pe- 4)))
    (g ((he- 1) (he+ 2)) ((pe+ 3) (pe- 4)))
    (g ((he- 1) (pe- 2)) ((pe+ 3) (he+ 4)))
    (g ((he- 1) (pe- 2)) ((he- 3) (he+ 4)))
    (g ((he- 1) (pe- 2)) ((pe+ 3) (pe- 4)))
    (g ((he- 1) (pe- 2)) ((he- 3) (pe- 4)))))
(defparameter *h1e-h2e*
  (append '((f ((he- 1) (he+ 2)))
            (f ((pe+ 1) (pe- 2)))
            (f ((he- 1) (pe- 2)))
            (f ((pe+ 1) (he+ 2))))
          *h2e-ops*))

(defun op-copy (n op)
  (loop repeat n
       collect op))

; amp == (t (op1 . op2) (op3 . op4) ...)
; n-excitation amplitude without linking
; first make n pairs, then label indices
(defun make-new-amp (n)
  (attach-tag 't (op-copy n (make-node 'pe+ 'he+))))
; t1 = (t (he+ . pe+))
; t2 = (t (he+ . pe+) (he+ . pe+))
;
;todo assign indices
;

;;; contraction of one hole and an amplitude
;;; can use replace-oncep instead
(defun contract-hole-amp (idx amp)
  (let* ((last-node '())
         (c1 (mapreplace (lambda (node)
                           (when (and (not (equal last-node node))
                                      (eql (in-line-of node) 'he+))
                             (setf last-node node)
                             (make-node (out-line-of node)
                                        (make-line 'hi+ idx))))
                         (content-of amp))))
    (if c1
        (mapcar (lambda (a) (attach-tag 't a)) c1))))
(defun contract-particle-amp (idx amp)
  (let* ((last-node '())
         (c1 (mapreplace (lambda (node)
                           (when (and (not (equal last-node node))
                                      (eql (out-line-of node) 'pe+))
                             (setf last-node node)
                             (make-node (make-line 'pi+ idx)
                                        (in-line-of node))))
                         (content-of amp))))
    (if c1
        (mapcar (lambda (a) (attach-tag 't a)) c1))))

(defun contract-hole-ampprod (idx ampprod)
  (let ((last-amp '()))
    (mapreplace* (lambda (amp)
                   (unless (equal last-amp amp)
                     (setf last-amp amp)
                     (contract-hole-amp idx amp)))
                ampprod)))
(defun contract-particle-ampprod (idx ampprod)
  (let ((last-amp '()))
    (mapreplace* (lambda (amp)
                   (unless (equal last-amp amp)
                     (setf last-amp amp)
                     (contract-particle-amp idx amp)))
                 ampprod)))

(defun contract-op-ampprods (op ampprod-lst)
  (flet ((line-func (line ampprod-lst)
           (let ((symb (symb-of line))
                 (idx (idx-of line)))
             (case symb
               (he- (let ((res (mapcan (lambda (a)
                                         (contract-hole-ampprod idx a))
                                       ampprod-lst)))
                      (if res res ampprod-lst))) ; return orig-list if not-contracted
               (pe- (let ((res (mapcan (lambda (a)
                                         (contract-particle-ampprod idx a))
                                       ampprod-lst)))
                      (if res res ampprod-lst)))
               (otherwise ampprod-lst)))))
    (reduce (lambda (ampprod-lst node)
              (line-func (in-line-of node)
                         (line-func (out-line-of node) ampprod-lst)))
            op :initial-value ampprod-lst)))

(defun connected-amp? (amp)
  (flet ((conn? (line)
           (or (eql line 'hi+)
               (eql line 'pi+))))
    (find-anywhere-if #'conn? (content-of amp))))
(defun connected-ampprod? (ampprod)
  (every #'connected-amp? ampprod))

(defun id-of-node (node)
  (flet ((type-of-line (l)
           ;; valide node id can be
           ;; (hi- pi-) == 0 ; (hi- hi+) == 1 ; (hi- he+) == 2 ; (hi- pe-) __ 3 ;
           ;; (pi+ pi-) == 4 ; (pi+ hi+) == 5 ; (pi+ he+) == 6 ; (pi+ pe-) __ 7 ;
           ;; (pe+ pi-) == 8 ; (pe+ hi+) == 9 ; (pe+ he+) == 10; (pe+ pe-) __ 11;
           ;; (he- pi-) __ 12; (he- hi+) __ 13; (he- he+) __ 14; (he- pe-) __ 15;
           (if (atom l)
               (case l
                 ((pe+ he+) 2)
                 ((pe- he-) 3))
               (case (symb-of l)
                 ((pi- hi-) 0)
                 ((pi+ hi+) 1)
                 ((pe+ he+) 2)
                 ((pe- he-) 3))))
         (id-of-line (l)
           (cond ((atom l) 0)
                 ((member (symb-of l) '(hi+ pi+ hi- pi-))
                  (idx-of l))
                 (t 0))))
    (let ((lo (out-line-of node))
          (li (in-line-of node)))
      (+ (* 100 (+ (* 4 (type-of-line lo)) (type-of-line li)))
         (+ (* 4 (id-of-line lo)) (id-of-line li))))))
(defun id-of-amp (amp)
  (sort (mapcar #'id-of-node (content-of amp))
        #'<))
(defun list<= (lst1 lst2)
  (cond ((null lst1) t)
        ((null lst2) nil)
        ((eq (car lst1) (car lst2))
         (list<= (cdr lst1) (cdr lst2)))
        (t (< (car lst1) (car lst2)))))
(defun id-of-ampprod (ampprod)
  (sort (mapcar #'id-of-amp ampprod)
        (lambda (id1 id2)
          (let ((len1 (length id1))
                (len2 (length id2)))
            (if (eql len1 len2)
                (list<= id1 id2)
                (< len1 len2))))))

(defun remove-symm-eq-ampprod (ampprod-lst)
  (flet ((swap-e12 (ampprod)
           (maptree (lambda (n)
                      (case n (1 3) (2 4) (3 1) (4 2) (otherwise n)))
                    ampprod)))
    (remove-duplicates ampprod-lst
                       :test (lambda (a1 a2)
                               (equal (id-of-ampprod a1)
                                      (id-of-ampprod (swap-e12 a2))))
                       :from-end t)))

(defun symmetric-op? (op)
  (let ((nodes (content-of op)))
    (if (eql (length nodes) 1)
        nil ; one-electron operator
        (let ((symbs1 (mapcar #'symb-of (car nodes)))
              (symbs2 (mapcar #'symb-of (cadr nodes))))
          (equal symbs1 symbs2)))))
(defun contract-h2e-ampprod (h2e ampprod)
  (flet ((contract (ampprod-lst)
           (contract-op-ampprods (content-of h2e) ampprod-lst))
         (filter-conn (ampprod-lst)
           (remove-if-not #'connected-ampprod? ampprod-lst))
         (uniq (ampprod-lst)
           (if (symmetric-op? h2e)
               (remove-symm-eq-ampprod ampprod-lst)
               ampprod-lst))
         (append-h (ampprod-lst)
           (let ((ctr-h2e (maptree (lambda (line)
                                     (case line
                                       (he- 'hi-)
                                       (pe- 'pi-)
                                       (otherwise line)))
                                   h2e)))
             (mapcar (lambda (ampprod) (cons ctr-h2e ampprod)) ampprod-lst))))
    (funcall (compose #'append-h #'uniq #'filter-conn #'contract)
             (list ampprod))))

(defun gen-amps-list (n-lst)
  (if (null n-lst)
      '()
      (let* ((tnew (make-new-amp (car n-lst)))
             (t1 (list tnew))
             (t2 (cons tnew t1))
             (t3 (cons tnew t2))
             (t4 (cons tnew t3))
             (amps-lst (gen-amps-list (cdr n-lst)))
             (new-lst (mapcan (lambda (tx)
                                (mapcar (lambda (amps) (append tx amps))
                                        amps-lst))
                              (list t1 t2 t3)))
             (mod-lst (remove-if (lambda (ts) (> (length ts) 4))
                                 new-lst)))
        (append (list t1 t2 t3 t4) mod-lst))))

(defun count-tot-lines (pred ampprod)
  (apply #'+ (mapcar (lambda (amp)
                       (count-if pred (content-of amp)))
                     ampprod)))
(defun count-excite-lines (ampprod)
  (count-if (lambda (x) (member x '(he+ pe+)))
            (flatten ampprod)))
(defun count-dexcite-lines (ampprod)
  (count-if (lambda (x) (member x '(he- pe-)))
            (flatten ampprod)))

(defun gen-diagrams-w/o-index (n-lst)
  (flet ((d-ext-lines (op ampprod)
           (- (count-excite-lines (cons op ampprod))
              (count-dexcite-lines (list op)))))
    (let ((avail-exts (mapcar (lambda (x) (+ x x)) n-lst)))
      (mapcan (lambda (ampprod)
                (mapcan (lambda (op)
                          (if (member (d-ext-lines op ampprod) avail-exts)
                              (contract-h2e-ampprod op ampprod)))
                        *h1e-h2e*))
              (gen-amps-list n-lst)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; adding indices
;;; e.g. assign 2 to internal hole line (hi+ . 2)
;;;

;; return nil if not replaced
;(defun label-amp (test idx amp)
;  (let ((ops (replace-oncep (lambda (op) (if (funcall test op)
;                                             (make-line op idx)))
;                            (content-of amp))))
;    (if ops
;        (attach-tag (tag-of amp) ops))))
;(defun label-amp-contract-hole (idx amp)
;  (label-amp (lambda (op) (or (eql op 'hi-) (eql op 'hi+))) idx amp))
;(defun label-amp-contract-particle (idx amp)
;  (label-amp (lambda (op) (or (eql op 'pi-) (eql op 'pi+))) idx amp))
;
;;;; if not contracted, return the input ampprod
;(defun label-contract-pair (label-func idx h-ampprod)
;  (cons (funcall label-func idx (car h-ampprod))
;        (replace-once (lambda (amp) (funcall label-func idx amp))
;                      (cdr h-ampprod))))
;
;;;; return a product, sum over the indices which appear twice
;(defun label-lines (ampprod)
;  (let ((reg 0))
;    (flet ((label-ctr (ts op)
;             (case op
;               (hi- (label-contract-pair #'label-amp-contract-hole
;                                         (incf reg) ts))
;               (pi- (label-contract-pair #'label-amp-contract-particle
;                                         (incf reg) ts))
;               (otherwise ts)))
;           (label-ex (symb)
;             (lambda (amp)
;               (let ((pairs (mapcar (lambda (op)
;                                      (if (eql op symb)
;                                          (make-line op (incf reg))
;                                          op))
;                                    (content-of amp))))
;                 (attach-tag (tag-of amp) pairs)))))
;      (mapcar (label-ex 'pe+)
;              (mapcar (label-ex 'he+)
;                      (reduce #'label-ctr (content-of (car ampprod))
;                              :initial-value ampprod))))))
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;
;;;; interperate the diagrams
;;;;
;
;;;; equivalent internal lines give a factor of 1/2
;;;; return the factor 1, 1/2 or 1/4
;(defun factor-int-line-pair (h-ampprod)
;  (flet ((count-eq-line (symb)
;           (apply #'* (mapcar (lambda (amp)
;                                (if (eql 2 (count symb (content-of amp) :key #'car))
;                                    .5 1))
;                              (cdr h-ampprod)))))
;    (* (count-eq-line 'hi+)
;       (count-eq-line 'pi+))))
;
;;;; equivalent external lines must connect to the same vertex
;(defun find-rline-vertex (rline h-ampprod)
;  (find-if (lambda (amp) (member rline amp :test #'equal))
;           h-ampprod))
;;todo: change to ext-pair-eql?
;(defun ext-line-eql? (ex1 ex2 h-ampprod)
;  ;;; same symbol and same vertex
;  (and (eql (symb-of ex1) (symb-of ex2))
;       (equal (find-rline-vertex ex1 h-ampprod)
;              (find-rline-vertex ex2 h-ampprod))))
;
;(defun vertex-equiv? (amp1 amp2)
;  (flet ((get-symb (x)
;           (if (atom x) x (symb-of x))))
;    (equal (mapcar #'get-symb (content-of amp1))
;           (mapcar #'get-symb (content-of amp2)))))
;(defun ext-line-symm-eql? (ex1 ex2 h-ampprod)
;  ;;; same symbol on equivalent vertex
;  (vertex-equiv? (find-rline-vertex ex1 h-ampprod)
;                 (find-rline-vertex ex2 h-ampprod)))
;
;(defun factor-of-symm-vertices (h-ampprod)
;  (let ((ampprod (cdr h-ampprod)))
;    (case (length ampprod)
;      (2 (if (vertex-equiv? (first ampprod) (second ampprod)) .5 1))
;      (3 ;todo
;       (and (equal (first ampprod) (second ampprod))
;              (equal symm1?)))
;      (4 ;todo
;       (and (equal (first ampprod) (second ampprod))
;            (equal (third ampprod) (fourth ampprod))))
;      (otherwise 1))))
;
;;;; return the connected rlines
;(defun track-rline (rline h-ampprod)
;  (let ((finds (list rline)))
;    (labels ((find-friend (rline) ; find the rline on the same node
;               (let* ((v (content-of (find-rline-vertex rline h-ampprod)))
;                      (pos (position rline v :test #'equal)))
;                 (if (evenp pos)
;                     (nth (1+ pos) v)
;                     (nth (1- pos) v))))
;             (conn-int-line (rline)
;               (let ((s (symb-of rline))
;                     (i (idx-of rline)))
;                 (case s
;                   (hi- (make-line 'hi+ i))
;                   (hi+ (make-line 'hi- i))
;                   (pi- (make-line 'pi+ i))
;                   (pi+ (make-line 'pi- i))
;                   (otherwise nil))))
;             (searching (rline)
;               (let ((next-rline (find-friend rline)))
;                 (setf finds (cons next-rline finds))
;                 (if (member (symb-of next-rline)
;                             '(hi- hi+ pi- pi+))
;                     (let ((nnext (conn-int-line next-rline)))
;                       (setf finds (cons nnext finds))
;                       (searching nnext))
;                     finds))))
;      (searching rline))))
;
;(defun count-loops (ampprod)
;  (count-tot-lines (lambda (rline)
;                     (eql (symb-of rline) 'he+))
;                   ampprod))
;(defun count-hole-lines (ampprod)
;  (count-tot-lines (lambda (rline)
;                     (member (symb-of rline) '(he- he+ hi- hi+)))
;                   ampprod))
;(defun hole-loop-sign (ampprod)
;  (if (evenp (+ (count-hole-lines ampprod)
;                (count-loops ampprod)))
;      1
;      -1))
;
;(defun collect-ext-holes (ampprod)
;  (remove-if-not #'identity
;                 (mapcar (lambda (amp)
;                           (find-if (lambda (rline)
;                                      (eql (symb-of rline) 'he+))
;                                    (content-of amp)))
;                         ampprod)))

;;; elem-lst has at least one item
(defun permutation-sets (elem-lst &key (test #'equal))
  (if (last-one? elem-lst)
      (list elem-lst)
      (mapcan (lambda (e)
                (mapcar (lambda (s) (cons e s))
                        (permutation-sets
                         (remove e elem-lst :count 1 :test #'equal))))
              (remove-duplicates elem-lst :test test :from-end t))))
;;; even permutation and odd permutation
(defun permutation-even-odd-sets (elem-lst &key (test #'equal))
  (labels ((per-it (elems)
             (if (last-one? elems)
                 (list (list elems) '())
                 (reduce (lambda (eo-sets e)
                           (let* ((eset (first eo-sets))
                                  (oset (second eo-sets))
                                  (p (per-it (remove e elems :count 1 :test #'equal)))
                                  (s1 (mapcar (lambda (s) (cons e s)) (first p)))
                                  (s2 (mapcar (lambda (s) (cons e s)) (second p))))
                             (if (evenp (position e elems))
                                 (list (append s1 eset) (append s2 oset))
                                 (list (append s2 eset) (append s1 oset)))))
                         (remove-duplicates elems :test test :from-end t)
                         :initial-value '(() ())))))
    (mapcar #'reverse (per-it elem-lst))))

;;; symmetric vertices will cancel against the permutation of inequivalent ext-lines
(defun permutation-ext-line (h-ampprod)
  (let* ((h-ext (collect-ext-holes h-ampprod))
         (p-ext (mapcar #'car (track-rline h-ext h-ampprod))))
    (flet ((ext-eql (x1 x2)
             (or (ext-line-eql? x1 x2 h-ampprod)
                 (ext-line-symm-eql? x1 x2 h-ampprod))))
      (list (permutation-even-odd-sets h-ext :test #'ext-eql)
            (permutation-even-odd-sets p-ext :test #'ext-eql)))))

;;; confine to the same spin
;(defun permutate-pairs)