# Canonical Comparison Feature for Fill-in Flashcards

## Overview
This feature adds canonical Lojban comparison for fill-in mode flashcards, allowing the system to recognize semantically equivalent answers even when written differently.

## What it does
- When enabled, user answers in fill-in mode are parsed using the tersmu WASM parser
- Both the expected answer and the user's answer are converted to their canonical forms
- The canonical forms are compared instead of raw text
- If canonicalization fails, it falls back to standard string comparison
- This is turned on by default for new flashcards

## User Experience
- **Creating flashcards**: Users see a checkbox to enable/disable canonical comparison (default: enabled)
- **Studying**: For fill-in cards with canonical comparison enabled, a green badge appears showing the feature is active
- **Answering**: Users can write Lojban answers in different but equivalent forms and still be marked correct

## Example
If the expected answer is `mi ce do simxu lo ka ce'u ce'u prami` and the user writes it slightly differently but semantically equivalent, the canonical forms will match and the answer will be accepted as correct.
