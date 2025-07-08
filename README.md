# Org SRS

Org SRS is a lightweight spaced reptition system (SRS) using Emac's Org mode.

Each flashcard is an Org entry, and card parameters are stored as properties. Three properties are stored:
1. `CURRENT-INTERVAL` is the time in days for the next review when the card is reviewed.
2. `EASE` is the easiness of the card.
3. `NEXT-REVIEW` is the date when the card should be reviewed.

See [org-srs.org](org-srs.org) for design details.

## Usage

Require the feature in your `init.el`, pointing to the source file, and set the org files to use as appropriate:

```elisp
(require 'org-srs "~/.emacs.d/org-srs.el")
(setq org-srs-files (directory-files "~/flashcards" t directory-files-no-dot-files-regexp))
```

The Org SRS files should have headlines, e.g.:

```
* Org SRS is great!
```

Run `M-x org-srs-drill` to start the drill. The card will show up:

```
残りカード：1
復習時間：2025-07-08 00:51:49
Org SRS is great!
```

and you will be prompted in the minibuffer. Upon review, the card will
be automatically updated, e.g.:

```
* Org SRS is great!
:PROPERTIES:
:CURRENT-INTERVAL: 2.5
:EASE:     2.5
:NEXT-REVIEW: Thu Jul 10 12:52:35 2025
:END:
```
