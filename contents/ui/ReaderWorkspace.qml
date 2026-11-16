/***************************************************************************
 *   EQ-RSS Reader - central article workspace                             *
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
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: workspace
    property var controller
    property var webProfile
    property color readerBackgroundColor: Kirigami.Theme.backgroundColor
    property int wideThreshold: 700
    property bool splitMode: width >= wideThreshold
    property var currentWebView: splitMode ? wideWebView : narrowWebView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 240

                    RowLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing

                        Item {
                            id: listPane
                            visible: splitMode || !controller.selectedArticle
                            Layout.fillWidth: visible
                            Layout.fillHeight: true
                            Layout.minimumWidth: splitMode ? 250 : 0

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    PlasmaComponents.Label {
                                        text: controller.activeFeedIndex >= 0 ? (controller.feeds[controller.activeFeedIndex] ? controller.feeds[controller.activeFeedIndex].name : qsTr("Articles")) :
                                              (controller.activeGroupIndex >= 0 ? (controller.groups[controller.activeGroupIndex] ? controller.groups[controller.activeGroupIndex].name : qsTr("Group")) : qsTr("All articles"))
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.BusyIndicator {
                                        running: controller.loading
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
                                    model: controller.filteredArticles()
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
                                            onClicked: controller.selectArticle(modelData)
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
                                                onClicked: controller.selectArticle(modelData)
                                            }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        anchors.centerIn: parent
                                        visible: newsGrid.count === 0
                                        text: controller.statusMessage || qsTr("No articles")
                                        opacity: 0.7
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                PlasmaComponents.Button {
                                    Layout.fillWidth: true
                                    visible: controller.activeFeedIndex === -1 &&
                                             controller.activeGroupIndex === -1 &&
                                             controller.articles.length > controller.articleDisplayLimit
                                    text: qsTr("Load 100 more articles") +
                                          " (" + Math.min(100, controller.articles.length - controller.articleDisplayLimit) + ")"
                                    icon.name: "go-down"
                                    onClicked: controller.loadMoreArticles()
                                }
                            }
                        }

                        Rectangle {
                            id: readerPane
                            visible: splitMode && !!controller.selectedArticle
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
                                        text: controller.selectedArticle ? controller.selectedArticle.feedName : ""
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents.ToolButton {
                                        icon.name: "window-close"
                                        text: qsTr("Close")
                                        onClicked: controller.goBackToList()
                                    }
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: controller.selectedArticle ? controller.selectedArticle.title : ""
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
                                        enabled: controller.hasPreviousArticle()
                                        onClicked: controller.navigateArticle(-1)
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Reader View")
                                        icon.name: "text-plain"
                                        highlighted: controller.articleViewMode === "reader"
                                        onClicked: controller.setArticleViewMode("reader")
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Original Page")
                                        icon.name: "internet-web-browser"
                                        highlighted: controller.articleViewMode === "website"
                                        onClicked: controller.setArticleViewMode("website")
                                    }
                                    PlasmaComponents.ToolButton {
                                        visible: controller.selectedArticle && controller.selectedArticle.link !== ""
                                        text: qsTr("Open in Browser")
                                        icon.name: "window-new"
                                        onClicked: if (controller.selectedArticle) Qt.openUrlExternally(controller.selectedArticle.link)
                                    }
                            // SLEDEĆA (NEXT) - TEKST LEVO, IKONA DESNO
                                    PlasmaComponents.ToolButton {
                                        enabled: controller.hasNextArticle()
                                        onClicked: controller.navigateArticle(1)

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
                                    profile: webProfile
                                    // Usklađuje pozadinu WebEngine površine sa KDE Plasma temom.
                                    backgroundColor: workspace.readerBackgroundColor
                                    settings.accelerated2dCanvasEnabled: true
                                    settings.webGLEnabled: true
                                    settings.localStorageEnabled: true
                                    settings.javascriptEnabled: true
                                }
                            }
                        }

                        Rectangle {
                            id: narrowPane
                            visible: !splitMode && !!controller.selectedArticle
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
                                        onClicked: controller.goBackToList()
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: qsTr("Article")
                                        font.bold: true
                                    }
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: controller.selectedArticle ? controller.selectedArticle.title : ""
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
                                        enabled: controller.hasPreviousArticle()
                                        onClicked: controller.navigateArticle(-1)
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Reader View")
                                        icon.name: "text-plain"
                                        highlighted: controller.articleViewMode === "reader"
                                        onClicked: controller.setArticleViewMode("reader")
                                    }
                                    PlasmaComponents.ToolButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Original page")
                                        icon.name: "internet-web-browser"
                                        highlighted: controller.articleViewMode === "website"
                                        onClicked: controller.setArticleViewMode("website")
                                    }
                                    PlasmaComponents.ToolButton {
                                        visible: controller.selectedArticle && controller.selectedArticle.link !== ""
                                        text: qsTr("Open in Browser")
                                        icon.name: "window-new"
                                        onClicked: if (controller.selectedArticle) Qt.openUrlExternally(controller.selectedArticle.link)
                                    }
                                    // SLEDEĆA (NEXT) - TEKST LEVO, IKONA DESNO
                                    PlasmaComponents.ToolButton {
                                        enabled: controller.hasNextArticle()
                                        onClicked: controller.navigateArticle(1)

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
                                    profile: webProfile
                                    // Usklađuje pozadinu WebEngine površine sa KDE Plasma temom.
                                    backgroundColor: workspace.readerBackgroundColor
                                    settings.accelerated2dCanvasEnabled: true
                                    settings.webGLEnabled: true
                                    settings.localStorageEnabled: true
                                    settings.javascriptEnabled: true
                                }
                            }
                        }
                    }
                }
