;;; qute-launcher.el --- launcher for qutebrowser     -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Lars Rustand.

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

;; Author: Lars Rustand
;; URL: http://githhub.com/lrustand/qute-launcher
;; Version: 

;;; Commentary:

;;; Change Log:

;;; Code:

;; TODO Separate out search history from regular history
;; i.e. remove Google, Ebay, Amazon, Youtube searches etc
(require 'sqlite)
(require 'marginalia)
(require 'consult)
(require 'exwm)
(require 'json)

(defvar qutebrowser--target 'auto)
(defvar qutebrowser-history-database
  "~/.local/share/qutebrowser/history.sqlite")

(defun qutebrowser-history ()
  (let ((db (sqlite-open qutebrowser-history-database)))
    (sqlite-select db "SELECT url,substr(title,0,99) FROM History GROUP BY url ORDER BY
COUNT(url) DESC")))

(defun qutebrowser--pseudo-annotate (row)
  (let* ((url (nth 0 row))
         (title (nth 1 row))
         (display-url (truncate-string-to-width url 50 0 ?\ )))
    (cons
     (format "%s %s"
             display-url
             (propertize title
                         'face 'marginalia-value))
     url)))

(defun qutebrowser-history-candidates ()
  "Returns a list of completion candidates from qutebrowser
history. Candidates contain the url, and a pseudo-annotation with the
website title, to allow searching based on either one."
  (let* ((history (qutebrowser-history)))
    (mapcar #'qutebrowser--pseudo-annotate
            history)))

(defun qutebrowser-open-url (url)
  (let* ((pipe (getenv "QUTE_FIFO"))
         (target (or qutebrowser--target 'auto))
         (flag (pcase target
                 ('window "-w")
                 ('tab "-t")
                 ('private-window "-p")
                 ('auto ""))))
    (if pipe
        (write-region (format "open %s %s" flag url) nil pipe t)
      (start-process "qutebrowser" nil "qutebrowser" "--target" (symbol-name target) url))))

(defun qute-launcher--internal (&optional url prefilled)
  (if (and url (not prefilled))
      (qutebrowser-open-url url)
    (let* ((res (consult--multi '(qutebrowser-buffer-source
                                  qutebrowser-history-buffer-source)
                                :initial url
                                :sort nil))
           (plist (cdr res))
           (selected (car res)))
      ;; If none of the buffer sources handled it
      (unless (plist-get plist :match)
        (qutebrowser-open-url selected)))))

(defun qute-launcher (&optional url _ prefilled)
  (interactive)
  (qute-launcher--internal url prefilled))

(defun qute-launcher-tab (&optional url _ prefilled)
  (interactive)
  (let ((qutebrowser--target 'tab))
    (qute-launcher--internal url prefilled)))

(defun qute-launcher-window (&optional url _ prefilled)
  (interactive)
  (let ((qutebrowser--target 'window))
    (qute-launcher--internal url prefilled)))

(defun qute-launcher-private (&optional url _ prefilled)
  (interactive)
  (let ((qutebrowser--target 'private-window))
    (qute-launcher--internal url prefilled)))


(defvar qutebrowser-buffer-source
  `(;; consult-buffer source for open Qutebrowser windows
    :name "Qutebrowser buffers"
    :hidden nil
    :narrow ?q
    :category buffer
    ;; Specify either :action or :state
    :action ,#'consult--buffer-action ;; No preview
    ;; :state ,#'consult--buffer-state  ;; Preview
    ;; HACK to workaround that it doesn't work in the other source
    :items
    ,(lambda () (consult--buffer-query
                 :sort 'visibility
                 :as #'buffer-name
                 :predicate (lambda (buf)
                              (with-current-buffer buf
                                (string-equal "qutebrowser"
                                              exwm-class-name)))
                 :mode 'exwm-mode))))


(defvar qutebrowser-history-buffer-source
  `(;; consult-buffer source for Qutebrowser history
    :name "Qutebrowser history"
    :hidden nil
    :narrow ?h
    :history nil
    :category buffer
    :action ,#'qutebrowser-open-url
    :items
    ,#'qutebrowser-history-candidates))

;;(add-to-list 'consult-buffer-sources 'qutebrowser-buffer-source 'append)


(defvar qutebrowser-ipc-protocol-version 1
  "The protocol version for qutebrowser IPC.")

(defun qutebrowser-ipc-socket-path ()
  "Return the path to qutebrowser's IPC socket."
  (expand-file-name
   (format "qutebrowser/ipc-%s" (md5 (user-login-name)))
   (or (getenv "XDG_RUNTIME_DIR")
       (format "/run/user/%d" (user-real-uid)))))

(defun qutebrowser-ipc-send (&rest commands)
  "Send COMMANDS to qutebrowser via IPC."
  (let* ((socket-path (qutebrowser-ipc-socket-path))
         (data (json-encode `(("args" . ,commands)
                              ("target_arg" . nil)
                              ("protocol_version" . ,qutebrowser-ipc-protocol-version))))
         process)
    (condition-case err
        (progn
          (setq process (make-network-process :name "qutebrowser-ipc"
                                              :family 'local
                                              :service socket-path
                                              :coding 'utf-8))
          (process-send-string process (concat data "\n"))
          (let ((response (or (process-buffer process)
                              (with-temp-buffer
                                (set-process-buffer process (current-buffer))
                                (accept-process-output process 1)
                                (buffer-string))))))
          (delete-process process))
      (file-error
       (message "Error connecting to qutebrowser IPC socket: %s" (error-message-string err)))
      (error
       (message "Unexpected error in qutebrowser-ipc-send: %s" (error-message-string err))))))

(defun qutebrowser-ipc-open-url (url)
  "Open URL in qutebrowser."
  (interactive "sEnter URL: ")
  (qutebrowser-ipc-send (format ":open %s" url))))


(provide 'qute-launcher)

;;; qute-launcher.el ends here
