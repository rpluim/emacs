;;; rlogin.el --- remote login interface

;; Author: Noah Friedman
;; Maintainer: Noah Friedman <friedman@prep.ai.mit.edu>
;; Keywords: unix, comm

;; Copyright (C) 1992, 1993, 1994, 1995 Free Software Foundation, Inc.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to: The Free Software Foundation,
;; Inc.; 675 Massachusetts Avenue.; Cambridge, MA 02139, USA.

;; $Id: rlogin.el,v 1.25 1995/03/12 18:18:29 rms Exp friedman $

;;; Commentary:

;; Support for remote logins using `rlogin'.
;; This program is layered on top of shell.el; the code here only accounts
;; for the variations needed to handle a remote process, e.g. directory
;; tracking and the sending of some special characters.

;; If you wish for rlogin mode to prompt you in the minibuffer for
;; passwords when a password prompt appears, just enter m-x send-invisible
;; and type in your line, or add `comint-watch-for-password-prompt' to
;; `comint-output-filter-functions'.

;;; Code:

(require 'comint)
(require 'shell)

(defvar rlogin-program "rlogin"
  "*Name of program to invoke rlogin")

(defvar rlogin-explicit-args nil
  "*List of arguments to pass to rlogin on the command line.")

(defvar rlogin-mode-hook nil
  "*Hooks to run after setting current buffer to rlogin-mode.")

(defvar rlogin-process-connection-type nil
  "*If non-`nil', use a pty for the local rlogin process.
If `nil', use a pipe (if pipes are supported on the local system).

Generally it is better not to waste ptys on systems which have a static
number of them.  On the other hand, some implementations of `rlogin' assume
a pty is being used, and errors will result from using a pipe instead.")

