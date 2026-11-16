/***************************************************************************
 *   Copyright 2026 by Barnak Zlatko <saradnja.barnak@gmail.com>           *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 3 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   *   WITHOUT ANY WARRANTY; without even the implied warranty of        *
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
import QtWebEngine
import QtQuick.LocalStorage as LocalStorage
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: PlasmoidItem.FullRepresentation

    property int unreadNewArticlesCount: 0

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSize.small
        Layout.minimumHeight: Kirigami.Units.iconSize.small

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl(getIcon())
        }

        Rectangle {
            visible: root.unreadNewArticlesCount > 0
            anchors.right: parent.right
            anchors.top: parent.top
            width: Math.max(16, labelBadge.implicitWidth + 6)
            height: 16
            radius: 8
            color: Kirigami.Theme.negativeTextColor

            QQC2.Label {
                id: labelBadge
                anchors.centerIn: parent
                text: root.unreadNewArticlesCount > 99 ? "99+" : root.unreadNewArticlesCount
                font.pointSize: 8
                font.bold: true
                color: "white"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    function getIcon() {
        if (Plasmoid.configuration.useCustomIcon && Plasmoid.configuration.customIconPath) {
            return "file://" + Plasmoid.configuration.customIconPath;
        }
        return "assets/eq-rssnews.svg";
    }

    fullRepresentation: Item {
        id: app
        implicitWidth: 1120
        implicitHeight: 720

        // Izlažemo unread brojač direktno na controller-u
        property int unreadNewArticlesCount: root.unreadNewArticlesCount

        onUnreadNewArticlesCountChanged: {
            root.unreadNewArticlesCount = unreadNewArticlesCount
        }

        Connections {
            target: root
            function onUnreadNewArticlesCountChanged() {
                if (app.unreadNewArticlesCount !== root.unreadNewArticlesCount) {
                    app.unreadNewArticlesCount = root.unreadNewArticlesCount
                }
            }
        }

        property int wideThreshold: Math.min(760, Math.max(560, Number(plasmoid.configuration.wideThreshold || 700)))
        property bool splitMode: workspace.splitMode

        property color readerBackgroundColor: Kirigami.Theme.backgroundColor
        property color readerTextColor: Kirigami.Theme.textColor
        property color readerLinkColor: Kirigami.Theme.highlightColor
        property color readerSubtleColor: Kirigami.Theme.disabledTextColor
        property color readerCodeBackgroundColor: Kirigami.Theme.alternateBackgroundColor
        property var feeds: []
        property var groups: []
        property var articles: []
        property var selectedArticle: null
        property string articleViewMode: "reader"
        property int activeFeedIndex: -1
        property int activeGroupIndex: -1
        property int pendingRequests: 0
        property int activeRequests: 0
        property int maxConcurrentRequests: 2
        property var requestQueue: []
        property var queuedFeedIndices: []
        property var refreshNewArticles: []
        property int batchSize: 10
        property int articleDisplayLimit: 100
        property int loadedFeedCount: 0
        property var loadedFeedIndices: []
        property bool loading: false
        property string statusMessage: ""
        property bool autoRefreshEnabled: true

        // --- LocalStorage Database Functions (EQ-Notes style) ---
        function getDatabase() {
            return LocalStorage.LocalStorage.openDatabaseSync("EQrss_database", "1.0", "EQrss Storage", 1000000);
        }

        function readSavedData() {
            try {
                var db = getDatabase();
                db.transaction(function(tx) {
                    tx.executeSql('CREATE TABLE IF NOT EXISTS settings(key TEXT UNIQUE, value TEXT)');
                    var rs = tx.executeSql('SELECT value FROM settings WHERE key = ?', ['app_state']);
                    if (rs.rows.length > 0) {
                        var saved = JSON.parse(rs.rows.item(0).value);
                        feeds = saved.feeds || [];
                        groups = saved.groups || [];
                        loadedFeedIndices = saved.loadedFeedIndices || [];
                        loadedFeedCount = saved.loadedFeedCount || 0;
                        articleDisplayLimit = saved.articleDisplayLimit || 100;
                        activeFeedIndex = saved.activeFeedIndex !== undefined ? saved.activeFeedIndex : -1;
                        activeGroupIndex = saved.activeGroupIndex !== undefined ? saved.activeGroupIndex : -1;
                    }
                });
            } catch (err) {
                console.log("Error reading saved data: " + err);
            }

            if (feeds.length) {
                refreshAll();
            } else {
                statusMessage = qsTr("Add an RSS or Atom feed to get started.");
            }
        }

        function saveData() {
            try {
                var db = getDatabase();
                var dataToSave = {
                    feeds: feeds,
                    groups: groups,
                    loadedFeedIndices: loadedFeedIndices,
                    loadedFeedCount: loadedFeedCount,
                    articleDisplayLimit: articleDisplayLimit,
                    activeFeedIndex: activeFeedIndex,
                    activeGroupIndex: activeGroupIndex
                };

                var jsonData = JSON.stringify(dataToSave);
                db.transaction(function(tx) {
                    tx.executeSql('CREATE TABLE IF NOT EXISTS settings(key TEXT UNIQUE, value TEXT)');
                    tx.executeSql('INSERT OR REPLACE INTO settings(key, value) VALUES(?, ?)', ['app_state', jsonData]);
                });
            } catch (err) {
                console.log("Error saving data: " + err);
            }
        }
        // --------------------------------------------------------

        function clearNewArticlesCount() {
            root.unreadNewArticlesCount = 0
            app.unreadNewArticlesCount = 0
        }

        function loadSelectedArticle() {
            if (!selectedArticle) return
            articleRenderer.article = selectedArticle
            articleRenderer.viewMode = articleViewMode
            articleRenderer.targetView = workspace.currentWebView
            articleRenderer.loadSelectedArticle()
        }

        function sortedFeedIndices() {
            var indices = []
            for (var i = 0; i < feeds.length; ++i) indices.push(i)

            indices.sort(function(a, b) {
                var dateA = 0, dateB = 0
                for (var j = 0; j < articles.length; ++j) {
                    if (articles[j].feedIndex === a && (!dateA || Date.parse(articles[j].date) > dateA)) {
                        dateA = Date.parse(articles[j].date) || 0
                    }
                    if (articles[j].feedIndex === b && (!dateB || Date.parse(articles[j].date) > dateB)) {
                        dateB = Date.parse(articles[j].date) || 0
                    }
                }
                return dateB - dateA
            })
            return indices
        }

        function decodeEntities(value) {
            return String(value || "")
                .replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&")
                .replace(/&quot;/gi, '"').replace(/&#39;/gi, "'")
                .replace(/&apos;/gi, "'").replace(/&lt;/gi, "<")
                .replace(/&gt;/gi, ">")
                .replace(/&#(\d+);/g, function(m, n) { return String.fromCharCode(Number(n)) })
        }

        function cleanText(value) {
            var s = String(value || "")
            s = s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
                 .replace(/<script[\s\S]*?<\/script>/gi, "")
                 .replace(/<style[\s\S]*?<\/style>/gi, "")
                 .replace(/<[^>]*>/g, " ")
            return decodeEntities(s).replace(/\s+/g, " ").trim()
        }

        function rawTag(block, tag) {
            var safeTag = tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
            var m = block.match(new RegExp("<" + safeTag + "\\b[^>]*>([\\s\\S]*?)<\\/" + safeTag + "\\s*>", "i"))
            return m ? m[1].trim() : ""
        }

        function attrTag(block, tag, attr) {
            var safeTag = tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
            var m = block.match(new RegExp("<" + safeTag + "\\b([^>]*)>", "i"))
            if (!m) return ""
            var safeAttr = attr.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
            var a = m[1].match(new RegExp("\\b" + safeAttr + "\\s*=\\s*['\"]([^'\"]+)['\"]", "i"))
            return a ? a[1] : ""
        }

        function absoluteUrl(value, base) {
            var u = String(value || "").trim()
            if (!u) return ""
            if (/^https?:\/\//i.test(u) || /^data:/i.test(u)) return u
            if (u.indexOf("//") === 0) return "https:" + u
            var origin = String(base || "").match(/^(https?:\/\/[^/]+)/i)
            if (u.charAt(0) === "/" && origin) return origin[1] + u
            if (origin) {
                var path = String(base).replace(/[?#].*$/, "")
                return path.substring(0, path.lastIndexOf("/") + 1) + u
            }
            return u
        }

        function extractImage(block, base) {
            var u = attrTag(block, "media:content", "url") ||
                    attrTag(block, "media:thumbnail", "url") ||
                    attrTag(block, "enclosure", "url")
            if (!u) {
                var html = rawTag(block, "content:encoded") || rawTag(block, "description") || rawTag(block, "summary")
                var m = html.match(/<img\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]/i)
                if (m) u = m[1]
            }
            return absoluteUrl(u, base)
        }

        function articleIdentity(article) {
            var feedPart = String(article.feedIndex)
            var guid = String(article.guid || "").trim()
            if (guid) return feedPart + "|id|" + guid
            var link = String(article.link || "").trim()
            if (link) return feedPart + "|link|" + link
            return feedPart + "|title|" + String(article.title || "").trim() +
                   "|" + String(article.date || "").trim()
        }

        function parseFeed(xml, feedIndex) {
            var blocks = xml.match(/<(item|entry)\b[\s\S]*?<\/\1\s*>/gi) || []
            var result = []
            var feed = feeds[feedIndex]
            for (var i = 0; i < blocks.length; ++i) {
                var b = blocks[i]
                var title = cleanText(rawTag(b, "title")) || qsTr("Untitled article")
                var link = rawTag(b, "link") || attrTag(b, "link", "href")
                link = absoluteUrl(link.replace(/<!\[CDATA\[|\]\]>/g, "").trim(), feed ? feed.url : "")
                var content = rawTag(b, "content:encoded") || rawTag(b, "content") ||
                            rawTag(b, "description") || rawTag(b, "summary")
                var date = cleanText(rawTag(b, "pubDate") || rawTag(b, "published") ||
                                    rawTag(b, "updated") || rawTag(b, "dc:date"))
                var guid = cleanText(rawTag(b, "guid") || rawTag(b, "id"))
                result.push({
                    title: title, link: link, guid: guid,
                    summary: cleanText(content), content: content,
                    date: date, image: extractImage(b, feed ? feed.url : ""),
                    feedIndex: feedIndex, feedName: feed ? feed.name : ""
                })
            }
            return result
        }

        function articleTimestamp(article) {
            var value = String(article && article.date ? article.date : "").trim()
            if (!value) return 0
            var timestamp = Date.parse(value)
            return isNaN(timestamp) ? 0 : timestamp
        }

        function finalizeRefresh() {
            if (activeRequests !== 0 || requestQueue.length !== 0) return
            if (refreshNewArticles.length === 0) return

            var fresh = refreshNewArticles.slice()
            fresh.sort(function(a, b) {
                return articleTimestamp(b) - articleTimestamp(a)
            })

            articles = fresh.concat(articles)
            refreshNewArticles = []

            root.unreadNewArticlesCount += fresh.length
            app.unreadNewArticlesCount = root.unreadNewArticlesCount
            statusMessage = qsTr("New articles added") + ": " + fresh.length
        }

        function updateLoadingState() {
            pendingRequests = activeRequests + requestQueue.length
            loading = pendingRequests > 0
        }

        function enqueueFeed(index) {
            if (index < 0 || index >= feeds.length) return
            if (queuedFeedIndices.indexOf(index) !== -1) return
            if (activeFeedRequests[index] === true) return

            if (loadedFeedIndices.indexOf(index) === -1) {
                loadedFeedIndices = loadedFeedIndices.concat([index])
            }

            requestQueue = requestQueue.concat([index])
            queuedFeedIndices = queuedFeedIndices.concat([index])
            updateLoadingState()
            processFeedQueue()
        }

        property var activeFeedRequests: ({})

        function processFeedQueue() {
            while (activeRequests < maxConcurrentRequests && requestQueue.length > 0) {
                var index = requestQueue[0]
                requestQueue = requestQueue.slice(1)

                var queued = queuedFeedIndices.slice()
                var queuedPosition = queued.indexOf(index)
                if (queuedPosition !== -1) queued.splice(queuedPosition, 1)
                queuedFeedIndices = queued

                if (index < 0 || index >= feeds.length) {
                    updateLoadingState()
                    continue
                }

                if (activeFeedRequests[index] === true) {
                    updateLoadingState()
                    continue
                }

                startFeedRequest(index)
            }

            updateLoadingState()
            finalizeRefresh()
        }

        function startFeedRequest(index) {
            var req = new XMLHttpRequest()
            var completed = false

            activeFeedRequests[index] = true
            activeRequests++
            updateLoadingState()

            function finishRequest() {
                if (completed) return
                completed = true

                activeRequests = Math.max(0, activeRequests - 1)
                var active = Object.assign({}, activeFeedRequests)
                delete active[index]
                activeFeedRequests = active
                updateLoadingState()
                processFeedQueue()
            }

            req.open("GET", feeds[index].url)
            req.timeout = 20000

            req.onreadystatechange = function() {
                if (req.readyState !== XMLHttpRequest.DONE || completed) return

                if (req.status >= 200 && req.status < 400) {
                    var parsed = parseFeed(req.responseText, index)

                    if (parsed && parsed.length > 0) {
                        var known = ({})
                        for (var oldIndex = 0; oldIndex < articles.length; ++oldIndex) {
                            var oldArticle = articles[oldIndex]
                            if (oldArticle.feedIndex === index)
                                known[articleIdentity(oldArticle)] = true
                        }

                        for (var stagedIndex = 0; stagedIndex < refreshNewArticles.length; ++stagedIndex) {
                            var stagedArticle = refreshNewArticles[stagedIndex]
                            if (stagedArticle.feedIndex === index)
                                known[articleIdentity(stagedArticle)] = true
                        }

                        var addedCount = 0
                        for (var newIndex = 0; newIndex < parsed.length; ++newIndex) {
                            var candidate = parsed[newIndex]
                            var identity = articleIdentity(candidate)
                            if (!known[identity]) {
                                known[identity] = true
                                refreshNewArticles.push(candidate)
                                addedCount++
                            }
                        }

                        if (addedCount === 0)
                            statusMessage = qsTr("Feeds are up to date")
                    } else {
                        statusMessage = qsTr("No valid articles received. Previous articles preserved.")
                    }
                } else {
                    statusMessage = qsTr("Could not load") + ": " +
                                    feeds[index].name + " (" + req.status + ")"
                }

                finishRequest()
            }

            req.onerror = function() {
                if (completed) return
                statusMessage = qsTr("Network error while loading") +
                                " " + (feeds[index] ? feeds[index].name : "")
                finishRequest()
            }

            req.ontimeout = function() {
                if (completed) return
                statusMessage = qsTr("Request timed out") +
                                " " + (feeds[index] ? feeds[index].name : "")
                finishRequest()
            }

            req.send()
        }

        function fetchFeed(index) {
            enqueueFeed(index)
        }
        function toggleAutoRefresh() {
            autoRefreshEnabled = !autoRefreshEnabled
            if (autoRefreshEnabled) {
                statusMessage = qsTr("Automatski refresh je ponovo pokrenut.")
                refreshAll()
            } else {
                statusMessage = qsTr("Automatski refresh je pauziran.")
            }
        }
        function refreshAll() {
            if (!feeds.length) {
                articles = []
                refreshNewArticles = []
                loadedFeedCount = 0
                loadedFeedIndices = []
                saveData()
                statusMessage = qsTr("Add an RSS or Atom feed to get started.")
                return
            }

            if (loadedFeedCount === 0 && loadedFeedIndices.length === 0) {
                loadedFeedCount = Math.min(batchSize, feeds.length)
                for (var i = 0; i < loadedFeedCount; ++i) enqueueFeed(i)
                saveData()
            } else {
                var indices = loadedFeedIndices.slice()
                for (var j = 0; j < indices.length; ++j) enqueueFeed(indices[j])
            }

            statusMessage = qsTr("Updating loaded feeds…")
        }

        function fullRefreshAll() {
            if (!feeds.length) {
                statusMessage = qsTr("No feeds available for full refresh.")
                return
            }

            articles = []
            refreshNewArticles = []
            requestQueue = []
            queuedFeedIndices = []
            activeFeedRequests = {}
            activeRequests = 0

            clearNewArticlesCount()

            loadedFeedCount = feeds.length
            loadedFeedIndices = []
            for (var i = 0; i < feeds.length; ++i) {
                loadedFeedIndices.push(i)
            }
            saveData()

            for (var j = 0; j < feeds.length; ++j) {
                enqueueFeed(j)
            }

            statusMessage = qsTr("Performing full refresh of all feeds…")
        }

        function loadMoreFeeds() {
            if (loading || loadedFeedCount >= feeds.length) return

            var start = loadedFeedCount
            var end = Math.min(start + batchSize, feeds.length)
            loadedFeedCount = end
            saveData()

            var requested = 0
            for (var i = start; i < end; ++i) {
                if (loadedFeedIndices.indexOf(i) === -1) {
                    enqueueFeed(i)
                    requested++
                }
            }

            if (requested > 0) {
                saveData()
                statusMessage = qsTr("Loading feeds") + " " + (start + 1) + "–" + end
            }
        }

        function filteredArticles() {
            if (activeFeedIndex >= 0) {
                return articles.filter(function(a) { return a.feedIndex === activeFeedIndex })
            }
            if (activeGroupIndex >= 0 && groups[activeGroupIndex]) {
                var groupFeeds = groups[activeGroupIndex].feedIndices || []
                return articles.filter(function(a) { return groupFeeds.indexOf(a.feedIndex) !== -1 })
            }

            return articles.slice(0, articleDisplayLimit)
        }

        function loadMoreArticles() {
            articleDisplayLimit += 100
            saveData()
        }

        function addFeed(url) {
            var u = String(url || "").trim()
            if (!u) return
            if (!/^https?:\/\//i.test(u)) u = "https://" + u
            for (var i = 0; i < feeds.length; ++i) {
                if (feeds[i].url === u) {
                    statusMessage = qsTr("This feed is already in the list.")
                    return
                }
            }
            var host = u.replace(/^https?:\/\//, "").split("/")[0]
            feeds = feeds.concat([{ url: u, name: host, icon: "rss" }])
            var newIndex = feeds.length - 1
            if (newIndex === 0 && loadedFeedCount === 0) loadedFeedCount = 1
            discoverFeedInfo(u, newIndex)
            enqueueFeed(newIndex)
            saveData()
        }

        function addGroup(name) {
            var gName = String(name || "").trim()
            if (!gName) return
            for (var i = 0; i < groups.length; ++i) {
                if (groups[i].name.toLowerCase() === gName.toLowerCase()) {
                    statusMessage = qsTr("A group with this name already exists.")
                    return
                }
            }
            groups = groups.concat([{ name: gName, feedIndices: [] }])
            activeFeedIndex = -1
            activeGroupIndex = groups.length - 1
            selectedArticle = null
            saveData()
        }

        function addFeedToGroup(feedIndex, groupIndex) {
            if (feedIndex < 0 || feedIndex >= feeds.length ||
                    groupIndex < 0 || groupIndex >= groups.length) return

            var updatedGroups = groups.slice()
            var updatedGroup = {
                name: updatedGroups[groupIndex].name,
                feedIndices: (updatedGroups[groupIndex].feedIndices || []).slice()
            }

            if (updatedGroup.feedIndices.indexOf(feedIndex) !== -1) {
                statusMessage = qsTr("Feed is already in this group.")
                return
            }

            updatedGroup.feedIndices.push(feedIndex)
            updatedGroups[groupIndex] = updatedGroup
            groups = updatedGroups
            saveData()
            statusMessage = qsTr("Feed added to group: ") + updatedGroup.name
        }

        function removeFeedFromGroup(feedIndex, groupIndex) {
            if (groupIndex < 0 || groupIndex >= groups.length) return
            if (feedIndex < 0 || feedIndex >= feeds.length) return

            var updatedGroups = groups.slice()
            var updatedGroup = {
                name: updatedGroups[groupIndex].name,
                feedIndices: (updatedGroups[groupIndex].feedIndices || []).slice()
            }
            var position = updatedGroup.feedIndices.indexOf(feedIndex)
            if (position === -1) return

            updatedGroup.feedIndices.splice(position, 1)
            updatedGroups[groupIndex] = updatedGroup
            groups = updatedGroups
            saveData()
            statusMessage = qsTr("Feed removed from group: ") + updatedGroup.name
        }

        function activeGroupFeeds() {
            if (activeGroupIndex < 0 || activeGroupIndex >= groups.length) return []
            var indices = groups[activeGroupIndex].feedIndices || []
            var result = []
            for (var i = 0; i < indices.length; ++i) {
                var feedIndex = indices[i]
                if (feedIndex >= 0 && feedIndex < feeds.length) {
                    result.push({ feedIndex: feedIndex, name: feeds[feedIndex].name })
                }
            }

            result.sort(function(a, b) {
                var dateA = 0
                var dateB = 0
                for (var j = 0; j < articles.length; ++j) {
                    var articleDate = Date.parse(articles[j].date) || 0
                    if (articles[j].feedIndex === a.feedIndex && articleDate > dateA)
                        dateA = articleDate
                    if (articles[j].feedIndex === b.feedIndex && articleDate > dateB)
                        dateB = articleDate
                }
                return dateB - dateA
            })

            return result
        }

        function selectAllFeeds() {
            activeFeedIndex = -1
            activeGroupIndex = -1
            selectedArticle = null
            statusMessage = qsTr("Showing articles from all RSS feeds.")
            saveData()
        }

        function selectGroup(index) {
            if (index < 0 || index >= groups.length) return
            activeGroupIndex = index
            activeFeedIndex = -1
            selectedArticle = null
            saveData()
        }

        function removeGroup(index) {
            if (index < 0 || index >= groups.length) return
            var updated = groups.slice()
            updated.splice(index, 1)
            groups = updated
            if (activeGroupIndex === index) activeGroupIndex = -1
            else if (activeGroupIndex > index) activeGroupIndex--
            saveData()
        }

        function discoverFeedInfo(url, index) {
            var req = new XMLHttpRequest()
            req.open("GET", url)
            req.onreadystatechange = function() {
                if (req.readyState !== XMLHttpRequest.DONE || req.status < 200 || req.status >= 400) return
                var xml = req.responseText
                var title = cleanText(rawTag(xml, "title"))
                var site = rawTag(xml, "link") || attrTag(xml, "link", "href") || url
                var host = site.replace(/^(https?:\/\/[^/]+).*$/, "$1")
                var updated = feeds.slice()
                if (updated[index]) {
                    if (title) updated[index].name = title
                    updated[index].icon = host + "/favicon.ico"
                    feeds = updated
                    saveData()
                }
            }
            req.send()
        }

        function removeFeed(index) {
            var loaded = []
            for (var k = 0; k < loadedFeedIndices.length; ++k) {
                if (loadedFeedIndices[k] === index) continue
                loaded.push(loadedFeedIndices[k] > index ? loadedFeedIndices[k] - 1 : loadedFeedIndices[k])
            }
            loadedFeedIndices = loaded
            if (index < loadedFeedCount) loadedFeedCount = Math.max(0, loadedFeedCount - 1)

            var updated = feeds.slice()
            updated.splice(index, 1)
            feeds = updated
            var kept = []
            for (var i = 0; i < articles.length; ++i) {
                if (articles[i].feedIndex === index) continue
                if (articles[i].feedIndex > index) articles[i].feedIndex--
                kept.push(articles[i])
            }
            articles = kept
            var updatedGroups = []
            for (var g = 0; g < groups.length; ++g) {
                var indices = (groups[g].feedIndices || []).slice()
                var pos = indices.indexOf(index)
                if (pos !== -1) indices.splice(pos, 1)
                for (var j = 0; j < indices.length; ++j) {
                    if (indices[j] > index) indices[j]--
                }
                updatedGroups.push({ name: groups[g].name, feedIndices: indices })
            }
            groups = updatedGroups
            if (selectedArticle && selectedArticle.feedIndex === index) selectedArticle = null
            else if (selectedArticle && selectedArticle.feedIndex > index) selectedArticle.feedIndex--
            if (activeFeedIndex === index) activeFeedIndex = -1
            else if (activeFeedIndex > index) activeFeedIndex--
            saveData()
        }

        function selectArticle(article) {
            selectedArticle = article
            articleViewMode = "reader"
            loadSelectedArticle()
        }

        function setArticleViewMode(mode) {
            if (!selectedArticle) return
            articleViewMode = mode
            loadSelectedArticle()
        }

        function goBackToList() {
            selectedArticle = null
        }

        function navigateArticle(step) {
            var list = filteredArticles()
            if (!selectedArticle || list.length === 0) return
            var currentIndex = -1
            for (var i = 0; i < list.length; i++) {
                if (list[i].link === selectedArticle.link && list[i].title === selectedArticle.title) {
                    currentIndex = i
                    break
                }
            }
            var nextIndex = currentIndex + step
            if (nextIndex >= 0 && nextIndex < list.length) {
                selectArticle(list[nextIndex])
            }
        }

        function hasPreviousArticle() {
            var list = filteredArticles()
            if (!selectedArticle || list.length === 0) return false
            for (var i = 0; i < list.length; i++) {
                if (list[i].link === selectedArticle.link && list[i].title === selectedArticle.title) {
                    return i > 0
                }
            }
            return false
        }

        function hasNextArticle() {
            var list = filteredArticles()
            if (!selectedArticle || list.length === 0) return false
            for (var i = 0; i < list.length; i++) {
                if (list[i].link === selectedArticle.link && list[i].title === selectedArticle.title) {
                    return i < list.length - 1
                }
            }
            return false
        }

        ArticleRenderer {
            id: articleRenderer
            readerBackgroundColor: app.readerBackgroundColor
            readerTextColor: app.readerTextColor
            readerLinkColor: app.readerLinkColor
            readerSubtleColor: app.readerSubtleColor
            readerCodeBackgroundColor: app.readerCodeBackgroundColor
        }

        Component.onCompleted: readSavedData()

        onSplitModeChanged: {
            if (selectedArticle) Qt.callLater(loadSelectedArticle)
        }

        Timer {
            id: refreshTimer
            interval: Math.max(2, Number(plasmoid.configuration.refreshMinutes || 15)) * 60000
            running: app.autoRefreshEnabled
            repeat: true
            onTriggered: {
                if (app.autoRefreshEnabled) {
                    app.refreshAll()
                }
            }
        }

        QQC2.Menu {
            id: addToGroupMenu
            property int feedIndex: -1

            Repeater {
                model: app.groups
                QQC2.MenuItem {
                    text: modelData.name
                    onTriggered: app.addFeedToGroup(addToGroupMenu.feedIndex, index)
                }
            }
        }

        WebEngineProfile {
            id: rssProfile
            storageName: "EQrss_profil"
            persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        }

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
            radius: Kirigami.Units.cornerRadius
            border.color: Kirigami.Theme.separatorColor
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            HeaderBar {
                Layout.fillWidth: true
                controller: app
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Kirigami.Theme.separatorColor
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing

                FeedSidebar {
                    controller: app
                }

                ReaderWorkspace {
                    id: workspace
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 240
                    controller: app
                    webProfile: rssProfile
                    wideThreshold: app.wideThreshold
                    readerBackgroundColor: app.readerBackgroundColor
                }

                ManagementSidebar {
                    controller: app
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: app.statusMessage
                opacity: 0.65
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
