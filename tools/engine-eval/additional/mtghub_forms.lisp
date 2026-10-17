;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; SPDX-FileCopyrightText: 2026 Hexproof contributors
;;;; Read the pinned engine's core sources without substituting missing dependencies.
(let ((files '("src/game-machine/game-machine.lisp"
               "src/game-machine/macros.lisp" "src/game-machine/mgml.lisp"
               "src/game-engines/duel.lisp" "src/game.lisp" "src/repl.lisp")))
  (dolist (file files)
    (with-open-file (stream file)
      (let ((forms (loop for form = (read stream nil :eof)
                         until (eq form :eof) collect form)))
        (format t "~A forms=~D content=~S~%" file (length forms) forms)))))
