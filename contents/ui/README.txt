EQ-RSS Reader - modular QML layout

Place these QML files together in the same UI directory, preserving the
existing plasmoid directory structure. Keep the original Storage.js file
in this same directory: main.qml still imports it for persistent storage.

Files:
- main.qml: application root and RSS/feed business logic
- HeaderBar.qml: top application header and manual Refresh button
- ReaderWorkspace.qml: article grid and responsive article reader panes
- ArticleRenderer.qml: article loading, HTML cleanup and Reader View rendering
- FeedSidebar.qml: existing feed navigation sidebar
- ManagementSidebar.qml: existing feed/group management sidebar
- configGeneral.qml: existing general configuration page

The original RSS refresh timer, manual refresh behavior, feed/group handling,
article sorting, and storage calls have been retained.
