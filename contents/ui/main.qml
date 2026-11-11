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
import QtWebEngine
import QtQuick.LocalStorage 2.0 as LocalStorage
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "Storage.js" as Storage

PlasmoidItem {
    id: root
    preferredRepresentation: PlasmoidItem.FullRepresentation

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSize.small
        Layout.minimumHeight: Kirigami.Units.iconSize.small

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl(getIcon())
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

        property int wideThreshold: Math.min(760, Math.max(560, Number(plasmoid.configuration.wideThreshold || 700)))
        property bool splitMode: centerArea.width >= wideThreshold
        property var feeds: []
        property var groups: []
        property var articles: []
        property var selectedArticle: null
        property string articleViewMode: "reader" // reader ili website
        property int activeFeedIndex: -1
        property int activeGroupIndex: -1
        // Ograničavamo broj paralelnih RSS zahteva da QML interfejs
        // ne bude preopterećen kada postoji mnogo izvora.
        property int pendingRequests: 0
        property int activeRequests: 0
        property int maxConcurrentRequests: 2
        property var requestQueue: []
        property var queuedFeedIndices: []
        // Novi članci iz svih feedova čekaju završetak ciklusa osvežavanja.
        property var refreshNewArticles: []
        property int batchSize: 10
        property int articleDisplayLimit: 100
        property int loadedFeedCount: 0
        property var loadedFeedIndices: []
        property bool loading: false
        property string statusMessage: ""

        // --- PREUZIMANJE TEKSTA (ZADRŽANE SLIKE/MEDIJA, UKLONJENI HEDER I FUTER) ---
        function loadSelectedArticle() {
            if (!selectedArticle) return
            var view = splitMode ? wideWebView : narrowWebView

            if (articleViewMode === "website") {
                if (selectedArticle.link) view.url = selectedArticle.link
                else renderCleanHtml(view, selectedArticle.content || selectedArticle.summary || "<p>No content available.</p>")
                return
            }

            if (!selectedArticle.link) {
                renderCleanHtml(view, selectedArticle.content || selectedArticle.summary || "<p>No content available.</p>")
                return
            }

            view.loadHtml(`
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <style>
                        body {
                            background-color: ${Kirigami.Theme.backgroundColor} !important;
                            color: ${Kirigami.Theme.textColor} !important;
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
                            display: flex;
                            justify-content: center;
                            align-items: center;
                            height: 100vh;
                            margin: 0;
                        }
                        .loader {
                            color: ${Kirigami.Theme.highlightColor};
                            font-size: 16px;
                            font-weight: 500;
                        }
                    </style>
                </head>
                <body>
                    <div class="loader">Loading article text...</div>
                </body>
                </html>
            `)

            var xhr = new XMLHttpRequest()
            xhr.open("GET", selectedArticle.link)
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return

                if (xhr.status >= 200 && xhr.status < 400) {
                    var htmlText = xhr.responseText

                    var articleMatch = htmlText.match(/<article[\s\S]*?>([\s\S]*?)<\/article>/i) ||
                                       htmlText.match(/<main[\s\S]*?>([\s\S]*?)<\/main>/i) ||
                                       htmlText.match(/<div[^>]*class=["'][^"']*(?:post-content|article-body|entry-content|content|story-body)[^"']*["'][^>]*>([\s\S]*?)<\/div>/i)

                    var extractedContent = articleMatch ? articleMatch[1] : ""

                    if (!extractedContent || extractedContent.length < 200) {
                        var pMatches = htmlText.match(/<p\b[^>]*>[\s\S]*?<\/p>/gi)
                        if (pMatches && pMatches.length > 0) {
                            extractedContent = pMatches.join("\n")
                        } else {
                            extractedContent = selectedArticle.content || selectedArticle.summary
                        }
                    }

                    // Uklanjanje isključivo hedera, futera, navigacija i skripti/stilizacija sa sajta
                    extractedContent = extractedContent.replace(/<script[\s\S]*?<\/script>/gi, "")
                                                     .replace(/<style[\s\S]*?<\/style>/gi, "")
                                                     .replace(/<header[\s\S]*?<\/header>/gi, "")
                                                     .replace(/<footer[\s\S]*?<\/footer>/gi, "")
                                                     .replace(/<nav[\s\S]*?<\/nav>/gi, "")
                                                     .replace(/<aside[\s\S]*?<\/aside>/gi, "")

                    renderCleanHtml(view, extractedContent)
                } else {
                    renderCleanHtml(view, selectedArticle.content || selectedArticle.summary || "<p>Greška pri preuzimanju teksta.</p>")
                }
            }
            xhr.send()
        }

        function renderCleanHtml(view, bodyContent) {
            var bgColor = Kirigami.Theme.backgroundColor
            var textColor = Kirigami.Theme.textColor
            var linkColor = Kirigami.Theme.highlightColor
            var subtleColor = Kirigami.Theme.disabledTextColor
            var altBgColor = Kirigami.Theme.alternateBackgroundColor

            var finalCleanHtml = `
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <style>
                        body {
                            background-color: ${bgColor} !important;
                            color: ${textColor} !important;
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
                            line-height: 1.7 !important;
                            padding: 30px !important;
                            max-width: 720px !important;
                            margin: 0 auto !important;
                        }
                        h1 {
                            color: ${linkColor} !important;
                            font-size: 1.9em !important;
                            margin-bottom: 8px !important;
                            line-height: 1.3 !important;
                        }
                        .meta {
                            color: ${subtleColor} !important;
                            font-size: 0.88em !important;
                            margin-bottom: 20px !important;
                        }
                        p {
                            color: ${textColor} !important;
                            font-size: 16px !important;
                            margin-bottom: 18px !important;
                        }
                        img {
                            max-width: 100% !important;
                            height: auto !important;
                            border-radius: 8px !important;
                            margin: 20px 0 !important;
                            display: block !important;
                        }
                        a {
                            color: ${linkColor} !important;
                            text-decoration: none !important;
                        }
                        a:hover {
                            text-decoration: underline !important;
                        }
                        pre, code {
                            background: ${altBgColor} !important;
                            color: ${textColor} !important;
                            padding: 10px !important;
                            border-radius: 4px !important;
                            overflow-x: auto !important;
                        }
                        blockquote {
                            border-left: 3px solid ${linkColor} !important;
                            margin: 15px 0 !important;
                            padding-left: 15px !important;
                            color: ${subtleColor} !important;
                        }
                    </style>
                </head>
                <body>
                    <h1>${selectedArticle ? selectedArticle.title : ""}</h1>
                    <div class="meta">${selectedArticle ? selectedArticle.feedName : ""} ${selectedArticle && selectedArticle.date ? "· " + selectedArticle.date : ""}</div>
                    <hr style="border: 0; border-top: 1px solid ${subtleColor}; margin: 20px 0; opacity: 0.3;">
                    ${bodyContent}
                </body>
                </html>
            `
            view.loadHtml(finalCleanHtml)
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

        function readSavedData() {
            var saved = Storage.load(LocalStorage, plasmoid.configuration)
            feeds = saved.feeds
            groups = saved.groups
            loadedFeedIndices = saved.loadedFeedIndices
            loadedFeedCount = saved.loadedFeedCount
            articleDisplayLimit = saved.articleDisplayLimit
            activeFeedIndex = saved.activeFeedIndex
            activeGroupIndex = saved.activeGroupIndex

            if (feeds.length) {
                refreshAll()
            } else {
                statusMessage = qsTr("Add an RSS or Atom feed to get started.")
            }
        }

        function saveData() {
            Storage.save(LocalStorage, plasmoid.configuration, {
                feeds: feeds,
                groups: groups,
                loadedFeedIndices: loadedFeedIndices,
                loadedFeedCount: loadedFeedCount,
                articleDisplayLimit: articleDisplayLimit,
                activeFeedIndex: activeFeedIndex,
                activeGroupIndex: activeGroupIndex
            })
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

        // Stabilan identifikator članka: GUID/ID ima prednost, a link
        // služi kao rezervni ključ za feedove koji ne daju GUID.
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
            // Ne objavljuj listu dok svi zahtevi iz reda i svi aktivni
            // zahtevi nisu završeni.
            if (activeRequests !== 0 || requestQueue.length !== 0) return
            if (refreshNewArticles.length === 0) return

            // Sortiranje je globalno: ne zavisi od toga kojim redom
            // su pojedinačni RSS serveri odgovorili.
            var fresh = refreshNewArticles.slice()
            fresh.sort(function(a, b) {
                return articleTimestamp(b) - articleTimestamp(a)
            })

            // Postojeća arhiva ostaje netaknuta i pomera se naniže.
            articles = fresh.concat(articles)
            refreshNewArticles = []
            statusMessage = qsTr("New articles added") + ": " + fresh.length
        }

        function updateLoadingState() {
            pendingRequests = activeRequests + requestQueue.length
            loading = pendingRequests > 0
        }

        function enqueueFeed(index) {
            if (index < 0 || index >= feeds.length) return

            // Sprečava dupliranje zahteva za isti izvor u redu čekanja.
            if (queuedFeedIndices.indexOf(index) !== -1) return

            // Ako se izvor već učitava, ne pokrećemo još jedan zahtev.
            if (activeFeedRequests[index] === true) return

            if (loadedFeedIndices.indexOf(index) === -1) {
                loadedFeedIndices = loadedFeedIndices.concat([index])
            }

            requestQueue = requestQueue.concat([index])
            queuedFeedIndices = queuedFeedIndices.concat([index])
            updateLoadingState()
            processFeedQueue()
        }

        // Evidencija aktivnih zahteva po indeksu izvora.
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
                    // Parsiranje se izvršava samo za jedan završeni zahtev
                    // u datom trenutku, umesto za desetine izvora odjednom.
                    var parsed = parseFeed(req.responseText, index)

                    if (parsed && parsed.length > 0) {
                        // Postojeći članci ostaju netaknuti. Dodaju se samo
                        // članci koje već nemamo iz ovog feeda.
                        var known = ({})
                        for (var oldIndex = 0; oldIndex < articles.length; ++oldIndex) {
                            var oldArticle = articles[oldIndex]
                            if (oldArticle.feedIndex === index)
                                known[articleIdentity(oldArticle)] = true
                        }

                        // Uključi i već prikupljene nove članke iz istog feeda,
                        // kako se isti unos ne bi dodao dvaput u jednom ciklusu.
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

        // --- POMOĆNE FUNKCIJE ZA NAVIGACIJU KROZ VESTI ---
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

        Component.onCompleted: readSavedData()

        onSplitModeChanged: {
            if (selectedArticle) Qt.callLater(loadSelectedArticle)
        }

        Timer {
            interval: Math.max(2, Number(plasmoid.configuration.refreshMinutes || 15)) * 60000
            running: true
            repeat: true
            onTriggered: app.refreshAll()
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

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: "EQ-RSS Reader"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                    Layout.fillWidth: true
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    text: qsTr("Refresh")
                    onClicked: app.refreshAll()
                }
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

                Item {
                    id: centerArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 240

                    RowLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing

                        Item {
                            id: listPane
                            visible: app.splitMode || !app.selectedArticle
                            Layout.fillWidth: visible
                            Layout.fillHeight: true
                            Layout.minimumWidth: app.splitMode ? 250 : 0

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    PlasmaComponents.Label {
                                        text: app.activeFeedIndex >= 0 ? (app.feeds[app.activeFeedIndex] ? app.feeds[app.activeFeedIndex].name : qsTr("Articles")) :
                                              (app.activeGroupIndex >= 0 ? (app.groups[app.activeGroupIndex] ? app.groups[app.activeGroupIndex].name : qsTr("Group")) : qsTr("All articles"))
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.BusyIndicator {
                                        running: app.loading
                                        visible: running
                                        implicitWidth: 22
                                        implicitHeight: 22
                                    }
                                }

                                GridView {
                                    id: newsGrid
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: app.filteredArticles()
                                    cellWidth: Math.max(205, Math.min(300, width / Math.max(1, Math.floor(width / 245))))
                                    cellHeight: 310
                                    boundsBehavior: Flickable.StopAtBounds

                                    delegate: Rectangle {
                                        width: newsGrid.cellWidth - 8
                                        height: newsGrid.cellHeight - 8
                                        radius: 8
                                        color: Kirigami.Theme.alternateBackgroundColor
                                        border.color: Kirigami.Theme.separatorColor
                                        border.width: 1

                                        MouseArea {
                                            anchors.fill: parent
                                            z: 0
                                            onClicked: app.selectArticle(modelData)
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 9
                                            spacing: 5
                                            PlasmaComponents.Label {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                font.bold: true
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }
                                            Image {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 112
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                visible: modelData.image !== ""
                                            }
                                            PlasmaComponents.Label {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                text: modelData.summary
                                                maximumLineCount: 4
                                                elide: Text.ElideRight
                                                wrapMode: Text.WordWrap
                                                opacity: 0.82
                                            }
                                            PlasmaComponents.Label {
                                                Layout.fillWidth: true
                                                text: modelData.feedName + (modelData.date ? " · " + modelData.date : "")
                                                opacity: 0.65
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                elide: Text.ElideRight
                                            }
                                            PlasmaComponents.Button {
                                                Layout.fillWidth: true
                                                text: qsTr("Read more")
                                                icon.name: "document-open"
                                                onClicked: app.selectArticle(modelData)
                                            }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        anchors.centerIn: parent
                                        visible: newsGrid.count === 0
                                        text: app.statusMessage || qsTr("No articles")
                                        opacity: 0.7
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                PlasmaComponents.Button {
                                    Layout.fillWidth: true
                                    visible: app.activeFeedIndex === -1 &&
                                             app.activeGroupIndex === -1 &&
                                             app.articles.length > app.articleDisplayLimit
                                    text: qsTr("Load 100 more articles") +
                                          " (" + Math.min(100, app.articles.length - app.articleDisplayLimit) + ")"
                                    icon.name: "go-down"
                                    onClicked: app.loadMoreArticles()
                                }
                            }
                        }

                        Rectangle {
                            id: readerPane
                            visible: app.splitMode && !!app.selectedArticle
                            Layout.fillWidth: visible
                            Layout.fillHeight: true
                            Layout.minimumWidth: visible ? 280 : 0
                            radius: 8
                            color: Kirigami.Theme.alternateBackgroundColor
                            border.color: Kirigami.Theme.separatorColor
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5
                                RowLayout {
                                    Layout.fillWidth: true
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: app.selectedArticle ? app.selectedArticle.feedName : ""
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents.ToolButton {
                                        icon.name: "window-close"
                                        text: qsTr("Close")
                                        onClicked: app.goBackToList()
                                    }
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: app.selectedArticle ? app.selectedArticle.title : ""
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Previous")
                                        icon.name: "go-previous"
                                        enabled: app.hasPreviousArticle()
                                        onClicked: app.navigateArticle(-1)
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Reader View")
                                        icon.name: "text-plain"
                                        highlighted: app.articleViewMode === "reader"
                                        onClicked: app.setArticleViewMode("reader")
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Original Page")
                                        icon.name: "internet-web-browser"
                                        highlighted: app.articleViewMode === "website"
                                        onClicked: app.setArticleViewMode("website")
                                    }
                                    PlasmaComponents.ToolButton {
                                        visible: app.selectedArticle && app.selectedArticle.link !== ""
                                        text: qsTr("Open in Browser")
                                        icon.name: "window-new"
                                        onClicked: if (app.selectedArticle) Qt.openUrlExternally(app.selectedArticle.link)
                                    }
                            // SLEDEĆA (NEXT) - TEKST LEVO, IKONA DESNO
                                    PlasmaComponents.ToolButton {
                                        enabled: app.hasNextArticle()
                                        onClicked: app.navigateArticle(1)

                                        contentItem: RowLayout {
                                            spacing: 4
                                            Item { Layout.fillWidth: true } // Gura sadržaj u desnu stranu ako je potrebno, ili ukloni ako želiš levo
                                            PlasmaComponents.Label {
                                                text: "Next"
                                                color: Kirigami.Theme.textColor
                                                horizontalAlignment: Text.AlignRight
                                            }
                                            Kirigami.Icon {
                                                source: "go-next"
                                                implicitWidth: Kirigami.Units.iconSize.small
                                                implicitHeight: Kirigami.Units.iconSize.small
                                            }
                                        }
                                    }
                                }
                                WebEngineView {
                                    id: wideWebView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    profile: rssProfile
                                    settings.accelerated2dCanvasEnabled: true
                                    settings.webGLEnabled: true
                                    settings.localStorageEnabled: true
                                    settings.javascriptEnabled: true
                                }
                            }
                        }

                        Rectangle {
                            id: narrowPane
                            visible: !app.splitMode && !!app.selectedArticle
                            Layout.fillWidth: visible
                            Layout.fillHeight: true
                            radius: 8
                            color: Kirigami.Theme.alternateBackgroundColor
                            border.color: Kirigami.Theme.separatorColor
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5
                                RowLayout {
                                    Layout.fillWidth: true
                                    PlasmaComponents.ToolButton {
                                        icon.name: "go-previous"
                                        text: qsTr("Back")
                                        onClicked: app.goBackToList()
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: qsTr("Article")
                                        font.bold: true
                                    }
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: app.selectedArticle ? app.selectedArticle.title : ""
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Previous")
                                        icon.name: "go-previous"
                                        enabled: app.hasPreviousArticle()
                                        onClicked: app.navigateArticle(-1)
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Reader View")
                                        icon.name: "text-plain"
                                        highlighted: app.articleViewMode === "reader"
                                        onClicked: app.setArticleViewMode("reader")
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Original page")
                                        icon.name: "internet-web-browser"
                                        highlighted: app.articleViewMode === "website"
                                        onClicked: app.setArticleViewMode("website")
                                    }
                                    PlasmaComponents.ToolButton {
                                        visible: app.selectedArticle && app.selectedArticle.link !== ""
                                        text: qsTr("Open in Browser")
                                        icon.name: "window-new"
                                        onClicked: if (app.selectedArticle) Qt.openUrlExternally(app.selectedArticle.link)
                                    }
                                    // SLEDEĆA (NEXT) - TEKST LEVO, IKONA DESNO
                                    PlasmaComponents.ToolButton {
                                        enabled: app.hasNextArticle()
                                        onClicked: app.navigateArticle(1)

                                        contentItem: RowLayout {
                                            spacing: 4
                                            Item { Layout.fillWidth: true } // Gura sadržaj u desnu stranu ako je potrebno, ili ukloni ako želiš levo
                                            PlasmaComponents.Label {
                                                text: "Next"
                                                color: Kirigami.Theme.textColor
                                                horizontalAlignment: Text.AlignRight
                                            }
                                            Kirigami.Icon {
                                                source: "go-next"
                                                implicitWidth: Kirigami.Units.iconSize.small
                                                implicitHeight: Kirigami.Units.iconSize.small
                                            }
                                        }
                                    }
                                }
                                WebEngineView {
                                    id: narrowWebView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    profile: rssProfile
                                    settings.accelerated2dCanvasEnabled: true
                                    settings.webGLEnabled: true
                                    settings.localStorageEnabled: true
                                    settings.javascriptEnabled: true
                                }
                            }
                        }
                    }
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
