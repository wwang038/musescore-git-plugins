//==============================================
//  Commit to GitHub
//  Uses temp script + openUrlExternally (QProcess unreliable in MuseScore 4.x)
//==============================================

import QtQuick 2.0
import MuseScore 3.0
import Muse.UiComponents 1.0
import FileIO 3.0

MuseScore {
    id: commitPlugin
    title: "Commit to GitHub"
    categoryCode: "composing-arranging-tools"
    menuPath: "Plugins.Commit to GitHub"
    description: "Commit to https://github.com/wwang038/musescoretest.git"
    version: "2.1"
    requiresScore: true

    FileIO {
        id: fileIO
    }

    onRun: {
        if (typeof curScore == 'undefined' || curScore == null) {
            quit();
            return;
        }


        var scoreName = curScore.scoreName;
        var pluginDirUrl = Qt.resolvedUrl(".");
        var pluginDirStr = pluginDirUrl.toString ? pluginDirUrl.toString() : ("" + pluginDirUrl);
        var pluginDir = pluginDirStr.replace("file:///", "");
        var scriptPath = pluginDir + "/musescore-git-push.bat";

        var script = "@echo off\ncd /d \"%~dp0..\\Scores\"\nif exist \"" + scoreName + ".mscz\" git add \"" + scoreName + ".mscz\"\nif exist \"" + scoreName + ".mscx\" git add \"" + scoreName + ".mscx\"\ngit commit -m \"Commit from MuseScore plugin: " + scoreName + "\"\ngit push\npause";
        fileIO.source = scriptPath;
        if (fileIO.exists()) fileIO.remove();
        fileIO.write(script);

        var fileUrl = "file:///" + scriptPath.replace(/\\/g, "/");
        Qt.openUrlExternally(fileUrl);

        var cleanup = Qt.createQmlObject('import QtQuick 2.0; Timer { interval: 1500; repeat: false }', commitPlugin, "cleanupTimer");
        cleanup.triggered.connect(function() {
            fileIO.source = scriptPath;
            fileIO.remove();
            quit();
        });
        cleanup.start();
    }
}