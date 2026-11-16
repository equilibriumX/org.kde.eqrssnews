/***************************************************************************
 *   Copyright 2026 by Barnak Zlatko <saradnja.barnak@gmail.com>           *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 3 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .        *
 ***************************************************************************/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: managementSidebar
    property var controller

    property var discoveredFeeds: []
    property string discoveryStatus: ""
    property bool discovering: false

    function normalizeWebsiteUrl(value) {
        var url = (value || "").trim()
        if (!url)
            return ""
        if (!/^https?:\/\//i.test(url))
            url = "https://" + url
        return url.replace(/\/+$/, "")
    }

    function htmlAttribute(tagText, attributeName) {
        var escapedName = attributeName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        var regex = new RegExp("(?:^|\\s)" + escapedName + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", "i")
        var match = tagText.match(regex)
        if (!match)
            return ""
        return (match[1] !== undefined ? match[1] :
                match[2] !== undefined ? match[2] : match[3]).trim()
    }

    function decodeHtmlAttribute(value) {
        return (value || "").replace(/&amp;/gi, "&")
                             .replace(/&quot;/gi, "\"")
                             .replace(/&#39;|&apos;/gi, "'")
                             .replace(/&lt;/gi, "<")
                             .replace(/&gt;/gi, ">")
    }

    function resolveFeedUrl(href, baseUrl) {
        href = decodeHtmlAttribute((href || "").trim())
        if (!href || /^(javascript|data|mailto):/i.test(href))
            return ""

        // Keep absolute HTTP(S) URLs unchanged.
        if (/^https?:\/\//i.test(href))
            return href

        var protocolMatch = baseUrl.match(/^(https?):\/\//i)
        var originMatch = baseUrl.match(/^(https?:\/\/[^\/]+)/i)
        if (!protocolMatch || !originMatch)
            return ""

        var protocol = protocolMatch[1] + ":"
        var origin = originMatch[1]
        if (href.indexOf("//") === 0)
            return protocol + href
        if (href.charAt(0) === "#")
            return ""

        // Remove query and fragment from the base before resolving a relative path.
        var cleanBase = baseUrl.split("#")[0].split("?")[0]
        if (href.charAt(0) === "/")
            return origin + href

        var lastSlash = cleanBase.lastIndexOf("/")
        var directory = cleanBase.substring(0, lastSlash + 1)
        var combined = directory + href

        // Normalize ./ and ../ path segments without changing the query string.
        var queryIndex = combined.search(/[?#]/)
        var pathPart = queryIndex >= 0 ? combined.substring(0, queryIndex) : combined
        var suffix = queryIndex >= 0 ? combined.substring(queryIndex) : ""
        var prefixMatch = pathPart.match(/^(https?:\/\/[^\/]+)(.*)$/i)
        if (!prefixMatch)
            return combined
        var segments = prefixMatch[2].split("/")
        var normalized = []
        for (var i = 0; i < segments.length; ++i) {
            if (segments[i] === "..") {
                if (normalized.length > 0)
                    normalized.pop()
            } else if (segments[i] !== ".") {
                normalized.push(segments[i])
            }
        }
        return prefixMatch[1] + normalized.join("/") + suffix
    }

    function addDiscoveredFeed(url, label) {
        if (!url)
            return
        for (var i = 0; i < discoveredFeeds.length; ++i) {
            if (discoveredFeeds[i].url === url)
                return
        }
        var updated = discoveredFeeds.slice(0)
        updated.push({ "url": url, "name": label || url })
        discoveredFeeds = updated
    }

    function discoverWebsiteFeeds() {
        var websiteUrl = normalizeWebsiteUrl(websiteInput.text)
        if (!websiteUrl) {
            discoveryStatus = qsTr("Enter a website address.")
            return
        }

        discoveredFeeds = []
        discoveryStatus = qsTr("Searching website for RSS/Atom feeds...")
        discovering = true

        var request = new XMLHttpRequest()
        var completed = false
        request.open("GET", websiteUrl)
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || completed)
                return
            completed = true

            var found = []
            if (request.status >= 200 && request.status < 400) {
                var html = request.responseText || ""
                var pageUrl = request.responseURL || websiteUrl
                var linkRegex = /<link\b[^>]*>/gi
                var tag
                while ((tag = linkRegex.exec(html)) !== null) {
                    var tagText = tag[0]
                    var rel = htmlAttribute(tagText, "rel").toLowerCase().split(/\s+/)
                    var type = htmlAttribute(tagText, "type").toLowerCase().split(";")[0].trim()
                    var href = htmlAttribute(tagText, "href")
                    if (!href || rel.indexOf("alternate") === -1)
                        continue
                    if (type === "application/rss+xml" ||
                        type === "application/atom+xml" ||
                        type === "application/rdf+xml") {
                        var resolved = resolveFeedUrl(href, pageUrl)
                        if (resolved)
                            found.push({ "url": resolved, "name": resolved })
                    }
                }
            }

            if (found.length > 0) {
                discoveredFeeds = found
                discoveryStatus = qsTr("Found %1 feed(s). Select one to add.").arg(found.length)
                discovering = false
            } else {
                testFallbackFeedPaths(websiteUrl, 0)
            }
        }
        request.onerror = function() {
            if (completed)
                return
            completed = true
            testFallbackFeedPaths(websiteUrl, 0)
        }
        request.send()
    }

    function testFallbackFeedPaths(websiteUrl, candidateIndex) {
        var paths = ["/feed", "/feed/", "/rss", "/rss.xml", "/feed.xml",
                     "/atom.xml", "/index.xml", "/feeds/posts/default?alt=rss"]
        if (candidateIndex >= paths.length) {
            discovering = false
            discoveryStatus = discoveredFeeds.length > 0
                              ? qsTr("Found %1 possible feed(s).").arg(discoveredFeeds.length)
                              : qsTr("No RSS/Atom feed was found on this website.")
            return
        }

        var candidate = resolveFeedUrl(paths[candidateIndex], websiteUrl)
        var request = new XMLHttpRequest()
        var completed = false
        request.open("GET", candidate)
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || completed)
                return
            completed = true

            var body = request.responseText || ""
            var looksLikeFeed = request.status >= 200 && request.status < 400 &&
                                (/<rss\b/i.test(body) || /<feed\b/i.test(body) ||
                                 /<rdf:RDF\b/i.test(body))
            if (looksLikeFeed)
                addDiscoveredFeed(candidate, candidate)

            testFallbackFeedPaths(websiteUrl, candidateIndex + 1)
        }
        request.onerror = function() {
            if (completed)
                return
            completed = true
            testFallbackFeedPaths(websiteUrl, candidateIndex + 1)
        }
        request.send()
    }

    function addFoundFeed(url) {
        controller.addFeed(url)
        discoveryStatus = qsTr("Feed added.")
    }

                        Layout.fillHeight: true
                        Layout.preferredWidth: 230
                        Layout.minimumWidth: 175
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.alternateBackgroundColor

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            PlasmaComponents.Button {
                                Layout.fillWidth: true
                                text: qsTr("ALL RSS FEEDS")
                                icon.name: "view-list-details"
                                highlighted: controller.activeFeedIndex === -1 && controller.activeGroupIndex === -1
                                onClicked: controller.selectAllFeeds()
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Kirigami.Theme.separatorColor
                            }

                            PlasmaComponents.Label {
                                text: qsTr("Feed groups")
                                font.bold: true
                            }

                            ListView {
                                id: groupsList
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(contentHeight, 150)
                                Layout.minimumHeight: 45
                                clip: true
                                spacing: 3
                                model: controller.groups
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 36
                                    radius: 5
                                    color: controller.activeGroupIndex === index ? Kirigami.Theme.highlightColor : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 2
                                        spacing: 2

                                        PlasmaComponents.ToolButton {
                                            Layout.preferredWidth: 28
                                            icon.name: controller.activeGroupIndex === index ? "folder-open" : "folder"
                                            onClicked: controller.selectGroup(index)
                                        }

                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            font.bold: controller.activeGroupIndex === index
                                            elide: Text.ElideRight
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: controller.selectGroup(index)
                                            }
                                        }

                                        PlasmaComponents.ToolButton {
                                            Layout.preferredWidth: 28
                                            icon.name: "edit-delete"
                                            onClicked: controller.removeGroup(index)
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        z: -1
                                        onClicked: controller.selectGroup(index)
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                text: controller.activeGroupIndex >= 0 && controller.groups[controller.activeGroupIndex]
                                      ? qsTr("Feeds in selected group") : qsTr("Select a group to manage its feeds")
                                font.bold: true
                                opacity: 0.85
                            }

                            ListView {
                                id: groupFeedsList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 30
                                clip: true
                                spacing: 2
                                model: controller.activeGroupFeeds()
                                delegate: RowLayout {
                                    width: ListView.view.width
                                    height: 30
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        icon.name: "list-remove"
                                        text: qsTr("Remove from group")
                                        onClicked: controller.removeFeedFromGroup(modelData.feedIndex, controller.activeGroupIndex)
                                    }
                                }
                                PlasmaComponents.Label {
                                    anchors.centerIn: parent
                                    visible: groupFeedsList.count === 0
                                    text: controller.activeGroupIndex >= 0 ? qsTr("No feeds in this group") : qsTr("No group selected")
                                    opacity: 0.6
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                QQC2.TextField {
                                    id: groupInput
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("New group...")
                                    onAccepted: {
                                        controller.addGroup(text)
                                        text = ""
                                    }
                                }
                                PlasmaComponents.Button {
                                    icon.name: "list-add"
                                    text: qsTr("Add")
                                    onClicked: {
                                        controller.addGroup(groupInput.text)
                                        groupInput.text = ""
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Kirigami.Theme.separatorColor
                            }

                            PlasmaComponents.Label {
                                text: qsTr("RSS sources")
                                font.bold: true
                            }

                            ListView {
                                id: feedsList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 80
                                clip: true
                                spacing: 3
                                model: controller.feeds
                                delegate: RowLayout {
                                    width: ListView.view.width
                                    height: 36
                                    PlasmaComponents.ToolButton {
                                        Layout.preferredWidth: 30
                                        icon.name: "rss"
                                        onClicked: {
                                            controller.activeFeedIndex = index
                                            controller.activeGroupIndex = -1
                                            controller.selectedArticle = null
                                            controller.saveData()
                                        }
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                controller.activeFeedIndex = index
                                                controller.activeGroupIndex = -1
                                                controller.selectedArticle = null
                                                controller.saveData()
                                                if (!controller.articles.some(function(a) { return a.feedIndex === index; }))
                                                    controller.fetchFeed(index)
                                            }
                                        }
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.preferredWidth: 30
                                        icon.name: "edit-delete"
                                        text: qsTr("Remove")
                                        onClicked: controller.removeFeed(index)
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: qsTr("Loaded") + " " + controller.loadedFeedCount + " / " + controller.feeds.length
                                opacity: 0.7
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                horizontalAlignment: Text.AlignHCenter
                            }

                            PlasmaComponents.Button {
                                Layout.fillWidth: true
                                visible: controller.loadedFeedCount < controller.feeds.length
                                enabled: !controller.loading
                                icon.name: "go-down"
                                text: qsTr("Load 50 more")
                                onClicked: controller.loadMoreFeeds()
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Kirigami.Theme.separatorColor
                            }

                            PlasmaComponents.Label {
                                text: qsTr("Add RSS feed")
                                font.bold: true
                            }
                            QQC2.TextField {
                                id: feedInput
                                Layout.fillWidth: true
                                placeholderText: "https://example.com/feed.xml"
                                onAccepted: {
                                    controller.addFeed(text)
                                    text = ""
                                }
                            }
                            PlasmaComponents.Button {
                                Layout.fillWidth: true
                                icon.name: "list-add"
                                text: qsTr("Add RSS feed")
                                onClicked: {
                                    controller.addFeed(feedInput.text)
                                    feedInput.text = ""
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Kirigami.Theme.separatorColor
                            }

                            PlasmaComponents.Button {
                                Layout.fillWidth: true
                                icon.name: "system-search"
                                text: qsTr("Find RSS on website")
                                onClicked: websiteFinderDialog.open()
                            }
                        }

                        QQC2.Dialog {
                            id: websiteFinderDialog
                            title: qsTr("Find RSS feeds on website")
                            modal: false
                            focus: true
                            width: 740
                            height: 470
                            standardButtons: QQC2.Dialog.Close

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Enter a website address. EQ-RSS Reader will search its HTML for RSS/Atom feeds and check common feed locations if needed.")
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.TextField {
                                        id: websiteInput
                                        Layout.fillWidth: true
                                        placeholderText: "https://example.com"
                                        enabled: !managementSidebar.discovering
                                        onAccepted: managementSidebar.discoverWebsiteFeeds()
                                    }
                                    PlasmaComponents.Button {
                                        Layout.preferredWidth: 145
                                        enabled: !managementSidebar.discovering && websiteInput.text.trim().length > 0
                                        icon.name: managementSidebar.discovering ? "view-refresh" : "system-search"
                                        text: managementSidebar.discovering ? qsTr("Searching...") : qsTr("Find feeds")
                                        onClicked: managementSidebar.discoverWebsiteFeeds()
                                    }
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    visible: managementSidebar.discoveryStatus.length > 0
                                    text: managementSidebar.discoveryStatus
                                    wrapMode: Text.WordWrap
                                    opacity: 0.8
                                }

                                ListView {
                                    id: discoveredFeedsList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: Kirigami.Units.smallSpacing
                                    model: managementSidebar.discoveredFeeds

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: Math.max(66, feedUrlLabel.implicitHeight + 24)
                                        radius: Kirigami.Units.cornerRadius
                                        color: Kirigami.Theme.alternateBackgroundColor

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                id: feedUrlLabel
                                                Layout.fillWidth: true
                                                text: modelData.url
                                                wrapMode: Text.WrapAnywhere
                                                verticalAlignment: Text.AlignVCenter
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                textFormat: Text.PlainText
                                            }

                                            PlasmaComponents.Button {
                                                Layout.alignment: Qt.AlignVCenter
                                                icon.name: "list-add"
                                                text: qsTr("Add")
                                                onClicked: managementSidebar.addFoundFeed(modelData.url)
                                            }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        anchors.centerIn: parent
                                        visible: discoveredFeedsList.count === 0 && !managementSidebar.discovering && managementSidebar.discoveryStatus.length === 0
                                        text: qsTr("Discovered feeds will appear here.")
                                        opacity: 0.6
                                    }
                                }
                            }
                        }

}
