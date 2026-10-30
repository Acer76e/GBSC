# Project memory: Julia's study app (GBSC)

Notes for future sessions working on this repo. Keep this file updated when subjects, deploy setup, or decisions change.

## What this is
- A multiple-choice study app for Julia, a Florida 6th grader (2026-27 school year). Single file: `index.html`, installed on her phone as a PWA.
- She struggles most with math and science. Goal: solidify 6th grade and get ahead for 7th, aligned to Florida standards (B.E.S.T. for math, NGSSS for science).
- The app may serve a Catholic school (there is a "Catholic Social Teachings" topic), so her class may not follow state standards exactly. Her teachers' topic lists win over the state standards.

## Deploy
- GitHub Pages publishes from branch `claude/grade-6-study-app-4QBBw` (the repo's default branch) via `.github/workflows/pages.yml`.
- The workflow stages only the app files (`index.html`, `sw.js`, `manifest.webmanifest`, `icon.svg`, `icon-maskable.svg`) into `_site`. Anything else in the repo is not published. If a new asset file is added, add it to the `cp` line in the workflow.
- Bump the cache name in `sw.js` (`g6-quiz-vNN`) on every content change so phones pick up the update. Last used: `v28`.
- Work branches fast-forward onto the Pages branch to publish.

## How a subject is wired in `index.html`
1. Data constants placed before `const SUBJECTS = {`: `QUIZ_X` (topics, each with `title`, `emoji`, `color`, `questions`), `TIPS_X` (HTML allowed), `X_KEY_ORDER`, and `BOSSES_X`.
2. Questions: `{ q, a: 0, opts: [correct, wrong, wrong, wrong], hint }`. The correct answer is always first; the app shuffles. `q`, `opts`, `hint` are HTML-escaped plain text; tips render HTML.
3. Entry in `SUBJECTS`, key added to `SUBJECT_ORDER`, a `boss_<key>` trophy in the trophy list (awarded automatically when all bosses in the subject are beaten), and `<key>: BOSSES_X` in `BOSSES`.
4. Test headless with Playwright: load the page, check `SUBJECTS`/`BOSSES` counts, `enterSubject('<key>')`, start a Quick Quiz, and confirm no page errors.

## Subjects added on 2026-10-30 (all Florida-aligned)
| Key | Title | Topics / Qs | Trophy |
|---|---|---|---|
| `g6math` | FL 6th Grade Math | 12 / 120 | Sunshine Mathlete |
| `g6sci` | FL 6th Grade Science | 12 / 120 | Sunshine Scientist |
| `cross` | Math + Science Skills | 8 / 80 | Bridge Builder |
| `g7math` | FL 7th Grade Math Preview | 12 / 120 | Seventh Grade Rocket |
| `g7sci` | FL 7th Grade Science Preview | 12 / 120 | Seventh Grade Scientist |
| `accel` | Accelerated Math (Grade 8 Topics) | 12 / 120 | Fast Tracker |

Earlier subjects that overlap and should not be duplicated: `ratios`, `cells`, `microbes`, `bacteria`, `protists`, `math` ("Math 7"), `algebra`.

Question design used throughout: wrong answers are built from real misconceptions, hints teach the method and name the trap, Florida contexts (beach, softball, manatees, hurricanes, springs, Everglades), preview topics start with two easy concept questions. No em dashes in new content (the owner's preference).

## Research findings (report was removed from the repo; it is in git history)
- Florida math: B.E.S.T. Grade 6 has 31 benchmarks (integers are Grade 6 in Florida, no probability until Grade 7); Grade 7 has 37. Accelerated path: Grade 6 Accelerated (1205020), Grade 7 Accelerated (1205050, includes all of Grade 8), Algebra 1 in 8th grade. Placement is set by districts, often FAST Level 4 or 5.
- Florida science: 2008 NGSSS still in force for 2026-27. A draft rewrite was released 2026-09-25 with a State Board vote expected December 2026, phasing in over four years; evolution and climate content are the most likely to change.
- Her current science unit (bacteria, protists, microbes, cells) matches SC.6.L.14 and SC.6.L.15.1, most likely Comprehensive Science 1 (course 2002040). If her schedule says 2000010, it is Life Science only.
- Testing: FAST math PM1 Aug 3 to Sep 25 2026, PM2 Nov 30 2026 to Jan 22 2027, PM3 May 3 to 28 2027 (only PM3 counts). Grade 6 gets a four-function calculator, Grade 7 a scientific one. No state science test until the Grade 8 Statewide Science Assessment, which covers grades 6 to 8.
- Study method: short, spaced, mixed quizzes (retrieval practice) beat rereading. Fraction and division skill is the strongest predictor of later algebra success.
- Many official sites (fldoe.org, cpalms.org) were blocked by the session network policy, so some science benchmark wording, course codes and the Grade 7 FAST weights were not verified against primary sources.

## Decisions
- Research notes and the report were removed from the repo and the public site; git history was deliberately left as is.
- Four Grade 7 preview questions go slightly past the Grade 7 limits (two two-step inequalities, two compound probability items). Kept on purpose as gentle stretch items.

## Open items
- Waiting on Julia's current class topics and notes to add matching questions.
- Confirm her course numbers (science 2002040 vs 2000010; regular vs accelerated math).
- Possible textbook naming mismatch: six kingdoms use "Archaebacteria/Eubacteria"; switch to "Archaea/Bacteria" if her book does.
- `index.html` references `icon-180.png`, which does not exist in the repo (pre-existing).
