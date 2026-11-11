.pragma library

// EQ-RSS Reader persistent storage.
// The primary copy is stored in QtQuick.LocalStorage (SQLite), which is
// independent of a particular Plasma applet instance. Removing and adding
// the plasmoid again therefore does not remove the saved RSS configuration.

var DATABASE_NAME = "EQ-RSS-Reader"
var DATABASE_VERSION = "1.0"
var DATABASE_DESCRIPTION = "EQ-RSS Reader persistent settings"

function _parseJson(value, fallback) {
    try {
        var parsed = JSON.parse(value || "null")
        return parsed === null ? fallback : parsed
    } catch (e) {
        return fallback
    }
}

function _validArray(value) {
    return Array.isArray(value) ? value : []
}

function _openDatabase(localStorage) {
    return localStorage.openDatabaseSync(
        DATABASE_NAME,
        DATABASE_VERSION,
        DATABASE_DESCRIPTION,
        1024 * 1024
    )
}

function _readDatabase(localStorage) {
    var payload = null
    var db = _openDatabase(localStorage)

    db.transaction(function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)")
        var result = tx.executeSql("SELECT payload FROM app_state WHERE id = 1")
        if (result.rows.length > 0)
            payload = result.rows.item(0).payload
    })

    return payload ? _parseJson(payload, null) : null
}

function _writeDatabase(localStorage, state) {
    var db = _openDatabase(localStorage)
    var payload = JSON.stringify(state)

    db.transaction(function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)")
        tx.executeSql("INSERT OR REPLACE INTO app_state (id, payload) VALUES (1, ?)", [payload])
    })
}

function _stateFromConfiguration(configuration) {
    var state = _parseJson(configuration.savedState, {})
    var legacyFeeds = _parseJson(configuration.feeds, [])
    var legacyGroups = _parseJson(configuration.groups, [])

    var feeds = Array.isArray(state.feeds) ? state.feeds : _validArray(legacyFeeds)
    var groups = Array.isArray(state.groups) ? state.groups : _validArray(legacyGroups)

    return {
        version: 1,
        feeds: feeds,
        groups: groups,
        loadedFeedUrls: _validArray(state.loadedFeedUrls),
        loadedFeedIndices: _validArray(state.loadedFeedIndices),
        loadedFeedCount: Number(state.loadedFeedCount || 0),
        articleDisplayLimit: Number(state.articleDisplayLimit || 100),
        activeFeedUrl: state.activeFeedUrl || "",
        activeGroupName: state.activeGroupName || ""
    }
}

function _normaliseState(state) {
    state = state || {}
    var feeds = _validArray(state.feeds)
    var groups = _validArray(state.groups)
    var loadedIndices = []
    var loadedUrls = _validArray(state.loadedFeedUrls)

    for (var i = 0; i < loadedUrls.length; ++i) {
        for (var f = 0; f < feeds.length; ++f) {
            if (feeds[f] && feeds[f].url === loadedUrls[i]) {
                if (loadedIndices.indexOf(f) === -1) loadedIndices.push(f)
                break
            }
        }
    }

    // Compatibility with the previous savedState format (indices).
    if (!loadedIndices.length) {
        var oldIndices = _validArray(state.loadedFeedIndices)
        for (var j = 0; j < oldIndices.length; ++j) {
            var oldIndex = Number(oldIndices[j])
            if (oldIndex >= 0 && oldIndex < feeds.length && loadedIndices.indexOf(oldIndex) === -1)
                loadedIndices.push(oldIndex)
        }
    }

    var selectedFeedIndex = -1
    if (state.activeFeedUrl) {
        for (var k = 0; k < feeds.length; ++k) {
            if (feeds[k] && feeds[k].url === state.activeFeedUrl) {
                selectedFeedIndex = k
                break
            }
        }
    }

    var selectedGroupIndex = -1
    if (state.activeGroupName) {
        for (var g = 0; g < groups.length; ++g) {
            if (groups[g] && groups[g].name === state.activeGroupName) {
                selectedGroupIndex = g
                break
            }
        }
    }

    var count = Number(state.loadedFeedCount || 0)
    if (!isFinite(count) || count < 0) count = 0
    count = Math.min(Math.floor(count), feeds.length)
    if (count === 0 && loadedIndices.length) {
        for (var n = 0; n < loadedIndices.length; ++n)
            count = Math.max(count, loadedIndices[n] + 1)
    }

    var limit = Number(state.articleDisplayLimit || 100)
    if (!isFinite(limit) || limit < 100) limit = 100

    return {
        feeds: feeds,
        groups: groups,
        loadedFeedIndices: loadedIndices,
        loadedFeedCount: count,
        articleDisplayLimit: Math.floor(limit),
        activeFeedIndex: selectedFeedIndex,
        activeGroupIndex: selectedGroupIndex
    }
}

function load(localStorage, configuration) {
    // First try the independent SQLite database.
    try {
        var persistentState = _readDatabase(localStorage)
        if (persistentState)
            return _normaliseState(persistentState)
    } catch (e) {
        console.log("EQ-RSS Reader: LocalStorage read failed: " + e)
    }

    // First run after upgrading: migrate the previous Plasma configuration
    // into SQLite. This also preserves feeds/groups from the original version.
    var legacyState = _stateFromConfiguration(configuration)
    try {
        _writeDatabase(localStorage, legacyState)
    } catch (e2) {
        console.log("EQ-RSS Reader: LocalStorage migration failed: " + e2)
    }

    return _normaliseState(legacyState)
}

function save(localStorage, configuration, data) {
    var feeds = _validArray(data.feeds)
    var groups = _validArray(data.groups)
    var loadedIndices = _validArray(data.loadedFeedIndices)
    var loadedUrls = []

    for (var i = 0; i < loadedIndices.length; ++i) {
        var index = Number(loadedIndices[i])
        if (index >= 0 && index < feeds.length && feeds[index] && feeds[index].url) {
            var url = feeds[index].url
            if (loadedUrls.indexOf(url) === -1) loadedUrls.push(url)
        }
    }

    var activeFeedUrl = ""
    if (data.activeFeedIndex >= 0 && data.activeFeedIndex < feeds.length && feeds[data.activeFeedIndex])
        activeFeedUrl = feeds[data.activeFeedIndex].url || ""

    var activeGroupName = ""
    if (data.activeGroupIndex >= 0 && data.activeGroupIndex < groups.length && groups[data.activeGroupIndex])
        activeGroupName = groups[data.activeGroupIndex].name || ""

    var state = {
        version: 1,
        feeds: feeds,
        groups: groups,
        loadedFeedUrls: loadedUrls,
        loadedFeedCount: Math.max(0, Number(data.loadedFeedCount || 0)),
        articleDisplayLimit: Math.max(100, Number(data.articleDisplayLimit || 100)),
        activeFeedUrl: activeFeedUrl,
        activeGroupName: activeGroupName
    }

    // Primary save: survives removing/re-adding the Plasma widget.
    try {
        _writeDatabase(localStorage, state)
    } catch (e) {
        console.log("EQ-RSS Reader: LocalStorage write failed: " + e)
    }

    // Keep the old Plasma settings in sync as a fallback and for downgrade
    // compatibility. These are no longer the primary storage location.
    try {
        configuration.savedState = JSON.stringify(state)
        configuration.feeds = JSON.stringify(feeds)
        configuration.groups = JSON.stringify(groups)
    } catch (e2) {
        console.log("EQ-RSS Reader: Plasma config backup failed: " + e2)
    }
}
