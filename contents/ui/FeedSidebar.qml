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
    id: feedSidebar
    property var controller

                        Layout.fillHeight: true
                        Layout.preferredWidth: 62
                        Layout.minimumWidth: 54
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.alternateBackgroundColor

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 4

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 7
                                    color: (controller.activeFeedIndex === -1 && controller.activeGroupIndex === -1) ? Kirigami.Theme.highlightColor : "transparent"
                                }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: "view-list-details"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        controller.selectAllFeeds()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Kirigami.Theme.separatorColor
                            }

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: controller.sortedFeedIndices()
                                spacing: 5
                                clip: true
                                delegate: Item {
                                    property int originalIndex: modelData
                                    width: ListView.view.width
                                    height: 42

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 7
                                        color: controller.activeFeedIndex === originalIndex ? Kirigami.Theme.highlightColor : "transparent"
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        spacing: 1

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Image {
                                                id: sourceFavicon
                                                anchors.centerIn: parent
                                                width: 22
                                                height: 22
                                                source: (controller.feeds[originalIndex] ? controller.feeds[originalIndex].icon : "")
                                                fillMode: Image.PreserveAspectFit
                                                visible: status === Image.Ready
                                            }
                                            Kirigami.Icon {
                                                anchors.centerIn: parent
                                                width: 22
                                                height: 22
                                                source: "rss"
                                                visible: !sourceFavicon.visible
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    controller.activeFeedIndex = originalIndex
                                                    controller.activeGroupIndex = -1
                                                    controller.selectedArticle = null
                                                    controller.saveData()
                                                    if (!controller.articles.some(function(a) { return a.feedIndex === originalIndex; }))
                                                        controller.fetchFeed(originalIndex)
                                                }
                                            }
                                        }

                                        QQC2.ToolButton {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 38
                                            icon.name: "list-add"
                                            text: "+"
                                            onClicked: {
                                                if (controller.groups.length === 0) {
                                                    controller.statusMessage = qsTr("Create a group on the right first.")
                                                    return
                                                }
                                                addToGroupMenu.feedIndex = originalIndex
                                                addToGroupMenu.popup()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                
}
