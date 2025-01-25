;;; qutebrowser-consult.el --- Consult completion for Qutebrowser -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Isaac Haller & Lars Rustand.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

;;; Commentary:

;; Consult-based completion for Qutebrowser buffers, history,
;; commands, and bookmarks. The sources provided in this file can be
;; added as additional sources to 'consult-buffer' or similar. See
;; 'consult-buffer-sources' and 'consult--multi'.

;; To use Consult for all Qutebrowser-related selection, set
;; `qutebrowser-selection-function' to `qutebrowser-consult-select-url'.

;;; Change Log:

;;; Code:
(require 'qutebrowser)
(require 'consult)

(defgroup qutebrowser-consult nil
  "Consult completion for Qutebrowser."
  :group 'qutebrowser
  :prefix "qutebrowser-consult")

(defcustom qutebrowser-consult-launcher-sources
  '(qutebrowser-consult--exwm-buffer-source
    qutebrowser-consult--bookmark-url-source
    qutebrowser-consult--history-source
    qutebrowser-consult--command-source)
  "Sources used by `qutebrowser-launcher' and family."
  :type '(repeat symbol)
  :group 'qutebrowser-consult)

;;;; Helper functions
(defun qutebrowser-consult--annotate (entry)
  "Return annotation for ENTRY."
  (qutebrowser--shorten-display-url entry)
  (propertize (get-text-property 0 'title entry)
	      'face 'completions-annotations))

(defun qutebrowser-consult--format-buffer (entry)
  "Format buffer ENTRY for completion."
  (let ((title (get-text-property 0 'title entry)))
    (concat (qutebrowser--shorten-display-url entry)
	    (propertize title 'invisible t))))

;;;; Buffer source
(defvar qutebrowser-consult--exwm-buffer-source
  (list :name "Qutebrowser buffers"
        :hidden nil
        :narrow ?q
        :history nil
        :category 'url
        :action (lambda (entry)
		  (switch-to-buffer (get-text-property 0 'qutebrowser-buffer entry)))
        :annotate #'qutebrowser-consult--annotate
        :items (lambda () (mapcar #'qutebrowser-consult--format-buffer (qutebrowser-exwm-buffer-search))))
  "Consult source for open Qutebrowser windows.")

;;;; Bookmark source
(defvar qutebrowser-consult--bookmark-source
  (list :name "Qutebrowser bookmarks"
        :hidden nil
        :narrow ?m
        :history nil
        :category 'bookmark
        :face 'consult-bookmark
        :action #'qutebrowser-bookmark-jump
	:annotate #'qutebrowser-consult--annotate
        :items #'qutebrowser-bookmarks-list)
  "Consult source for Qutebrowser bookmarks.")

(defvar qutebrowser-consult--bookmark-url-source
  (list :name "Qutebrowser bookmarks" ;; should this be named differently? it's unlikely that this source is used with the other one
        :hidden nil
        :narrow ?m
        :history nil
        :category 'url
        :action #'qutebrowser-open-url
	:annotate #'qutebrowser-consult--annotate
        :items #'qutebrowser-bookmark-search)
  "Consult source for Qutebrowser bookmarks.")

;;;; Command source
(defvar qutebrowser-consult--command-history nil)

(defvar qutebrowser-consult--command-source
  (list :name "Qutebrowser commands"
	:hidden nil
	:narrow ?:
	:history nil
	:category 'other
	:action #'qutebrowser-send-commands
	:new #'qutebrowser-send-commands
        :annotate #'qutebrowser-consult--annotate
	:items (apply-partially #'qutebrowser-command-search '(":")))
  "Consult source for Qutebrowser commands.")

;;;###autoload
(defun qutebrowser-consult-command (&optional initial)
  "Command entry for Qutebrowser based on Consult.
Set initial completion input to INITIAL."
  (interactive)
  (let* ((consult-async-min-input 0)
	 (consult-async-split-style nil))
    (consult--multi '(qutebrowser-consult--command-source)
                    :group nil
		    :prompt "Command: "
		    :initial (or initial ":")
		    :history 'qutebrowser-consult--command-history)))

;;;; History source
(defvar qutebrowser-consult--history-source
  (list :name "Qutebrowser history"
	:hidden nil
	:narrow ?h
	:history nil
	:category 'url
	:action #'qutebrowser-open-url
	:new #'qutebrowser-open-url
	:annotate #'qutebrowser-consult--annotate
	:async
	(consult--dynamic-collection
	    (lambda (input)
	      (qutebrowser--history-search (string-split (or input ""))
					   qutebrowser-dynamic-results))
	  :min-input 0
	  :throttle 0
	  :debounce 0
	  :highlight t
	  :transform (consult--async-map #'qutebrowser--shorten-display-url)))
  "Consult source for Qutebrowser history.")

;;;; `qutebrowser-launcher' replacement
(defun qutebrowser-consult--suppress-action (source)
  "Return SOURCE with no action."
  (let* ((source (if (symbolp source) (symbol-value source) source))
	 (new-source (seq-copy source)))
    (plist-put new-source :action nil)))

;;;###autoload
(defun qutebrowser-consult-select-url (&optional initial default)
  "Backend for `qutebrowser-select-url' based on Consult."
  (let* ((consult-async-min-input 0)
         (consult-async-split-style nil)
	 (sources qutebrowser-consult-launcher-sources)
	 (selection (consult--multi
		     (mapcar #'qutebrowser-consult--suppress-action sources)
		     :prompt (if default
				 (format "Select (default %s): " default)
			       "Select: ")
		     :default default
		     :sort nil
		     :initial initial
		     :require-match nil)))
    (car selection)))

(provide 'qutebrowser-consult)

;;; qutebrowser-consult.el ends here
