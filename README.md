# MacMail <img src="AppLogo/icon.png" width="32" height="32" />

MacMail is a native macOS email client designed specifically for Gmail and Google Calendar, built with Swift, SwiftUI, and AppKit. It interfaces directly with the Google APIs using OAuth 2.0 and stores data in a local SQLite database, avoiding the use of web wrappers.

## Features

### Architecture
- **Native UI**: Built with SwiftUI and AppKit.
- **SQLite Caching**: Local caching of emails, threads, labels, and synchronization states using an SQLite database.
- **Dark Mode Support**: Adheres to system-wide appearance settings.

### Email Operations
- **Multi-Account Support**: Authenticate and switch between multiple Google accounts.
- **Three-Column Layout**: Includes a collapsible sidebar, a thread list, and a reading pane.
- **Undo Send**: Provides a 5-second delay before dispatching emails to the network, allowing message recall.
- **Rich Text Composer**: Supports bold, italics, underline, lists, indents, and font colors.
- **Google Drive Integration**: Insert links to Google Drive files directly into messages.
- **Inline Attachments**: Support for image drag-and-drop within the composer.
- **Custom Signatures**: Supports custom text and image signatures appended automatically to new messages.

### Google Calendar Integration
- **Agenda Sidebar**: A dedicated panel for viewing upcoming calendar events.
- **Smart Meet Links**: Automatically extracts and displays a "Join Meet" button for events containing Google Meet URLs.

## Setup & Installation

MacMail requires a configured Google Cloud Project to generate OAuth credentials.

> **Setup Instructions:** Please refer to [GOOGLE_API_SETUP.md](GOOGLE_API_SETUP.md) for detailed configuration steps.

### Building from Source

To compile the application via command line:
```bash
swift build
```

To build and package the macOS App bundle (including the application icon):
```bash
./script/build_and_run.sh
```

## Security

- **Direct Communication**: Interfaces directly with Google's API servers.
- **OAuth 2.0 Authorization**: Operates without requesting or storing user passwords.
- **Local Data Storage**: All cached emails, calendar events, and OAuth tokens are stored exclusively on the local machine within the user's Library directory.

## Technical Specifications
- Language: Swift 5.10
- Frameworks: SwiftUI, AppKit, Foundation
- Network: URLSession
- Storage: SQLite3, JSONEncoder/JSONDecoder
- Build System: Swift Package Manager
