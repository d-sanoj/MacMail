# Google API Setup for GmailBox

Follow these steps once before signing in with GmailBox.

1. Go to Google Cloud Console.
2. Create a new project named `GmailBox`.
3. Open "APIs & Services".
4. Click "Enable APIs and Services".
5. Search for "Gmail API".
6. Enable Gmail API.
7. Go to "OAuth consent screen".
8. Choose "External" if using a normal Gmail account.
9. Fill app name as `GmailBox`.
10. Fill user support email.
11. Fill developer contact email.
12. Add scopes:
    - `https://www.googleapis.com/auth/gmail.modify`
    - `https://www.googleapis.com/auth/gmail.labels`
    - `https://www.googleapis.com/auth/gmail.compose`
    - `https://www.googleapis.com/auth/gmail.send`
13. Add the user's Gmail accounts as test users.
14. Go to "Credentials".
15. Click "Create Credentials".
16. Choose "OAuth client ID".
17. Application type: "Desktop app".
18. Name it `GmailBox macOS`.
19. Download the OAuth client JSON.
20. Open GmailBox settings and click `Import OAuth JSON`.
21. Choose the OAuth client JSON you downloaded.

Important notes:

- GmailBox does not need your Gmail password.
- You log in on Google's official login page in your browser.
- GmailBox only receives OAuth tokens from Google after you approve access.
- Tokens are stored locally by GmailBox in Application Support.
- Each Gmail account gets its own token record so three personal accounts can be used independently.

For this SwiftPM project, the checked-in placeholder lives at:

`Sources/GmailBox/Config/GoogleOAuthClient.json`

For development, you can still replace that placeholder file manually. For normal app use, importing from Settings is better because GmailBox copies the JSON into:

`~/Library/Application Support/GmailBox/GoogleOAuthClient.json`

## Fix Error 403: access_denied

If Google shows:

`GmailBox has not completed the Google verification process`

then your OAuth app is still in testing mode and the account you are trying to sign in with is not approved as a test user.

Fix it in Google Cloud Console:

1. Open your `GmailBox` project.
2. Go to Google Auth Platform / OAuth consent screen.
3. Open the Audience or Test users section.
4. Add every Gmail address you want to use with GmailBox.
5. Save the changes.
6. Wait a minute, then try `Sign in with Google` again.

For personal use, you do not need to publish or verify the app as long as every account you use is listed as a test user. If you want other people outside your test-user list to use the app, Google may require OAuth verification because Gmail scopes are sensitive/restricted.

## What should happen after consent

After you click `Continue` on Google's "Select what GmailBox can access" screen, Google redirects the browser to a local callback page like `http://127.0.0.1:49152`. That page should say sign-in is complete, then you can return to GmailBox.

If the browser spins indefinitely, quit and relaunch GmailBox, then try signing in again. GmailBox keeps a temporary local callback server open for three minutes during sign-in.
