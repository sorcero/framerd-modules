(in-module 'jsonout)

(use-module '{fdweb})

(define json-lisp-prefix ":")

(defambda (jsonelt value (prefix #f) (initial #f))
  (printout (if (not initial) ",") (if prefix prefix)
    (unless (singleton? value) (printout "["))
    (if (singleton? value)
	(jsonout value #f)
	(do-choices (value value i)
	  (when (> i 0) (printout ","))
	  (jsonout value #f)))
    (unless (singleton? value) (printout "]"))))
(define (jsonvec vector)
  (printout "[" (doseq (elt vector i)
		  (jsonelt elt #f (= i 0)))
    "]"))

(defambda (jsonfield field value (valuefn #f) (prefix #f) (context #f)
		     (vecval #f))
  (unless (fail? value)
    (printout
      (if prefix prefix)
      (if (symbol? field)
	  (write (downcase (symbol->string field)))
	  (if (string? field) (write field)
	      (write (unparse-arg field))))
      ": "
      (if (or vecval (ambiguous? value)) (printout "["))
      (do-choices (value value i)
	(when (> i 0) (printout ","))
	(if valuefn
	    (jsonout (valuefn value context) #f)
	    (jsonout value #f)))
      (if (or vecval (ambiguous? value)) (printout "]")))))
(defambda (jsonfield+ field value (valuefn #f) (prefix #f) (context #f)
		      (vecval #f))
  (unless (fail? value)
    (printout
      (if prefix prefix)
      (if (symbol? field)
	  (write (downcase (symbol->string field)))
	  (if (string? field) (write field)
	      (write (unparse-arg field))))
      ": ["
      (do-choices (value value i)
	(when (> i 0) (printout ","))
	(if valuefn
	    (jsonout (valuefn value context) #f)
	    (jsonout value #f)))
      "]")))
(define (jsontable table (valuefn #f) (context #f))
  (printout "{"
	    (let ((initial #t))
	      (do-choices (key (getkeys table) i)
		(let ((v (get table key)))
		  (when (exists? v)
		    (unless initial (printout ", "))
		    (jsonfield key v valuefn "" context)
		    (set! initial #f)))))
	    
	    "}"))

(defambda (jsonout value (onfail "[]"))
  (cond ((ambiguous? value)
	 (printout "[" (do-choices (v value i)
			 (printout (if (> i 0) ",") (jsonout v)))
	   "]"))
	((fail? value) (if onfail (printout onfail)))
	((number? value) (printout value))
	((string? value) (jsonoutput value 0))
	((vector? value) (jsonvec value))
	((eq? value #t) (printout "true"))
	((eq? value #f) (printout "false"))
	((timestamp? value) (printout (get value 'tick)))
	((oid? value)
	 (printout "\":" (oid->string value) "\""))
	((table? value) (jsontable value))
	(else (let ((string (stringout (printout json-lisp-prefix)
			      (write value))))
		(jsonoutput string 0)))))

(module-export! '{jsonout jsonvec jsontable jsonfield jsonfield+ jsonelt})

;;; Support for JSON responses

(define (jsonp/open (var #f) (assign #f) (callback #f))
  (if var (printout "var " var "=")
      (if assign
	  (printout assign "=")
	  (if callback (printout callback "(")))))
(define (jsonp/close (var #f) (assign #f) (callback #f))
  (if (or var assign callback)
      (printout (if callback ")") ";")))

(module-export! '{jsonp/open jsonp/close})

;;; Converting a FramerD/Scheme object into an object that converts to
;;; JSON better
(defambda (exportjson object (toplevel #f))
  (if (ambiguous? object)
      (choice->vector (for-choices object (exportjson object)))
      (if (pair? object)
	  (if (proper-list? object)
	      (vector (->vector (map exportjson object)))
	      `#[CAR ,(exportjson (car object))
		 CDR ,(exportjson (car object))])
	  (if (string? object)
	      (if (has-prefix object {"#" "\\"}) (glom "\\" object)
		  object)
	      (if (timestamp? object)
		  (glom "#T" (get object 'iso))
		  (if (packet? object) 
		      (glom "#x\"" (packet->base16 object) "\"")
		      (if (uuid? object)
			  (glom "#U" (uuid->string object))
			  (if (oid? object)
			      (glom ":" (oid->string object))
			      (if (vector? object) (vector (map exportjson object))
				  (if (table? object)
				      (let ((obj (frame-create #f)))
					(do-choices (key (getkeys object))
					  (if (and toplevel (symbol? key))
					      (store! obj (downcase (symbol->string key))
						      (for-choices (v (get object key))
							(exportjson v)))
					      (store! obj key
						      (for-choices (v (get object key))
							(exportjson v)))))
					obj)
				      object))))))))))
(define (export->json arg) (exportjson arg #t))

(defambda (importjson object (toplevel #f))
  (if (vector? object)
      (for-choices (elt (elts object))
	(if (vector? elt) (map importjson elt)
	    (importjson elt)))
      (if (string? object)
	  (cond ((has-prefix object "\\") (slice object 1))
		((has-prefix object "#x") (base16->packet (slice object 2)))
		((has-prefix object "#T") (timestamp (slice object 2)))
		((has-prefix object "#U") (getuuid (slice object 2)))
		((has-prefix object "#@") (string->lisp (slice object 1)))
		(else object))
	  (if (oid? object) object
	      (if (table? object)
		  (let ((obj (frame-create #f)))
		    (do-choices (key (getkeys object))
		      (if (and toplevel (string? key) (lowercase? key))
			  (add! obj (string->lisp key)
				(importjson (get object key)))
			  (add! obj key (importjson (get object key)))))
		    obj)	      
		  object)))))
(define (import->json obj) (importjson obj #t))
(module-export! '{export->json import->json})

;;; JSON stringout

(define (json->string x)
  (stringout (jsonout (exportjson x #t))))
(define (jsonstringout x) (json->string x))
(define (json/stringout x) (json->string x))

(module-export! '{json->string jsonstringout json/stringout})


