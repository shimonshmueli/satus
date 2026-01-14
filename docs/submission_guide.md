# App Submission Guide

## Prerequisites
1.  **Apple Developer Account**: Ensure you are enrolled in the Apple Developer Program.
2.  **Certificates**: You must have a valid "Apple Distribution" certificate in your Keychain.
3.  **App Record**: Create the app record in App Store Connect with the Bundle ID `com.shimonshmueli.Satus`.

## Creating a Release Build
To create a build signed for distribution (App Store/TestFlight), run the archive script with the `--release` flag:

```bash
./archive_app.sh --release
```

This will:
- Set the signing identity to "Apple Distribution".
- Create an archive in the `Builds/` directory.
- Open the archive in **Xcode Organizer**.

## Uploading to App Store Connect
1.  In **Xcode Organizer**, select the latest archive.
2.  Click **Distribute App**.
3.  Select **TestFlight & App Store**.
4.  Click **Distribute**.
5.  Xcode will validate the archive and upload it.

## Troubleshooting
- **Signing Errors**: If the script fails during signing, open `Keychain Access` and ensure you have a certificate named "Apple Distribution".
- **Ambiguous Identity**: If you have multiple distribution certificates, you may need to edit `archive_app.sh` to provide the specific certificate ID.
