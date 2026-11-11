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
                        }
                
}
