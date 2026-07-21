# Mobile Context Inbox

Dayflow Dev can import lightweight iPhone context from an iCloud Drive folder.
This is meant for notes, links, calls, errands, and off-Mac work that screen
recording cannot see.

## Mac Setup

1. Open Dayflow Dev.
2. Go to Settings > Export > Mobile context inbox.
3. Use the default folder:
   `~/Library/Mobile Documents/com~apple~CloudDocs/Dayflow/Mobile Inbox`
4. Click Create folder.
5. Keep these enabled unless you want a narrower workflow:
   - Include mobile notes in Markdown exports.
   - Include mobile notes in Daily standup generation.

Dayflow matches `.md`, `.markdown`, and `.txt` files by either:

- a `yyyy-MM-dd` date in the filename, or
- the file's modified date.

## iPhone Setup

The simplest first workflow is a Shortcut that appends text to a dated Markdown
file in iCloud Drive.

1. Open Shortcuts on iPhone.
2. Create a shortcut named `Add Dayflow mobile note`.
3. Add `Ask for Input`.
   - Prompt: `What should Dayflow remember?`
   - Type: Text.
4. Add `Date`.
   - Format: Custom.
   - Custom format: `yyyy-MM-dd`
5. Add `Text` with this template:

   ```text
   ## Current Date

   Provided Input
   ```

6. Add `Save File`.
   - Service: iCloud Drive.
   - Path: `Dayflow/Mobile Inbox/`
   - File name: `Current Date-mobile.md`
   - Turn on `Append to File`.
   - Turn off `Ask Where to Save`.

Optional variants:

- Add the shortcut to the Share Sheet so links can be sent into the inbox.
- Create a second shortcut for voice dictation using `Dictate Text`.
- Save screenshots manually into the same folder, then add a text note that
  explains why the screenshot matters.

## Current Limitations

- This is file-based sync, not a live iOS companion app.
- Images are not OCR'd or summarized yet.
- Notes are imported into exports and Daily generation context, but they do not
  create timeline cards by themselves.
- Duplicates are possible if the same note is appended repeatedly.