(defvar rlogin-directory-tracking-mode 'local
  "*Control whether and how to do directory tracking in an rlogin buffer.

nil means don't do directory tracking.

t means do so using an ftp remote file name.

Any other value means do directory tracking using local file names.
This works only if the remote machine and the local one
share the same directories (through NFS).  This is the default.

This variable becomes local to a buffer when set in any fashion for it.

It is better to use the function of the same name to change the behavior of
directory tracking in an rlogin session once it has begun, rather than
simply setting this variable, since the function does the necessary
re-synching of directories.")

(make-variable-buffer-local 'rlogin-directory-tracking-mode)

(defvar rlogin-host nil
  "*The name of the remote host.  This variable is buffer-local.")

(defvar rlogin-remote-user nil
  "*The username used on the remote host.
This variable is buffer-local and defaults to your local user name.
If rlogin is invoked with the `-l' option to specify the remote username,
this variable is set from that.")

;; Initialize rlogin mode map.
(defvar rlogin-mode-map '())
(cond
 ((null rlogin-mode-map)
  (setq rlogin-mode-map (if (consp shell-mode-map)
                            (cons 'keymap shell-mode-map)
                          (copy-keymap shell-mode-map)))
  (define-key rlogin-mode-map "\C-c\C-c" 'rlogin-send-Ctrl-C)
  (define-key rlogin-mode-map "\C-c\C-d" 'rlogin-send-Ctrl-D)
  (define-key rlogin-mode-map "\C-c\C-z" 'rlogin-send-Ctrl-Z)
  (define-key rlogin-mode-map "\C-c\C-\\" 'rlogin-send-Ctrl-backslash)
  (define-key rlogin-mode-map "\C-d" 'rlogin-delchar-or-send-Ctrl-D)
  (define-key rlogin-mode-map "\C-i" 'rlogin-tab-or-complete)))


;;;###autoload (add-hook 'same-window-regexps "^\\*rlogin-.*\\*\\(\\|<[0-9]+>\\)")

;;;###autoload
(defun rlogin (input-args &optional prefix)
  "Open a network login connection to HOST via the `rlogin' program.
Input is sent line-at-a-time to the remote connection.

Communication with the remote host is recorded in a buffer `*rlogin-HOST*'
\(or `*rlogin-USER@HOST*' if the remote username differs\).
If a prefix argument is given and the buffer `*rlogin-HOST*' already exists,
a new buffer with a different connection will be made.

The variable `rlogin-program' contains the name of the actual program to
run.  It can be a relative or absolute path.

The variable `rlogin-explicit-args' is a list of arguments to give to
the rlogin when starting.  They are added after any arguments given in
INPUT-ARGS.

If the default value of `rlogin-directory-tracking-mode' is t, then the
default directory in that buffer is set to a remote (FTP) file name to
access your home directory on the remote machine.  Occasionally this causes
an error, if you cannot access the home directory on that machine.  This
error is harmless as long as you don't try to use that default directory.

If `rlogin-directory-tracking-mode' is neither t nor nil, then the default
directory is initially set up to your (local) home directory.
This is useful if the remote machine and your local machine
share the same files via NFS.  This is the default.

If you wish to change directory tracking styles during a session, use the
function `rlogin-directory-tracking-mode' rather than simply setting the
variable."
  (interactive (list
		(read-from-minibuffer "rlogin arguments (hostname first): ")
		current-prefix-arg))

  (let* ((process-connection-type rlogin-process-connection-type)
         (args (if rlogin-explicit-args
                   (append (rlogin-parse-words input-args)
                           rlogin-explicit-args)
                 (rlogin-parse-words input-args)))
	 (host (car args))
	 (user (or (car (cdr (member "-l" args)))
                   (user-login-name)))
         (buffer-name (if (string= user (user-login-name))
                          (format "*rlogin-%s*" host)
                        (format "*rlogin-%s@%s*" user host)))
	 proc)

    (cond ((null prefix))
          ((numberp prefix)
           (setq buffer-name (format "%s<%d>" buffer-name prefix)))
          (t
           (setq buffer-name (generate-new-buffer-name buffer-name))))

    (pop-to-buffer buffer-name)
    (cond
     ((comint-check-proc buffer-name))
     (t
      (comint-exec (current-buffer) buffer-name rlogin-program nil args)
      (setq proc (get-process buffer-name))
      ;; Set process-mark to point-max in case there is text in the
      ;; buffer from a previous exited process.
      (set-marker (process-mark proc) (point-max))
      (rlogin-mode)

      ;; comint-output-filter-functions is just like a hook, except that the
      ;; functions in that list are passed arguments.  add-hook serves well
      ;; enough for modifying it.
      (add-hook 'comint-output-filter-functions 'rlogin-carriage-filter)

      (make-local-variable 'rlogin-host)
      (setq rlogin-host host)
      (make-local-variable 'rlogin-remote-user)
      (setq rlogin-remote-user user)

      (cond
       ((eq rlogin-directory-tracking-mode t)
        ;; Do this here, rather than calling the tracking mode function, to
        ;; avoid a gratuitous resync check; the default should be the
        ;; user's home directory, be it local or remote.
        (setq comint-file-name-prefix
              (concat "/" rlogin-remote-user "@" rlogin-host ":"))
        (cd-absolute comint-file-name-prefix))
       ((null rlogin-directory-tracking-mode))
       (t
        (cd-absolute (concat comint-file-name-prefix "~/"))))))))

(defun rlogin-mode ()
  "Set major-mode for rlogin sessions.
If `rlogin-mode-hook' is set, run it."
  (interactive)
  (kill-all-local-variables)
  (shell-mode)
  (setq major-mode 'rlogin-mode)
  (setq mode-name "rlogin")
  (use-local-map rlogin-mode-map)
  (setq shell-dirtrackp rlogin-directory-tracking-mode)
  (make-local-variable 'comint-file-name-prefix)
  (run-hooks 'rlogin-mode-hook))

(defun rlogin-directory-tracking-mode (&optional prefix)
  "Do remote or local directory tracking, or disable entirely.

If called with no prefix argument or a unspecified prefix argument (just
``\\[universal-argument]'' with no number) do remote directory tracking via
ange-ftp.  If called as a function, give it no argument.

If called with a negative prefix argument, disable directory tracking
entirely.

If called with a positive, numeric prefix argument, e.g.
``\\[universal-argument] 1 M-x rlogin-directory-tracking-mode\'',
then do directory tracking but assume the remote filesystem is the same as
the local system.  This only works in general if the remote machine and the
local one share the same directories (through NFS)."
  (interactive "P")
  (cond
   ((or (null prefix)
        (consp prefix))
    (setq rlogin-directory-tracking-mode t)
    (setq shell-dirtrack-p t)
    (setq comint-file-name-prefix
          (concat "/" rlogin-remote-user "@" rlogin-host ":")))
   ((< prefix 0)
    (setq rlogin-directory-tracking-mode nil)
    (setq shell-dirtrack-p nil))
   (t
    (setq rlogin-directory-tracking-mode 'local)
    (setq comint-file-name-prefix "")
    (setq shell-dirtrack-p t)))
  (cond
   (shell-dirtrack-p
    (let* ((proc (get-buffer-process (current-buffer)))
           (proc-mark (process-mark proc))
           (current-input (buffer-substring proc-mark (point-max)))
           (orig-point (point))
           (offset (and (>= orig-point proc-mark)
                        (- (point-max) orig-point))))
      (unwind-protect
          (progn
            (delete-region proc-mark (point-max))
            (goto-char (point-max))
            (shell-resync-dirs))
        (goto-char proc-mark)
        (insert current-input)
        (if offset
            (goto-char (- (point-max) offset))
          (goto-char orig-point)))))))


;; Parse a line into its constituent parts (words separated by
;; whitespace).  Return a list of the words.
(defun rlogin-parse-words (line)
  (let ((list nil)
	(posn 0)
        (match-data (match-data)))
    (while (string-match "[^ \t\n]+" line posn)
      (setq list (cons (substring line (match-beginning 0) (match-end 0))
                       list))
      (setq posn (match-end 0)))
    (store-match-data (match-data))
    (nreverse list)))

(defun rlogin-carriage-filter (string)
  (let* ((point-marker (point-marker))
         (end (process-mark (get-buffer-process (current-buffer))))
         (beg (or (and (boundp 'comint-last-output-start)
                       comint-last-output-start)
                  (- end (length string)))))
    (goto-char beg)
    (while (search-forward "\C-m" end t)
      (delete-char -1))
    (goto-char point-marker)))

(defun rlogin-send-Ctrl-C ()
  (interactive)
  (send-string nil "\C-c"))

(defun rlogin-send-Ctrl-D ()
  (interactive)
  (send-string nil "\C-d"))

(defun rlogin-send-Ctrl-Z ()
  (interactive)
  (send-string nil "\C-z"))

(defun rlogin-send-Ctrl-backslash ()
  (interactive)
  (send-string nil "\C-\\"))

(defun rlogin-delchar-or-send-Ctrl-D (arg)
  "\
Delete ARG characters forward, or send a C-d to process if at end of buffer."
  (interactive "p")
  (if (eobp)
      (rlogin-send-Ctrl-D)
    (delete-char arg)))

(defun rlogin-tab-or-complete ()
  "Complete file name if doing directory tracking, or just insert TAB."
  (interactive)
  (if rlogin-directory-tracking-mode
      (comint-dynamic-complete)
    (insert "\C-i")))

;;; rlogin.el ends here
