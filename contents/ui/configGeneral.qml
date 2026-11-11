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
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    QQC2.SpinBox {
        Kirigami.FormData.label: i18n("Refresh interval (minutes):")
        from: 2
        to: 1440
        value: plasmoid.configuration.refreshMinutes
        onValueModified: plasmoid.configuration.refreshMinutes = value
    }
    QQC2.SpinBox {
        Kirigami.FormData.label: i18n("Split reader when central area is at least:")
        from: 560
        to: 760
        stepSize: 20
        value: plasmoid.configuration.wideThreshold
        onValueModified: plasmoid.configuration.wideThreshold = value
    }
}
