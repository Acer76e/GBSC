# Grade 6 Study Quiz 🎓

A fun multiple-choice study app to help prepare for the 6th grade final exam.

Covers vocabulary & roots, literary terms, pronouns, story structure, and writing.

## How to use it (3 ways)

### 1. Open it on a phone or computer (easiest)
Just open `index.html` in any modern web browser (Chrome, Safari, Firefox, Edge). Works offline once loaded — no install needed.

### 2. Install it on Android like an app (recommended for the phone)
1. In the repo settings on GitHub, enable **Pages** (Settings → Pages → Source: deploy from branch → pick this branch, folder: `/ (root)` → Save).
2. After a minute, GitHub gives you a URL like `https://acer76e.github.io/GBSC/`.
3. Open that URL in **Chrome on Android**.
4. Tap the three-dot menu → **Install app** (or **Add to Home Screen**).
5. An app icon appears on the home screen. Tapping it opens the quiz full‑screen, just like a regular APK.

### 3. Install it on iPhone/iPad
Open the GitHub Pages URL in **Safari** → Share button → **Add to Home Screen**.

## Features
- 🚀 Full quiz (all questions, shuffled) or ⚡ Quick 10-question quiz
- 📂 Study one topic at a time
- 🔥 Streak counter and high-score tracking (saved on the device)
- 📊 Score breakdown by topic
- 🎉 Confetti for great scores
- 🔊 Subtle sound effects for correct / wrong answers
- 📱 Works offline after first load (PWA)

## Android APK (sample build to show someone)

A real, installable `.apk` of the student app is built by GitHub Actions and published here:

**https://github.com/Acer76e/GBSC/releases/download/study-app-sample/study-quiz-sample.apk**

Open that link on the Android phone, allow the browser to install apps once, then tap Install.
The whole app is bundled inside the APK, so it needs no account, no login and no internet.

What the sample build leaves out (see `android/tools/make-sample.py`):
- the parent dashboard (the ⚙️ button) and its PIN
- cloud sync — nothing on the sample is tied to a real student

Everything else — all 10 subjects, all 8 games, trophies, streaks, progress history — is the app as it is on the web.

To rebuild it: push to `claude/julia-6th-grade-apk-ung6d6`, or run the **Build Study Quiz sample APK** workflow
from the Actions tab. The APK is a WebView wrapper (`android/`) around this repo's `index.html`.
