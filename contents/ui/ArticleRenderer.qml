/***************************************************************************
 *   EQ-RSS Reader - article loading and Reader View rendering             *
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

Item {
    id: renderer
    visible: false
    width: 0
    height: 0

    property var article: null
    property string viewMode: "reader"
    property var targetView: null

    // Boje prosleđuje glavni app objekat iz svog Plasma/Kirigami konteksta.
    property color readerBackgroundColor: "#ffffff"
    property color readerTextColor: "#202020"
    property color readerLinkColor: "#3daee9"
    property color readerSubtleColor: "#707070"
    property color readerCodeBackgroundColor: "#eeeeee"

        function loadSelectedArticle() {
            if (!article) return
            var view = targetView
            if (!view) return
            view.backgroundColor = readerBackgroundColor

            if (viewMode === "website") {
                if (article.link) view.url = article.link
                else renderCleanHtml(view, article.content || article.summary || "<p>No content available.</p>")
                return
            }

            if (!article.link) {
                renderCleanHtml(view, article.content || article.summary || "<p>No content available.</p>")
                return
            }

            view.loadHtml(`
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <style>
                        body {
                            background-color: ${readerBackgroundColor} !important;
                            color: ${readerTextColor} !important;
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
                            display: flex;
                            justify-content: center;
                            align-items: center;
                            height: 100vh;
                            margin: 0;
                        }
                        .loader {
                            color: ${readerLinkColor};
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
            xhr.open("GET", article.link)
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
                            extractedContent = article.content || article.summary
                        }
                    }

                    // --- READABILITY FILTRIRANJE UGRAĐENO DIREKTNO U QML ---

                    // 1. Uklanjanje skripti, stilova, noscript-a, hedera, futera, navigacija, aside-ova, formi, iframe-ova, objekata, embed-ova, dugmadi i inputa
                    extractedContent = extractedContent.replace(/<script[\s\S]*?<\/script>/gi, "")
                                                     .replace(/<noscript[\s\S]*?<\/noscript>/gi, "")
                                                     .replace(/<style[\s\S]*?<\/style>/gi, "")
                                                     .replace(/<header[\s\S]*?<\/header>/gi, "")
                                                     .replace(/<footer[\s\S]*?<\/footer>/gi, "")
                                                     .replace(/<nav[\s\S]*?<\/nav>/gi, "")
                                                     .replace(/<aside[\s\S]*?<\/aside>/gi, "")
                                                     .replace(/<form[\s\S]*?<\/form>/gi, "")
                                                     .replace(/<fieldset[\s\S]*?<\/fieldset>/gi, "")
                                                     .replace(/<iframe[\s\S]*?<\/iframe>/gi, "")
                                                     .replace(/<object[\s\S]*?<\/object>/gi, "")
                                                     .replace(/<embed[\s\S]*?<\/embed>/gi, "")
                                                     .replace(/<input\b[^>]*\/?>/gi, "")
                                                     .replace(/<textarea[\s\S]*?<\/textarea>/gi, "")
                                                     .replace(/<select[\s\S]*?<\/select>/gi, "")
                                                     .replace(/<button\b[\s\S]*?<\/button>/gi, "")

                    // 2. Uklanjanje elemenata sa sumnjivim ARIA ulogama (UNLIKELY_ROLES: menu, menubar, complementary, navigation, alert, alertdialog, dialog)
                    extractedContent = extractedContent.replace(/<([a-z0-9]+)\b[^>]*\brole\s*=\s*['"](?:menu|menubar|complementary|navigation|alert|alertdialog|dialog|button)['"][\s\S]*?<\/\1>/gi, "")
                                                     .replace(/<([a-z0-9]+)\b[^>]*\brole\s*=\s*['"](?:menu|menubar|complementary|navigation|alert|alertdialog|dialog|button)['"][^>]*\/?>/gi, "")

                    // 3. Uklanjanje elemenata sa negativnim klasama i ID-jevima (Readability regeksi za reklame, komentare, socijalne mreže, sidebar, widgete...)
                    var badClassRegex = /<(div|section|aside|ul|ol|table|span)\b([^>]*\b(?:class|id)\s*=\s*['"][^'"]*(-ad-|banner|combx|comment|community|disqus|extra|footer|gdpr|header|menu|outbrain|promo|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|popup|masthead|media|meta|shopping|tags|widget|share|sharedaddy|utility)[^'"]*['"][^>]*)>([\s\S]*?)<\/\1>/gi
                    for (var i = 0; i < 3; i++) {
                        extractedContent = extractedContent.replace(badClassRegex, "")
                    }

                    // 4. Uklanjanje blokova koji sadrže isključivo reči za reklame (adWords) ili učitavanje (loadingWords)
                    extractedContent = extractedContent.replace(/<p\b[^>]*>\s*(?:ad(?:vertising|vertisement)?|pub(?:licité)?|werb(?:ung)?|广告|Реклама|Anuncio|loading|正在加载|Загрузка|chargement|cargando)(?:…|\.\.\.)?\s*<\/p>/gi, "")

                    // --- KRAJ READABILITY FILTRIRANJA ---

                    renderCleanHtml(view, extractedContent)
                } else {
                    renderCleanHtml(view, article.content || article.summary || "<p>Greška pri preuzimanju teksta.</p>")
                }
            }
            xhr.send()
        }

        function renderCleanHtml(view, bodyContent) {
            var bgColor = readerBackgroundColor
            var textColor = readerTextColor
            var linkColor = readerLinkColor
            var subtleColor = readerSubtleColor
            var altBgColor = readerCodeBackgroundColor

            if (view) view.backgroundColor = bgColor

            var finalCleanHtml = `
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <style>
                        html, body {
                            background: ${bgColor} !important;
                            background-color: ${bgColor} !important;
                            color: ${textColor} !important;
                        }
                        body, body * {
                            color: ${textColor} !important;
                        }
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
                        a, a * {
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
                    <h1>${article ? article.title : ""}</h1>
                    <div class="meta">${article ? article.feedName : ""} ${article && article.date ? "· " + article.date : ""}</div>
                    <hr style="border: 0; border-top: 1px solid ${subtleColor}; margin: 20px 0; opacity: 0.3;">
                    ${bodyContent}
                </body>
                </html>
            `
            view.loadHtml(finalCleanHtml)
        }
}
