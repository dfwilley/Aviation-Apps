# Installing Hangar Log on an iPhone

Hangar Log is a personal app for N721NE. It isn't on the App Store. There are two ways to install it. Both use your paid Apple Developer account.

| | TestFlight (recommended) | Sideloadly |
|---|---|---|
| Cable needed | No | Yes, every install and update |
| How long a build works | 90 days per build; each new build restarts the 90 days | About 1 year |
| Updates | Arrive on the phone automatically | Download the new file and repeat the install |
| Carolyn's phone | Invite her by email | Plug her phone into the PC |

Use one method per phone. Both install the same app (same bundle ID, `com.dfwilley.hangarvoicelog`), so installing one replaces the other.

## Option 1: TestFlight

### Get a new build to TestFlight

Every change to `hangar-voice-log/` on `main` uploads a new build automatically. To upload one without a change:

1. Open https://github.com/dfwilley/Aviation-Apps/actions
2. Click **Hangar Voice Log - upload to TestFlight** → **Run workflow** → **Run workflow**.
3. Apple takes about 5 to 30 minutes to process the build.

### Add testers (one time)

1. Open https://appstoreconnect.apple.com → **Apps** → **Hangar Voice Log** → **TestFlight**.
2. Under **Internal Testing**, create a group (for example "Family") if there isn't one, turn on **automatic distribution**, and add yourself and Carolyn. Internal testers must be users on your App Store Connect team (Users and Access → +, with a role such as **Developer**, **App Manager** or **Marketing**).
3. Each tester gets an email invitation.

### On each iPhone (one time)

1. Install **TestFlight** from the App Store.
2. Open the invitation email on the phone and tap **View in TestFlight** → **Accept** → **Install**.
3. Open **Hangar Log**. Allow the microphone and speech recognition when it asks.

TestFlight builds stop opening 90 days after upload. Any new upload restarts that clock, and the phone updates on its own.

The rejected App Store submission doesn't affect TestFlight. Internal testing doesn't need Apple's review.

## Option 2: Sideloadly (Windows PC)

### One-time setup on the PC

1. Install **iTunes and iCloud from Apple's website**, not the Microsoft Store versions. Sideloadly's home page (https://sideloadly.io) links to the right downloads.
2. Install **Sideloadly** from https://sideloadly.io.
3. Restart the PC.

### Get the app file

1. Open https://github.com/dfwilley/Aviation-Apps/releases
2. Under the newest **Hangar Log build** (tag starts with `hangar-voice-log-build-`), click **HangarVoiceLog.ipa** to download it.

### Put it on the iPhone

1. Plug the iPhone into the PC and unlock it. Tap **Trust** if asked.
2. Open Sideloadly. The iPhone appears in the **iDevice** box.
3. Enter the Apple ID of your **paid Apple Developer account** in the **Apple account** box. (A free Apple ID also works, but the app then stops opening after 7 days.)
4. Drag **HangarVoiceLog.ipa** onto the IPA icon and click **Start**. Enter the password and two-factor code when asked. Sideloadly sends them only to Apple.
5. Wait for **Done.** in Sideloadly's log.

### First launch (one time per phone)

1. **Developer Mode:** Settings → Privacy & Security → **Developer Mode** → On → Restart, then tap **Turn On**.
2. If iOS says the developer isn't trusted: Settings → General → VPN & Device Management → your developer account → **Trust**.
3. Open **Hangar Log** and allow the microphone and speech recognition.

To update, download the newer file and repeat "Put it on the iPhone". Entries are kept.

## After installing: link the Dropbox folder (both methods)

The app starts set up for N721NE · RV-14. To get your standard jobs and last Hobbs from Access:

1. In Hangar Log, tap the **gear** (top right).
2. Under **Access database link**, tap **Choose Folder**.
3. Pick **Dropbox › Dropbox Documents › N721NE › Maintenance Software**.

Each morning a scheduled Claude task reads `Maintenance Record_be.accdb` and, when something changed, saves a new `Hangar Log Data <date>.json` file in that folder. The app reads the newest one each time it opens. Finished entries go into `Claude Logbook Import.txt` in the same folder; run **ImportClaudeLogbookEntries** in Access to bring them in.

The Dropbox app must be installed on the iPhone for the folder to appear in the picker.
